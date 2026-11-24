using System.Text.Json.Nodes;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Houdt alle onderdelen bij elkaar (zoals Core.swift op de Mac).</summary>
sealed class Core
{
    public readonly Pairing Pairing = new();
    public readonly LayoutStore Layouts = new();
    public readonly ThemeStore Themes = new();
    public readonly Actions Actions = new();
    public readonly Widgets Widgets = new();
    public readonly Server Server;

    readonly System.Threading.Timer ticker;
    readonly Dictionary<string, string?> lastProfiles = new();
    string lastState = "";
    int tick;

    /// <summary>Iets veranderd dat het systeemvak-menu moet laten zien (tablets, code, fouten).</summary>
    public event Action? UiChanged;

    public Core()
    {
        _ = BuiltInNames; // vooraf vullen
        Server = new Server(this);
        Widgets.Update(Layouts.Current);

        Layouts.Changed += () =>
        {
            Widgets.Update(Layouts.Current);
            Server.BroadcastLayout();
            Server.ScheduleState();
            UiChanged?.Invoke();
        };
        Widgets.Changed += Server.ScheduleState;
        Widgets.Toast += msg => Server.Broadcast(new { type = "toast", text = msg });
        Actions.AsyncError += msg => Server.Broadcast(new { type = "toast", text = msg });
        Pairing.Revoked += id => Server.Disconnect(id);
        Pairing.Changed += () => UiChanged?.Invoke();
        I18n.Changed += _ =>
        {
            Server.BroadcastLayout();
            Server.ScheduleState();
            UiChanged?.Invoke();
        };

        ticker = new System.Threading.Timer(_ => Tick(), null, 1000, 1000);
    }

    public Task StartAsync() => Server.StartAsync();

    public void ClientsChanged() => UiChanged?.Invoke();

    void Tick()
    {
        try
        {
            tick++;
            Pairing.RotateIfExpired();
            var active = Server.HasClients;
            Widgets.Tick(active);
            if (!active) return;
            // Volume of mute buiten Cyberpad om veranderd? Dan de tablets bijwerken.
            var s = Json.Serialize(FullState());
            if (s != lastState) { lastState = s; Server.BroadcastState(); }
            // Profielen op tijd: wisselt het profiel van een tablet, dan krijgt die een nieuwe layout.
            if (tick % 20 == 0)
            {
                var l = Layouts.Current;
                var changed = false;
                foreach (var d in Pairing.Devices)
                {
                    var p = Lay.Str(LayoutStore.ActiveProfile(l, d.Profile, DateTime.Now), "id");
                    if (!lastProfiles.TryGetValue(d.Id, out var old) || old != p) { lastProfiles[d.Id] = p; changed = true; }
                }
                if (changed && tick > 20) Server.BroadcastLayout();
            }
        }
        catch { }
    }

    // ---------------------------------------------------------------- layout voor de tablet

    /// <summary>De layout zoals de tablet hem krijgt: alleen wat nodig is om te tekenen (geen acties).</summary>
    public Dictionary<string, object?> LayoutJson(string? deviceId)
    {
        var l = Layouts.Current;
        var devProfile = deviceId == null ? null : Pairing.Devices.FirstOrDefault(d => d.Id == deviceId)?.Profile;
        var profile = LayoutStore.ActiveProfile(l, devProfile, DateTime.Now);
        var allPages = Lay.Pages(l).ToList();
        var pages = allPages;
        if (profile != null)
        {
            var ids = Lay.StrList(profile, "pages");
            var chosen = ids.Select(id => allPages.FirstOrDefault(p => Lay.Str(p, "id") == id)).Where(p => p != null).Cast<JsonObject>().ToList();
            if (chosen.Count > 0) pages = chosen;
        }
        var d = new Dictionary<string, object?>
        {
            ["version"] = Lay.Int(l, "version") ?? 1, ["columns"] = Lay.Int(l, "columns") ?? 5, ["rows"] = Lay.Int(l, "rows") ?? 3,
            ["theme"] = Lay.Str(l, "theme") ?? "cyberdeck", ["lang"] = I18n.Lang,
            ["pages"] = pages.Select(p =>
            {
                var pd = new Dictionary<string, object?>
                {
                    ["id"] = Lay.Str(p, "id"), ["name"] = DisplayName(Lay.Str(p, "name") ?? ""),
                    ["tiles"] = Lay.Tiles(p).Select(PadTile).ToList(),
                };
                if (Lay.Int(p, "columns") is { } c && Lay.Int(p, "rows") is { } r) { pd["columns"] = c; pd["rows"] = r; }
                if (Lay.StrList(p, "apps").Count > 0) pd["context"] = true;
                return pd;
            }).ToList(),
        };
        if (profile != null)
            d["profile"] = new Dictionary<string, object?> { ["id"] = Lay.Str(profile, "id"), ["name"] = DisplayName(Lay.Str(profile, "name") ?? ""), ["fixed"] = devProfile != null };
        if (Themes.Resolve(l) is { } t)
        {
            d["themeClasses"] = ThemeStore.Classes(t);
            d["themeKey"] = ThemeStore.Key(t);
        }
        return d;
    }

