using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cyberpad;

static class Json
{
    public static readonly JsonSerializerOptions Pretty = new()
    {
        WriteIndented = true,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };
    public static readonly JsonSerializerOptions Compact = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static string Serialize(object? o) => o is JsonNode n ? n.ToJsonString(Compact) : JsonSerializer.Serialize(o, Compact);

    /// <summary>Gewone .NET-waarden (Dictionary, List, string, getallen…) naar een JsonNode.</summary>
    public static JsonNode? ToNode(object? o) => o switch
    {
        null => null,
        JsonNode n => n.DeepClone(),
        _ => JsonSerializer.SerializeToNode(o, Compact),
    };
}

static class Files
{
    /// <summary>Schrijft via een tijdelijk bestand, zodat een half geschreven bestand nooit blijft staan.</summary>
    public static void WriteAtomic(string path, string text)
    {
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, text, new UTF8Encoding(false));
        File.Move(tmp, path, true);
    }
}

static class Crypto
{
    public static string RandomHex(int bytes) => Convert.ToHexString(RandomNumberGenerator.GetBytes(bytes)).ToLowerInvariant();

    public static string Sha256(string s) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(s))).ToLowerInvariant();

    public static bool ConstantTimeEqual(string a, string b) =>
        CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(a), Encoding.UTF8.GetBytes(b));
}

static class NetUtil
{
    /// <summary>Alleen het lokale netwerk: loopback, privé-adressen (10/8, 172.16/12, 192.168/16), link-local en IPv6 ULA.</summary>
    public static bool IsLocal(IPAddress? ip)
    {
        if (ip == null) return false;
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        if (IPAddress.IsLoopback(ip)) return true;
        if (ip.AddressFamily == AddressFamily.InterNetwork)
        {
            var b = ip.GetAddressBytes();
            return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254);
        }
        if (ip.AddressFamily == AddressFamily.InterNetworkV6)
        {
            if (ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal) return true;
            var b = ip.GetAddressBytes();
            return (b[0] & 0xFE) == 0xFC; // fc00::/7
        }
        return false;
    }

    public static bool IsLoopback(IPAddress? ip)
    {
        if (ip == null) return false;
        if (ip.IsIPv4MappedToIPv6) ip = ip.MapToIPv4();
        return IPAddress.IsLoopback(ip);
    }

    /// <summary>IPv4-adressen van deze pc op actieve netwerkkaarten (voor het koppelvenster).</summary>
    public static List<string> LocalIPv4()
    {
        var out_ = new List<string>();
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
                var desc = (ni.Description + " " + ni.Name).ToLowerInvariant();
                if (desc.Contains("virtual") || desc.Contains("vmware") || desc.Contains("hyper-v") || desc.Contains("vethernet")) continue;
                foreach (var a in ni.GetIPProperties().UnicastAddresses)
                    if (a.Address.AddressFamily == AddressFamily.InterNetwork && IsLocal(a.Address) && !IPAddress.IsLoopback(a.Address))
                        out_.Add(a.Address.ToString());
            }
        }
        catch { }
        return out_.Distinct().ToList();
    }
}

/// <summary>Hulpjes om een layout (JsonObject) te lezen zonder vaste klassen; onbekende velden blijven zo bewaard.</summary>
static class Lay
{
    public static string? Str(JsonNode? o, string key) =>
        o is JsonObject obj && obj[key] is JsonValue v && v.TryGetValue(out string? s) ? s : null;

    public static int? Int(JsonNode? o, string key)
    {
        if (o is not JsonObject obj || obj[key] is not JsonValue v) return null;
        if (v.TryGetValue(out int i)) return i;
        if (v.TryGetValue(out double d) && Math.Abs(d - Math.Round(d)) < 1e-9) return (int)Math.Round(d);
        return null;
    }

    public static double? Num(JsonNode? o, string key)
    {
        if (o is not JsonObject obj || obj[key] is not JsonValue v) return null;
        if (v.TryGetValue(out double d)) return d;
        if (v.TryGetValue(out int i)) return i;
        return null;
    }

    public static bool? Bool(JsonNode? o, string key) =>
        o is JsonObject obj && obj[key] is JsonValue v && v.TryGetValue(out bool b) ? b : null;

    public static JsonObject? Obj(JsonNode? o, string key) => o is JsonObject obj ? obj[key] as JsonObject : null;

    public static IEnumerable<JsonObject> Arr(JsonNode? o, string key) =>
        o is JsonObject obj && obj[key] is JsonArray a ? a.OfType<JsonObject>() : Enumerable.Empty<JsonObject>();

    public static List<string> StrList(JsonNode? o, string key)
    {
        var r = new List<string>();
        if (o is JsonObject obj && obj[key] is JsonArray a)
            foreach (var x in a) if (x is JsonValue v && v.TryGetValue(out string? s)) r.Add(s);
        return r;
    }

    public static IEnumerable<JsonObject> Pages(JsonObject layout) => Arr(layout, "pages");
    public static IEnumerable<JsonObject> Tiles(JsonObject page) => Arr(page, "tiles");

    public static JsonObject? Tile(JsonObject layout, string id) =>
        Pages(layout).SelectMany(Tiles).FirstOrDefault(t => Str(t, "id") == id);

    public static string Kind(JsonObject tile) => Str(tile, "kind") ?? "button";
    public static bool IsButton(JsonObject tile) => Kind(tile) == "button";

    public static readonly HashSet<string> WidgetKinds = new()
        { "weather", "nowplaying", "timer", "pomodoro", "worldclock", "photos", "stats", "terminal", "ha", "mqtt", "plugin" };
    public static bool IsWidget(JsonObject tile) => WidgetKinds.Contains(Kind(tile));

    public static JsonObject? Config(JsonObject tile) => Obj(tile, "config");
}
