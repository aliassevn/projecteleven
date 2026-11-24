using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Thema's (shared\themes) en de tablet-CSS: het sjabloon shared\pad\pad.css met de kleuren ingevuld.
/// Zelfde regels als ThemeStore.swift; zie docs\THEMES.md.</summary>
sealed class ThemeStore
{
    public static readonly string[] ColorKeys = { "bg", "bg2", "text", "accent", "accent2", "accent2Text", "danger", "dangerText", "ok", "okText",
        "panel", "panelBorder", "button", "buttonText", "buttonBorder", "buttonActive", "buttonActiveText" };
    public static readonly string[] EffectKeys = { "scanlines", "glow", "grid", "corner", "glitch", "upper", "bold" };

    readonly object gate = new();
    List<JsonObject> themes = new();
    (string Key, string Css)? cache;

    public ThemeStore() => Reload();

    public List<JsonObject> All { get { lock (gate) return themes.Select(t => (JsonObject)t.DeepClone()).ToList(); } }

    public void Reload()
    {
        var list = new List<JsonObject>();
        try
        {
            foreach (var f in Directory.GetFiles(Paths.Themes, "*.json"))
                try { if (JsonNode.Parse(File.ReadAllText(f)) is JsonObject o && Lay.Str(o, "id") != null) list.Add(o); } catch { }
        }
        catch { }
        list.Sort((a, b) =>
        {
            if (Lay.Str(a, "id") == "cyberdeck") return -1;
            if (Lay.Str(b, "id") == "cyberdeck") return 1;
            return string.CompareOrdinal(Lay.Str(a, "name"), Lay.Str(b, "name"));
        });
        lock (gate) themes = list;
    }

    JsonObject? Base(string? id)
    {
        lock (gate)
            return themes.FirstOrDefault(t => Lay.Str(t, "id") == id) ?? themes.FirstOrDefault(t => Lay.Str(t, "id") == "cyberdeck") ?? themes.FirstOrDefault();
    }

    static readonly Regex Color = new("^#[0-9a-fA-F]{6}$");
    static readonly Regex Font = new("^[A-Za-z0-9 ,\"'\\-]+$");
    public static bool ValidFont(string s) => s.Length > 0 && s.Length <= 200 && Font.IsMatch(s);

    public static List<string> OverrideProblems(JsonObject? o)
    {
        var r = new List<string>();
        if (o == null) return r;
        if (Lay.Obj(o, "colors") is { } cols)
            foreach (var kv in cols)
            {
                if (!ColorKeys.Contains(kv.Key)) r.Add(L("Onbekende themakleur “{0}”", kv.Key));
                if (kv.Value is not JsonValue v || !v.TryGetValue(out string? s) || !Color.IsMatch(s)) r.Add($"Kleur {kv.Key} moet als #rrggbb");
            }
        if (Lay.Str(o, "font") is { } f && !ValidFont(f)) r.Add(L("Lettertype mag alleen letters, cijfers, spaties, komma's en aanhalingstekens bevatten"));
        if (Lay.Num(o, "radius") is { } rad && (rad < 0 || rad > 30)) r.Add(L("Afronding moet tussen 0 en 30 liggen"));
        if (Lay.Obj(o, "effects") is { } fx)
            foreach (var kv in fx) if (!EffectKeys.Contains(kv.Key)) r.Add(L("Onbekend effect “{0}”", kv.Key));
        return r;
    }

    /// <summary>Thema uit de layout plus eigen aanpassingen (alleen geldige waarden).</summary>
    public JsonObject? Resolve(JsonObject layout)
    {
        var b = Base(Lay.Str(layout, "theme"));
        if (b == null) return null;
        var t = (JsonObject)b.DeepClone();
        var colors = Lay.Obj(t, "colors") ?? new JsonObject();
        t["colors"] = colors;
        var fx = Lay.Obj(t, "effects") ?? new JsonObject();
        t["effects"] = fx;
        if (Lay.Obj(layout, "themeOverrides") is { } o)
        {
            if (Lay.Obj(o, "colors") is { } oc)
                foreach (var kv in oc)
                    if (ColorKeys.Contains(kv.Key) && kv.Value is JsonValue v && v.TryGetValue(out string? s) && Color.IsMatch(s)) colors[kv.Key] = s;
            if (Lay.Str(o, "font") is { } f && ValidFont(f)) t["font"] = f;
            if (Lay.Num(o, "radius") is { } r && r >= 0 && r <= 30) t["radius"] = r;
            if (Lay.Obj(o, "effects") is { } oe)
                foreach (var kv in oe)
                    if (EffectKeys.Contains(kv.Key) && kv.Value is JsonValue v && v.TryGetValue(out bool bv)) fx[kv.Key] = bv;
        }
        return t;
    }

