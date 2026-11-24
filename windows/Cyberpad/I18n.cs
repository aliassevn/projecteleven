using System.Text.Json;
using System.Text.Json.Nodes;

namespace Cyberpad;

/// <summary>
/// Taal van Cyberpad: Engels (standaard), Nederlands of Spaans. Zelfde opzet als op de Mac (Localizer.swift):
/// de Nederlandse tekst is de sleutel, shared\i18n\en.json en es.json geven de vertaling.
/// </summary>
static class I18n
{
    public static readonly (string Code, string Name)[] Languages = { ("en", "English"), ("nl", "Nederlands"), ("es", "Español") };
    public const string DefaultLanguage = "en";

    static readonly Dictionary<string, Dictionary<string, string>> Dicts = new();
    static bool forceDutch;
    static HashSet<string>? builtIn;

    public static string Lang { get; private set; } = DefaultLanguage;
    public static event Action<string>? Changed;

    public static void Load()
    {
        foreach (var (code, _) in Languages)
        {
            if (code == "nl") continue;
            try
            {
                var file = Path.Combine(Paths.I18n, code + ".json");
                var obj = JsonNode.Parse(File.ReadAllText(file))?.AsObject();
                var d = new Dictionary<string, string>();
                if (obj != null)
                    foreach (var kv in obj)
                        if (!kv.Key.StartsWith('_') && kv.Value is JsonValue v && v.TryGetValue(out string? s)) d[kv.Key] = s;
                Dicts[code] = d;
            }
            catch { Dicts[code] = new(); }
        }
        var saved = Settings.Get("language");
        Lang = IsValid(saved) ? saved! : DefaultLanguage;
    }

    public static bool IsValid(string? code) => code != null && Languages.Any(l => l.Code == code);

    public static void Set(string code)
    {
        if (!IsValid(code) || code == Lang) return;
        Lang = code;
        Settings.Set("language", code);
        Changed?.Invoke(code);
    }

    public static string Translate(string s) =>
        forceDutch ? s : (Dicts.TryGetValue(Lang, out var d) && d.TryGetValue(s, out var t) ? t : s);

    /// <summary>Vertaal een Nederlandse tekst; {0}, {1}… worden ingevuld.</summary>
    public static string L(string s, params object?[] args)
    {
        var o = Translate(s);
        for (var i = 0; i < args.Length; i++) o = o.Replace("{" + i + "}", Convert.ToString(args[i], System.Globalization.CultureInfo.InvariantCulture));
        return o;
    }

    /// <summary>Namen uit de standaard-layout (Nederlands): die toont de tablet in de gekozen taal.</summary>
    public static HashSet<string> BuiltInNames
    {
        get
        {
            if (builtIn != null) return builtIn;
            forceDutch = true;
            try
            {
                var names = new HashSet<string>();
                var l = DefaultLayout.Build();
                foreach (var p in Lay.Pages(l))
                {
                    names.Add(Lay.Str(p, "name") ?? "");
                    foreach (var t in Lay.Tiles(p)) names.Add(Lay.Str(t, "label") ?? "");
                }
                foreach (var pr in Lay.Arr(l, "profiles")) names.Add(Lay.Str(pr, "name") ?? "");
                names.UnionWith(new[] { "Agenda", "Herinneringen", "Notities" });
                builtIn = names;
            }
            finally { forceDutch = false; }
            return builtIn;
        }
    }

    public static string DisplayName(string s) => BuiltInNames.Contains(s) ? Translate(s) : s;

    public static Dictionary<string, string> Dictionary => Dicts.TryGetValue(Lang, out var d) ? d : new();

    /// <summary>GET /i18n.js: zet CP_LANG en CP_I18N voordat pad.js of editor.js start.</summary>
    public static string Script()
    {
        var json = JsonSerializer.Serialize(new SortedDictionary<string, string>(Dictionary, StringComparer.Ordinal));
        json = json.Replace("</", "<\\/");
        return "window.CP_LANG=\"" + Lang + "\";window.CP_I18N=" + json + ";\n";
    }
}
