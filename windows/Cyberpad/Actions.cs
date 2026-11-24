using System.Text.Json.Nodes;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Voert acties uit de layout uit. Zelfde actietypes als op de Mac (README); wat Windows (nog) niet kan, meldt dat netjes.</summary>
sealed class Actions
{
    const int MaxMacroSteps = 50;
    const int MaxDelayMs = 10_000;

    readonly Dictionary<string, bool> toggles = new();
    readonly object gate = new();
    bool keepAwake;

    public Catalog Catalog { get; } = Catalog.Load();
    /// <summary>Fouten die pas later komen (macrostappen): als melding naar de tablets.</summary>
    public event Action<string>? AsyncError;

    public static string? StateKey(string? type) => type switch
    {
        "audio.mute" => "muted",
        "audio.micMute" => "micMuted",
        "system.keepAwake" => "keepAwake",
        "system.darkMode" => "darkMode",
        "audio.volume" => "volume",
        "audio.micVolume" => "micVolume",
        _ => null,
    };

    public Dictionary<string, object?> State()
    {
        var s = new Dictionary<string, object?>();
        if (Audio.Muted() is { } m) s["muted"] = m;
        if (Audio.Muted(true) is { } mm) s["micMuted"] = mm;
        if (Audio.Volume() is { } v) s["volume"] = Math.Round(v, 3);
        if (Audio.Volume(true) is { } mv) s["micVolume"] = Math.Round(mv, 3);
        s["keepAwake"] = keepAwake;
        try { s["darkMode"] = Native.DarkMode; } catch { }
        lock (gate) s["toggles"] = new Dictionary<string, bool>(toggles);
        return s;
    }

    /// <summary>Een tegel indrukken. Bij een aan/uit-knop wisselt de stand en wordt bij "uit" offAction gebruikt.</summary>
    public void Press(JsonObject tile, string gesture)
    {
        var id = Lay.Str(tile, "id") ?? "";
        JsonObject? action;
        switch (gesture)
        {
            case "long": action = Lay.Obj(tile, "longPress"); break;
            case "double": action = Lay.Obj(tile, "doubleTap"); break;
            default:
                if (Lay.Bool(tile, "toggle") == true)
                {
                    bool on;
                    lock (gate) on = !(toggles.TryGetValue(id, out var cur) && cur);
                    action = on ? Lay.Obj(tile, "action") : (Lay.Obj(tile, "offAction") ?? Lay.Obj(tile, "action"));
                    if (action == null) throw new ActionException(L("Ontbreekt in layout: {0}", "action"));
                    lock (gate) toggles[id] = on;
                    try { Run(action, () => { lock (gate) toggles[id] = !on; }); }
                    catch { lock (gate) toggles[id] = !on; throw; }
                    return;
                }
                action = Lay.Obj(tile, "action");
                break;
        }
        if (action == null)
            throw new ActionException(L("Ontbreekt in layout: {0}", gesture == "long" ? "longPress" : gesture == "double" ? "doubleTap" : "action"));
        Run(action);
    }

    public void Run(JsonObject a, Action? onLateFailure = null)
    {
        var type = Lay.Str(a, "type") ?? "";
        switch (type)
        {
            // Media
            case "media.playPause": Native.Tap(0xB3); break;
            case "media.next": Native.Tap(0xB0); break;
            case "media.previous": Native.Tap(0xB1); break;

            // Geluid
            case "audio.volumeUp": Audio.ChangeVolume(1f / 16); break;
            case "audio.volumeDown": Audio.ChangeVolume(-1f / 16); break;
            case "audio.mute": Audio.ToggleMute(); break;
            case "audio.micMute": Audio.ToggleMute(true); break;

            // Apps en links
            case "app.open":
                Apps.Open(Lay.Str(a, "app") ?? "");
                break;
            case "url.open":
                var url = Lay.Str(a, "url");
                if (url == null || !Uri.TryCreate(url, UriKind.Absolute, out var u) || (u.Scheme != "http" && u.Scheme != "https"))
                    throw new ActionException(L("Ontbreekt in layout: {0}", "geldige http(s)-url"));
                Apps.OpenUrl(u.AbsoluteUri, Lay.Str(a, "app"));
                break;

            // Toetsen en tekst
            case "keys.press":
                Native.Press(Native.Parse(Lay.Str(a, "keys") ?? throw new ActionException(L("Ontbreekt in layout: {0}", "keys"))));
                break;
            case "text.type":
                Native.Type(Lay.Str(a, "text") ?? throw new ActionException(L("Ontbreekt in layout: {0}", "text")));
                break;
            case "preset":
                RunPreset(Lay.Str(a, "preset") ?? throw new ActionException(L("Ontbreekt in layout: {0}", "preset")));
                break;
            case "macro":
                RunMacro(Lay.Arr(a, "steps").ToList(), onLateFailure);
                break;
            case "delay":
                throw new ActionException(L("Een pauze (delay) kan alleen binnen een macro"));

            // Systeem
            case "system.lock": Native.Lock(); break;
            case "system.displayOff": Native.DisplayOff(); break;
            case "system.screenshot": Native.Press(Native.Parse("win+printscreen")); break;
            case "system.screenshotArea": Native.Press(Native.Parse("win+shift+s")); break;
            case "system.keepAwake":
                keepAwake = !keepAwake;
                var on = keepAwake;
                Program.OnUi(() => Native.KeepAwake(on));
                break;
            case "system.darkMode": Native.ToggleDarkMode(); break;

            // Nog niet op Windows (volgende stap): Opdrachten, smart home, webhooks, plugins.
            case "shortcut.run":
                throw new ActionException(L("Opdrachten (Shortcuts) bestaan alleen op de Mac"));
            case "ha.toggle": case "ha.service": case "ha.level": case "mqtt.publish": case "webhook.call": case "plugin":
                throw new ActionException(L("Nog niet beschikbaar op Windows: {0}", type));

            default:
                throw new ActionException(L("Onbekende actie: {0}", type));
        }
    }