    public static string Classes(JsonObject t)
    {
        var fx = Lay.Obj(t, "effects");
        bool on(string k) => Lay.Bool(fx, k) == true;
        var c = new List<string>();
        if (!on("scanlines")) c.Add("fx-noscan");
        if (!on("glow")) c.Add("fx-noglow");
        if (!on("grid")) c.Add("fx-nogrid");
        if (!on("corner")) c.Add("fx-nocorner");
        if (on("glitch")) c.Add("fx-glitch");
        if (on("upper")) c.Add("fx-upper");
        if (on("bold")) c.Add("fx-bold");
        return string.Join(' ', c);
    }

    public static string Key(JsonObject t) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(t.ToJsonString()))).ToLowerInvariant()[..12];

    public string? Css(JsonObject layout)
    {
        var template = Path.Combine(Paths.Pad, "pad.css");
        var t = Resolve(layout);
        try
        {
            if (t == null) return File.ReadAllText(template);
            var key = Key(t) + File.GetLastWriteTimeUtc(template).Ticks;
            lock (gate) if (cache is { } c && c.Key == key) return c.Css;
            var css = Render(File.ReadAllText(template), t);
            lock (gate) cache = (key, css);
            return css;
        }
        catch { return null; }
    }

    /// <summary>Kleuren die een thema mag weglaten worden afgeleid (het oude uiterlijk).</summary>
    static Dictionary<string, string> Derived(JsonObject colorsNode)
    {
        var c = new Dictionary<string, string>();
        foreach (var kv in colorsNode) if (kv.Value is JsonValue v && v.TryGetValue(out string? s)) c[kv.Key] = s;
        string rgba(string key, double a)
        {
            if (!c.TryGetValue(key, out var hex) || hex.Length != 7) return "transparent";
            var v = Convert.ToInt32(hex[1..], 16);
            return $"rgba({(v >> 16) & 0xff},{(v >> 8) & 0xff},{v & 0xff},{a.ToString(CultureInfo.InvariantCulture)})";
        }
        var d = new Dictionary<string, string>(c);
        if (!d.ContainsKey("panel")) d["panel"] = rgba("accent", 0.04);
        if (!d.ContainsKey("panelBorder")) d["panelBorder"] = rgba("accent", 0.45);
        if (!d.ContainsKey("button")) d["button"] = d["panel"];
        if (!d.ContainsKey("buttonBorder")) d["buttonBorder"] = d["panelBorder"];
        if (!d.ContainsKey("buttonText")) d["buttonText"] = rgba("text", 0.75);
        if (!d.ContainsKey("buttonActive")) d["buttonActive"] = rgba("accent2", 0.12);
        if (!d.ContainsKey("buttonActiveText")) d["buttonActiveText"] = c.TryGetValue("accent2Text", out var at) ? at : "inherit";
        return d;
    }

    static readonly Regex Placeholder = new(@"\{\{(\w+)(?:\s+([0-9.]+))?\}\}");

    /// <summary>{{naam}} → waarde, {{kleur 0.4}} → rgba(r,g,b,0.4).</summary>
    public static string Render(string src, JsonObject t)
    {
        var colors = Derived(Lay.Obj(t, "colors") ?? new JsonObject());
        return Placeholder.Replace(src, m =>
        {
            var name = m.Groups[1].Value;
            var alpha = m.Groups[2].Success ? m.Groups[2].Value : null;
            switch (name)
            {
                case "font": return Lay.Str(t, "font") ?? "sans-serif";
                case "radius": return (Lay.Num(t, "radius") ?? 0).ToString("0.##", CultureInfo.InvariantCulture);
            }
            if (!colors.TryGetValue(name, out var value)) return "transparent";
            if (value.Length != 7 || value[0] != '#' || alpha == null) return value;
            var v = Convert.ToInt32(value[1..], 16);
            return $"rgba({(v >> 16) & 0xff},{(v >> 8) & 0xff},{v & 0xff},{alpha})";
        });
    }
}
