using System.Text.Json.Nodes;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Standaard-layout voor Windows (nieuwe installatie of "Standaard-layout terugzetten"), in de huidige taal.</summary>
static class DefaultLayout
{
    static JsonObject A(string type, params (string Key, object Value)[] extra)
    {
        var o = new JsonObject { ["type"] = type };
        foreach (var (k, v) in extra) o[k] = Json.ToNode(v);
        return o;
    }

    static JsonObject T(string id, string label, int x, int y, string? icon = null, JsonObject? action = null, string? kind = null,
        int w = 1, int h = 1, JsonObject? config = null, JsonObject? longPress = null, JsonObject? doubleTap = null,
        JsonObject? offAction = null, bool toggle = false)
    {
        var t = new JsonObject { ["id"] = id, ["label"] = label };
        if (icon != null) t["icon"] = icon;
        if (kind != null) t["kind"] = kind;
        if (action != null) t["action"] = action;
        if (longPress != null) t["longPress"] = longPress;
        if (doubleTap != null) t["doubleTap"] = doubleTap;
        if (toggle) t["toggle"] = true;
        if (offAction != null) t["offAction"] = offAction;
        if (config != null) t["config"] = config;
        t["x"] = x; t["y"] = y;
        if (w != 1) t["w"] = w;
        if (h != 1) t["h"] = h;
        return t;
    }

    static JsonObject Cfg(params (string Key, object Value)[] kv)
    {
        var o = new JsonObject();
        foreach (var (k, v) in kv) o[k] = Json.ToNode(v);
        return o;
    }

    static JsonObject Page(string id, string name, JsonObject[] tiles, int? columns = null, int? rows = null)
    {
        var p = new JsonObject { ["id"] = id, ["name"] = name, ["tiles"] = new JsonArray(tiles) };
        if (columns != null) p["columns"] = columns;
        if (rows != null) p["rows"] = rows;
        return p;
    }