    static Dictionary<string, object?> PadTile(JsonObject t)
    {
        var kind = Lay.Kind(t);
        var d = new Dictionary<string, object?>
        {
            ["id"] = Lay.Str(t, "id"), ["label"] = DisplayName(Lay.Str(t, "label") ?? ""), ["kind"] = kind,
            ["x"] = Lay.Int(t, "x") ?? 0, ["y"] = Lay.Int(t, "y") ?? 0,
        };
        if (Lay.Str(t, "icon") is { } icon) d["icon"] = icon;
        if (Lay.Str(t, "color") is { } color && LayoutStore.ValidColor(color)) d["color"] = color;
        if (Lay.Int(t, "w") is { } w) d["w"] = w;
        if (Lay.Int(t, "h") is { } h) d["h"] = h;
        if (kind == "terminal" && Lay.Bool(Lay.Config(t), "dangerous") == true) d["dangerous"] = true;
        if (kind == "agenda") d["count"] = Math.Clamp(Lay.Int(Lay.Config(t), "count") ?? 1, 1, 5);
        if (Lay.Obj(t, "longPress") != null) d["hasLong"] = true;
        if (Lay.Obj(t, "doubleTap") != null) d["hasDouble"] = true;
        if (Lay.Bool(t, "toggle") == true) d["toggle"] = true;
        else if (Actions.StateKey(Lay.Str(Lay.Obj(t, "action"), "type")) is { } key) d["stateKey"] = key;
        return d;
    }

    /// <summary>Alles wat de tablet aan status nodig heeft.</summary>
    public Dictionary<string, object?> FullState()
    {
        var s = Actions.State();
        s["meeting"] = null;
        s["agenda"] = new Dictionary<string, object?> { ["status"] = "none" };
        s["widgets"] = Widgets.State();
        s["integrations"] = new Dictionary<string, object?> { ["ha"] = "off", ["mqtt"] = "off" };
        s["context"] = new Dictionary<string, object?> { ["page"] = null };
        return s;
    }

    // ---------------------------------------------------------------- invoer van de tablet

    public (bool Ok, string? Error) HandleInput(string type, string id, string? gesture, double? value)
    {
        var tile = Lay.Tile(Layouts.Current, id);
        if (tile == null) return (false, L("Onbekende knop: {0}", id));
        try
        {
            if (type == "press")
            {
                if (Lay.Kind(tile) == "agenda") return (false, L("Agenda is nog niet beschikbaar op Windows"));
                if (!Lay.IsButton(tile)) return (false, L("Dit is geen knop"));
                Actions.Press(tile, gesture is "long" or "double" ? gesture : "tap");
            }
            else if (type == "slider")
            {
                if (Lay.Kind(tile) != "slider" || Lay.Obj(tile, "action") is not { } a || value is not { } v || !double.IsFinite(v))
                    return (false, L("Ongeldige schuifwaarde"));
                Actions.SetSlider(a, Math.Clamp(v, 0, 1));
            }
            else return (false, L("Onbekend bericht"));
            return (true, null);
        }
        catch (Exception e) { return (false, e.Message); }
    }

    public (bool Ok, string? Error) HandleWidget(string id, string action, double? value)
    {
        var tile = Lay.Tile(Layouts.Current, id);
        if (tile == null || !Lay.IsWidget(tile)) return (false, L("Onbekende widget: {0}", id));
        try { Widgets.Handle(tile, action, value); return (true, null); }
        catch (Exception e) { return (false, e.Message); }
    }

    public (bool Ok, string? Error) HandleDial(string id, int steps)
    {
        var tile = Lay.Tile(Layouts.Current, id);
        if (tile == null || Lay.Kind(tile) != "dial") return (false, L("Geen draaiknop: {0}", id));
        try { Actions.Dial(tile, steps); return (true, null); }
        catch (Exception e) { return (false, e.Message); }
    }

    public (bool Ok, string? Error) HandlePointer(string id, JsonObject msg)
    {
        var tile = Lay.Tile(Layouts.Current, id);
        if (tile == null || Lay.Kind(tile) != "touchpad") return (false, L("Geen aanraakpad: {0}", id));
        var cfg = Lay.Config(tile);
        try
        {
            switch (Lay.Str(msg, "op"))
            {
                case "move": Native.MouseMove(Lay.Num(msg, "dx") ?? 0, Lay.Num(msg, "dy") ?? 0, Lay.Num(cfg, "speed") ?? 1.5); break;
                case "scroll": Native.Scroll(Lay.Num(msg, "dx") ?? 0, Lay.Num(msg, "dy") ?? 0, Lay.Bool(cfg, "natural") ?? true); break;
                case "click": Native.Click(Lay.Str(msg, "button") == "right"); break;
                case "down": Native.Button(true); break;
                case "up": Native.Button(false); break;
                default: return (false, L("Onbekende muisactie"));
            }
            return (true, null);
        }
        catch (Exception e) { return (false, e.Message); }
    }

    // ---------------------------------------------------------------- editor

    public Dictionary<string, object?> EditorCatalog() => new()
    {
        ["platform"] = "windows",
        ["presets"] = Actions.Catalog.AppsList.SelectMany(a => a.Shortcuts.Select(s => new Dictionary<string, object?>
            { ["id"] = a.Id + "." + s.Id, ["app"] = a.Name, ["name"] = L(s.Label), ["keys"] = s.Keys })).ToList(),
        ["plugins"] = new List<object>(),
        ["apps"] = Apps.Catalog(),
        ["shortcuts"] = new List<string>(),
        ["timeZones"] = WorldClock.Catalog(),
        ["browsers"] = Apps.Browsers().Select(b => new Dictionary<string, object?> { ["id"] = b.Id, ["name"] = b.Name, ["default"] = b.IsDefault }).ToList(),
        ["devices"] = Pairing.Devices.Where(d => d.Viewport != null).Select(d => new Dictionary<string, object?>
            { ["id"] = d.Id, ["name"] = d.Name, ["w"] = d.Viewport!.W, ["h"] = d.Viewport.H, ["vw"] = d.Viewport.Vw, ["vh"] = d.Viewport.Vh }).ToList(),
    };
}
