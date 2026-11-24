using System.Text.Json;
using System.Text.Json.Serialization;

namespace Cyberpad;

sealed class Device
{
    [JsonPropertyName("id")] public string Id { get; set; } = "";
    [JsonPropertyName("name")] public string Name { get; set; } = "";
    /// <summary>SHA-256 van het token; het token zelf wordt nergens op de pc bewaard.</summary>
    [JsonPropertyName("tokenHash")] public string TokenHash { get; set; } = "";
    [JsonPropertyName("created")] public DateTime Created { get; set; }
    [JsonPropertyName("lastSeen")] public DateTime? LastSeen { get; set; }
    [JsonPropertyName("profile")] public string? Profile { get; set; }
    [JsonPropertyName("viewport")] public Viewport? Viewport { get; set; }
}

sealed record Viewport(
    [property: JsonPropertyName("w")] int W, [property: JsonPropertyName("h")] int H,
    [property: JsonPropertyName("vw")] int Vw, [property: JsonPropertyName("vh")] int Vh);

/// <summary>Koppelcodes, tokens per tablet en bescherming tegen raden (zelfde regels als op de Mac).</summary>
sealed class Pairing
{
    public const int CodeLifetimeSeconds = 120;
    const int MaxFailuresPerIP = 5;
    const int BlockSeconds = 60;
    const int MaxFailuresPerCode = 20;

    readonly object gate = new();
    readonly string storePath = Path.Combine(Paths.Support, "devices.json");
    readonly Dictionary<string, (int Count, DateTime? BlockedUntil)> failures = new();
    int failuresThisCode;
    DateTime lastSaved = DateTime.MinValue;
    List<Device> devices = new();

    public string Code { get; private set; } = "";
    public DateTime CodeExpires { get; private set; } = DateTime.MinValue;
    public event Action? Changed;
    public event Action<string>? Revoked;

    public Pairing()
    {
        Load();
        Rotate();
    }

    public List<Device> Devices { get { lock (gate) return devices.ToList(); } }

    public void Rotate()
    {
        lock (gate)
        {
            Code = (System.Security.Cryptography.RandomNumberGenerator.GetInt32(0, 1_000_000)).ToString("D6");
            CodeExpires = DateTime.UtcNow.AddSeconds(CodeLifetimeSeconds);
            failuresThisCode = 0;
        }
        Changed?.Invoke();
    }

    public void RotateIfExpired()
    {
        if (DateTime.UtcNow >= CodeExpires) Rotate();
    }

    public enum Outcome { Ok, Wrong, Blocked }

    public (Outcome Result, string? Token, Device? Device, int Number) Pair(string input, string name, string ip)
    {
        RotateIfExpired();
        var now = DateTime.UtcNow;
        string token;
        Device device;
        lock (gate)
        {
            if (failures.TryGetValue(ip, out var f0) && f0.BlockedUntil is { } until && until > now)
                return (Outcome.Blocked, null, null, (int)Math.Ceiling((until - now).TotalSeconds));

            var digits = new string(input.Where(char.IsDigit).ToArray());
            if (!Crypto.ConstantTimeEqual(digits, Code))
            {
                var f = failures.TryGetValue(ip, out var x) ? x : (0, null);
                f.Count++;
                if (f.Count >= MaxFailuresPerIP)
                {
                    failures[ip] = (0, now.AddSeconds(BlockSeconds));
                    return (Outcome.Blocked, null, null, BlockSeconds);
                }
                failures[ip] = f;
                failuresThisCode++;
                if (failuresThisCode >= MaxFailuresPerCode) Rotate(); // tegen raden vanaf veel adressen
                return (Outcome.Wrong, null, null, MaxFailuresPerIP - f.Count);
            }

            failures.Remove(ip);
            token = Crypto.RandomHex(32);
            var clean = (name ?? "").Trim();
            if (clean.Length == 0) clean = "Tablet";
            if (clean.Length > 40) clean = clean[..40];
            device = new Device { Id = Guid.NewGuid().ToString().ToUpperInvariant(), Name = clean, TokenHash = Crypto.Sha256(token), Created = now, LastSeen = now };
            devices.Add(device);
            SaveLocked();
        }
        Rotate(); // een code werkt maar één keer
        return (Outcome.Ok, token, device, 0);
    }

    public Device? Authenticate(string? token)
    {
        if (token == null || token.Length != 64) return null;
        var h = Crypto.Sha256(token);
        lock (gate)
        {
            var d = devices.FirstOrDefault(x => Crypto.ConstantTimeEqual(x.TokenHash, h));
            if (d == null) return null;
            d.LastSeen = DateTime.UtcNow;
            if ((DateTime.UtcNow - lastSaved).TotalSeconds > 60) SaveLocked();
            return d;
        }
    }

    public void SetViewport(string id, Viewport v)
    {
        static bool ok(int n) => n >= 100 && n <= 5000;
        if (!ok(v.W) || !ok(v.H) || !ok(v.Vw) || !ok(v.Vh)) return;
        lock (gate)
        {
            var d = devices.FirstOrDefault(x => x.Id == id);
            if (d == null || d.Viewport == v) return;
            d.Viewport = v;
            SaveLocked();
        }
    }

    public void Revoke(string id)
    {
        lock (gate)
        {
            devices.RemoveAll(x => x.Id == id);
            SaveLocked();
        }
        Revoked?.Invoke(id);
        Changed?.Invoke();
    }

    void Load()
    {
        try
        {
            if (File.Exists(storePath))
                devices = JsonSerializer.Deserialize<List<Device>>(File.ReadAllText(storePath)) ?? new();
        }
        catch { devices = new(); }
    }

    void SaveLocked()
    {
        try
        {
            Files.WriteAtomic(storePath, JsonSerializer.Serialize(devices, Json.Pretty));
            lastSaved = DateTime.UtcNow;
        }
        catch { }
    }
}