    public static JsonObject Build()
    {
        var zones = new[] { "America/New_York", "Asia/Tokyo" };
        var pages = new JsonArray(
            // Dashboard in een compact raster (10×6): tegels half zo groot.
            Page("main", "Main", new[]
            {
                T("m-nowplaying", L("Nu speelt"), 0, 0, kind: "nowplaying", w: 4, h: 2),
                T("m-weather", L("Weer"), 4, 0, kind: "weather", w: 3, h: 2, config: Cfg(("city", "Amsterdam"))),
                T("m-world", L("Wereldklok"), 7, 0, kind: "worldclock", w: 3, h: 2, config: Cfg(("zones", zones))),
                T("m-clock", L("Tijd"), 0, 2, kind: "clock", w: 4, h: 3),
                T("m-stats", L("Systeem"), 4, 2, kind: "stats", w: 3, h: 2),
                T("m-timer", "Timer", 7, 2, kind: "timer", w: 3, h: 2, config: Cfg(("seconds", 300))),
                T("m-pomodoro", "Pomodoro", 4, 4, kind: "pomodoro", w: 3, h: 2, config: Cfg(("work", 25), ("rest", 5))),
                T("m-play", "Play", 7, 4, icon: "⏯", action: A("media.playPause")),
                T("m-mute", L("Geluid uit"), 8, 4, icon: "🔇", action: A("audio.mute")),
                T("m-mic", L("Mic uit"), 9, 4, icon: "🎙", action: A("audio.micMute")),
                T("m-prev", L("Vorige"), 7, 5, icon: "⏮", action: A("media.previous")),
                T("m-next", L("Volgende"), 8, 5, icon: "⏭", action: A("media.next")),
                T("m-awake", L("Wakker"), 9, 5, icon: "☕️", action: A("system.keepAwake")),
                T("m-volume", "Volume", 0, 5, kind: "slider", w: 4, action: A("audio.volume")),
            }, 10, 6),
            Page("buttons", L("Knoppen"), new[]
            {
                T("prev", L("Vorige"), 0, 0, icon: "⏮", action: A("media.previous")),
                T("play", L("Play / pauze"), 1, 0, icon: "⏯", action: A("media.playPause")),
                T("next", L("Volgende"), 2, 0, icon: "⏭", action: A("media.next")),
                T("mute", L("Geluid uit"), 3, 0, icon: "🔇", action: A("audio.mute")),
                T("mic", L("Mic uit"), 4, 0, icon: "🎙", action: A("audio.micMute")),
                T("voldown", "Vol −", 0, 1, icon: "🔉", action: A("audio.volumeDown")),
                T("volup", "Vol +", 1, 1, icon: "🔊", action: A("audio.volumeUp")),
                T("browser", "Browser", 2, 1, icon: "🌐", action: A("url.open", ("url", "https://www.google.com"))),
                T("dark", "Dark mode", 3, 1, icon: "🌗", action: A("system.darkMode")),
                T("awake", L("Wakker"), 4, 1, icon: "☕️", action: A("system.keepAwake")),
                T("lock2", L("Vergrendel"), 0, 2, icon: "🔒", action: A("system.lock")),
                T("shot2", "Screenshot", 1, 2, icon: "📸", action: A("system.screenshot")),
                T("search", L("Zoeken"), 2, 2, icon: "🔎", action: A("keys.press", ("keys", "win+s"))),
                T("taskview", L("Taakweergave"), 3, 2, icon: "🪟", action: A("keys.press", ("keys", "win+tab"))),
                T("explorer", L("Verkenner"), 4, 2, icon: "🗂", action: A("keys.press", ("keys", "win+e"))),
            }),
            Page("work", L("Werk"), new[]
            {
                T("zoom-mic", "Zoom mic", 0, 0, icon: "🎤", action: A("preset", ("preset", "zoom.mute"))),
                T("zoom-cam", L("Zoom camera"), 1, 0, icon: "📹", action: A("preset", ("preset", "zoom.video"))),
                T("teams-mic", "Teams mic", 2, 0, icon: "🎤", action: A("preset", ("preset", "teams.mute"))),
                T("meet-mic", "Meet mic", 3, 0, icon: "🎤", action: A("preset", ("preset", "meet.mute"))),
                T("slack-mic", "Slack huddle", 4, 0, icon: "🎧", action: A("preset", ("preset", "slack.huddleMute"))),
                T("copy", L("Kopieer · lang: knip"), 0, 1, icon: "📋", action: A("keys.press", ("keys", "ctrl+c")),
                    longPress: A("keys.press", ("keys", "ctrl+x"))),
                T("paste", L("Plak · 2×: zonder opmaak"), 1, 1, icon: "📥", action: A("keys.press", ("keys", "ctrl+v")),
                    doubleTap: A("keys.press", ("keys", "ctrl+shift+v"))),
                T("greeting", L("Groet typen"), 2, 1, icon: "✍️", action: A("text.type", ("text", L("Met vriendelijke groet,")))),
                T("note", L("Nieuwe notitie"), 3, 1, icon: "🗒", action: A("macro", ("steps", new object[]
                {
                    new Dictionary<string, object> { ["type"] = "app.open", ["app"] = "notepad" },
                    new Dictionary<string, object> { ["type"] = "delay", ["ms"] = 800 },
                    new Dictionary<string, object> { ["type"] = "text.type", ["text"] = L("Notitie van Cyberpad") },
                }))),
                T("clipboard", L("Klembord"), 4, 1, icon: "📎", action: A("keys.press", ("keys", "win+v"))),
                T("desktop", L("Bureaublad"), 0, 2, icon: "🖥", action: A("keys.press", ("keys", "win+d"))),
                T("emoji", "Emoji", 1, 2, icon: "😀", action: A("keys.press", ("keys", "win+."))),
                T("snapleft", L("Venster links"), 2, 2, icon: "◧", action: A("keys.press", ("keys", "win+left"))),
                T("snapright", L("Venster rechts"), 3, 2, icon: "◨", action: A("keys.press", ("keys", "win+right"))),
                T("taskmgr", L("Taakbeheer"), 4, 2, icon: "📊", action: A("keys.press", ("keys", "ctrl+shift+escape"))),
            }),
            Page("widgets", "Widgets", new[]
            {
                T("nowplaying", L("Nu speelt"), 0, 0, kind: "nowplaying", w: 3),
                T("weather", L("Weer"), 3, 0, kind: "weather", w: 2, config: Cfg(("city", "Amsterdam"))),
                T("stats", L("Systeem"), 0, 1, kind: "stats", w: 2),
                T("timer", "Timer", 2, 1, kind: "timer", config: Cfg(("seconds", 300))),
                T("pomodoro", "Pomodoro", 3, 1, kind: "pomodoro", config: Cfg(("work", 25), ("rest", 5))),
                T("world", L("Wereldklok"), 4, 1, kind: "worldclock", config: Cfg(("zones", zones))),
                T("ping", "Ping", 0, 2, kind: "terminal", w: 3, config: Cfg(("command", "ping -n 5 1.1.1.1"), ("timeout", 30))),
                T("photos", L("Foto's"), 3, 2, kind: "photos", w: 2, config: Cfg(("seconds", 10))),
            }),
            // Tablet als touchpad en draaiknoppen.
            Page("touch", L("Bediening"), new[]
            {
                T("touchpad", L("Aanraakpad"), 0, 0, kind: "touchpad", w: 3, h: 3, config: Cfg(("speed", 1.5), ("natural", true))),
                T("dial-volume", "Volume", 3, 0, kind: "dial", action: A("audio.volume"), config: Cfg(("step", 0.03))),
                T("dial-scroll", L("Scrollen"), 4, 0, kind: "dial", action: A("pointer.scroll")),
                T("dial-spaces", L("Bureaubladen"), 3, 1, kind: "dial", action: A("keys.press", ("keys", "ctrl+win+right")),
                    offAction: A("keys.press", ("keys", "ctrl+win+left"))),
                T("dial-zoom", L("Zoomen"), 4, 1, kind: "dial", action: A("keys.press", ("keys", "ctrl+=")),
                    offAction: A("keys.press", ("keys", "ctrl+-"))),
                T("dial-tabs", L("Tabbladen"), 3, 2, kind: "dial", action: A("keys.press", ("keys", "ctrl+tab")),
                    offAction: A("keys.press", ("keys", "ctrl+shift+tab"))),
                T("taskview2", L("Taakweergave"), 4, 2, icon: "🪟", action: A("keys.press", ("keys", "win+tab"))),
            }),
            Page("system", L("Systeem"), new[]
            {
                T("lock", L("Vergrendel"), 0, 0, icon: "🔒", action: A("system.lock")),
                T("display", L("Scherm uit"), 1, 0, icon: "🌑", action: A("system.displayOff")),
                T("shot", "Screenshot", 2, 0, icon: "📸", action: A("system.screenshot")),
                T("shotarea", L("Selectie"), 3, 0, icon: "✂️", action: A("system.screenshotArea")),
                T("settings", L("Instellingen"), 4, 0, icon: "⚙️", action: A("keys.press", ("keys", "win+i"))),
                T("github", "GitHub", 0, 1, icon: "🌐", action: A("url.open", ("url", "https://github.com"))),
                T("mic-level", L("Mic-volume"), 0, 2, kind: "slider", action: A("audio.micVolume")),
                T("clock2", L("Tijd"), 1, 1, kind: "clock", w: 4, h: 2),
            })
        );
        return new JsonObject
        {
            ["version"] = 1,
            ["columns"] = 5,
            ["rows"] = 3,
            ["theme"] = "cyberdeck",
            ["pages"] = pages,
        };
    }
}