    /// <summary>Draaiknop: steps tikken (positief = met de klok mee).</summary>
    public void Dial(JsonObject tile, int steps)
    {
        var a = Lay.Obj(tile, "action") ?? throw new ActionException(L("Ontbreekt in layout: {0}", "action"));
        var n = Math.Clamp(steps, -20, 20);
        if (n == 0) return;
        var cfg = Lay.Config(tile);
        var step = Math.Clamp(Lay.Num(cfg, "step") ?? 0.03, 0.005, 0.5);
        switch (Lay.Str(a, "type"))
        {
            case "audio.volume": Audio.ChangeVolume((float)(n * step)); break;
            case "audio.micVolume": Audio.ChangeVolume((float)(n * step), true); break;
            case "pointer.scroll":
                Native.Scroll(0, n * 40 * (Lay.Num(cfg, "speed") ?? 1), Lay.Bool(cfg, "natural") ?? true);
                break;
            default:
                JsonObject act;
                if (n > 0) act = a;
                else act = Lay.Obj(tile, "offAction") ?? throw new ActionException(L("Ontbreekt in layout: {0}", L("offAction (tegen de klok in)")));
                for (var i = 0; i < Math.Min(Math.Abs(n), 10); i++) Run(act);
                break;
        }
    }

    public void SetSlider(JsonObject a, double value)
    {
        switch (Lay.Str(a, "type"))
        {
            case "audio.volume": Audio.SetVolume((float)value); break;
            case "audio.micVolume": Audio.SetVolume((float)value, true); break;
            case "ha.level": throw new ActionException(L("Nog niet beschikbaar op Windows: {0}", "ha.level"));
            default: throw new ActionException(L("Onbekende actie: {0}", Lay.Str(a, "type") ?? ""));
        }
    }

    // ---------- Shortcut-bibliotheek ----------

    void RunPreset(string id)
    {
        var (app, keys) = Catalog.Find(id) ?? throw new ActionException(L("Onbekende sneltoets uit de bibliotheek: {0}", id));
        var combo = Native.Parse(keys);
        // De sneltoets gaat naar het venster dat vooraan staat. Activeren van de juiste app volgt later.
        _ = app;
        Native.Press(combo);
    }

    // ---------- Macro's ----------

    void RunMacro(List<JsonObject> steps, Action? onFail)
    {
        if (steps.Count == 0) throw new ActionException(L("Ontbreekt in layout: {0}", "steps"));
        if (steps.Count > MaxMacroSteps) throw new ActionException(L("Een macro mag maximaal {0} stappen hebben", MaxMacroSteps));
        if (steps.Any(s => Lay.Str(s, "type") == "macro")) throw new ActionException(L("Een macro kan geen andere macro bevatten"));
        foreach (var s in steps.Where(s => Lay.Str(s, "type") == "keys.press")) Native.Parse(Lay.Str(s, "keys") ?? "");
        _ = Task.Run(async () =>
        {
            foreach (var step in steps)
            {
                if (Lay.Str(step, "type") == "delay")
                {
                    await Task.Delay(Math.Clamp(Lay.Int(step, "ms") ?? 0, 0, MaxDelayMs));
                    continue;
                }
                try { Run(step, onFail); }
                catch (Exception e)
                {
                    onFail?.Invoke();
                    AsyncError?.Invoke(L("Macro gestopt: {0}", e.Message));
                    return;
                }
                await Task.Delay(40); // adempauze zodat apps de toetsen bijhouden
            }
        });
    }
}

/// <summary>shared\catalog\shortcuts.json: sneltoetsen per app. Op Windows "keysWindows", anders "keys" met cmd → Ctrl.</summary>
sealed class Catalog
{
    public sealed record Shortcut(string Id, string Label, string Keys);
    public sealed record App(string Id, string Name, List<Shortcut> Shortcuts);

    public List<App> AppsList { get; } = new();

    public static Catalog Load()
    {
        var c = new Catalog();
        try
        {
            var root = JsonNode.Parse(File.ReadAllText(Path.Combine(Paths.Catalog, "shortcuts.json"))) as JsonObject;
            foreach (var a in Lay.Arr(root, "apps"))
            {
                var list = new List<Shortcut>();
                foreach (var s in Lay.Arr(a, "shortcuts"))
                {
                    var keys = Lay.Str(s, "keysWindows") ?? Lay.Str(s, "keys");
                    if (keys == null) continue;
                    list.Add(new Shortcut(Lay.Str(s, "id") ?? "", Lay.Str(s, "label") ?? "", keys));
                }
                c.AppsList.Add(new App(Lay.Str(a, "id") ?? "", Lay.Str(a, "name") ?? "", list));
            }
        }
        catch { }
        return c;
    }

    public (App App, string Keys)? Find(string id)
    {
        var dot = id.IndexOf('.');
        if (dot < 1) return null;
        var app = AppsList.FirstOrDefault(a => a.Id == id[..dot]);
        var sc = app?.Shortcuts.FirstOrDefault(s => s.Id == id[(dot + 1)..]);
        return app != null && sc != null ? (app, sc.Keys) : null;
    }
}
