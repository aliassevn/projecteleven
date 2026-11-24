using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Media;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using Windows.Media.Control;
using static Cyberpad.I18n;

namespace Cyberpad;

/// <summary>Verzamelt de gegevens van alle widget-tegels (state.widgets[tegel-id]). Zelfde velden als op de Mac (docs\PROTOCOL.md).</summary>
sealed class Widgets
{
    public readonly Weather Weather = new();
    public readonly Timers Timers = new();
    public readonly Stats Stats = new();
    public readonly NowPlaying NowPlaying = new();
    public readonly Photos Photos = new();
    public readonly Terminal Terminal = new();

    List<JsonObject> tiles = new();
    int tickCount;
    public event Action? Changed;
    public event Action<string>? Toast;

    public Widgets()
    {
        Weather.Updated += () => Changed?.Invoke();
        NowPlaying.Updated += () => Changed?.Invoke();
        Terminal.Updated += () => Changed?.Invoke();
        Timers.Finished += msg => Toast?.Invoke(msg);
    }

    public void Update(JsonObject layout)
    {
        tiles = Lay.Pages(layout).SelectMany(Lay.Tiles).Where(Lay.IsWidget).Select(t => (JsonObject)t.DeepClone()).ToList();
        Timers.Sync(tiles);
        foreach (var t in tiles.Where(t => Lay.Kind(t) == "weather")) Weather.Refresh(Lay.Config(t));
    }

    bool Has(string kind) => tiles.Any(t => Lay.Kind(t) == kind);

    /// <summary>Elke seconde. Zonder verbonden tablet wordt er niets opgevraagd.</summary>
    public void Tick(bool active)
    {
        tickCount++;
        Timers.Tick(tiles);
        if (!active) return;
        if (tickCount % 2 == 0)
        {
            if (Has("stats")) Stats.Sample();
            if (tiles.FirstOrDefault(t => Lay.Kind(t) == "nowplaying") is { } np) NowPlaying.Refresh(Lay.Str(Lay.Config(np), "player"));
        }
        if (tickCount % 60 == 0)
            foreach (var t in tiles.Where(t => Lay.Kind(t) == "weather")) Weather.Refresh(Lay.Config(t));
    }

    public Dictionary<string, object?> State()
    {
        var o = new Dictionary<string, object?>();
        foreach (var t in tiles)
        {
            var id = Lay.Str(t, "id") ?? "";
            var cfg = Lay.Config(t);
            switch (Lay.Kind(t))
            {
                case "weather": o[id] = Weather.Json(cfg); break;
                case "nowplaying": o[id] = NowPlaying.Current; break;
                case "stats":
                    var show = Lay.StrList(cfg, "show");
                    var cur = Stats.Current;
                    o[id] = show.Count > 0 ? cur.Where(kv => show.Contains(kv.Key)).ToDictionary(kv => kv.Key, kv => kv.Value) : cur;
                    break;
                case "timer": case "pomodoro": o[id] = Timers.Json(id); break;
                case "photos": o[id] = Photos.Json(cfg); break;
                case "terminal": o[id] = Terminal.Json(id, cfg); break;
                case "worldclock": o[id] = new Dictionary<string, object?> { ["zones"] = WorldClock.Zones(cfg) }; break;
                case "ha": case "mqtt": case "plugin":
                    o[id] = new Dictionary<string, object?> { ["status"] = "error", ["error"] = L("Nog niet beschikbaar op Windows: {0}", Lay.Kind(t)) };
                    break;
            }
        }
        return o;
    }

    /// <summary>Acties vanaf de tablet. Alleen vaste acties per soort tegel.</summary>
    public void Handle(JsonObject tile, string action, double? value)
    {
        switch (Lay.Kind(tile))
        {
            case "timer": case "pomodoro": Timers.Handle(tile, action); break;
            case "nowplaying": NowPlaying.Control(action, value); break;
            case "terminal": Terminal.Handle(tile, action, value == 1); break;
            case "weather":
                if (action != "refresh") throw new ActionException(L("Onbekende actie"));
                Weather.Refresh(Lay.Config(tile), force: true);
                break;
            default: throw new ActionException(L("Deze tegel heeft geen acties"));
        }
        Changed?.Invoke();
    }
}

// ---------------------------------------------------------------- Wereldklok

static class WorldClock
{
    static List<string>? known;

    /// <summary>IANA-tijdzones (shared\catalog\timezones.json) voor het keuzemenu in de editor.</summary>
    public static List<string> Known()
    {
        if (known != null) return known;
        try { known = Lay.StrList(JsonNode.Parse(File.ReadAllText(Path.Combine(Paths.Catalog, "timezones.json"))), "zones"); }
        catch { known = new(); }
        return known;
    }

    public static TimeZoneInfo? Find(string raw)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(raw); } catch { }
        // Plaatsnaam zoals "New York" → America/New_York.
        var want = raw.Trim().ToLowerInvariant();
        var id = Known().FirstOrDefault(z => z.Split('/').Last().Replace('_', ' ').ToLowerInvariant() == want);
        if (id != null) try { return TimeZoneInfo.FindSystemTimeZoneById(id); } catch { }
        return null;
    }

    public static string City(string id) => id.Split('/').Last().Replace('_', ' ');

    public static string Abbr(int offsetSeconds)
    {
        var h = Math.Abs(offsetSeconds) / 3600; var m = Math.Abs(offsetSeconds) % 3600 / 60;
        return "GMT" + (offsetSeconds < 0 ? "-" : "+") + h + (m > 0 ? ":" + m.ToString("00") : "");
    }

    public static List<Dictionary<string, object?>> Zones(JsonObject? cfg)
    {
        var ids = Lay.StrList(cfg, "zones");
        if (ids.Count == 0 && cfg?["zones"] == null) ids = new() { "America/New_York", "Asia/Tokyo" };
        var r = new List<Dictionary<string, object?>>();
        foreach (var raw in ids.Take(4))
        {
            var tz = Find(raw);
            if (tz == null) { r.Add(new() { ["label"] = raw, ["error"] = L("onbekende zone") }); continue; }
            var off = (int)tz.GetUtcOffset(DateTime.UtcNow).TotalSeconds;
            r.Add(new() { ["label"] = City(raw.Contains('/') ? raw : tz.Id), ["offset"] = off, ["abbr"] = Abbr(off) });
        }
        return r;
    }

    /// <summary>Voor de editor: [{id, region, name, offset}].</summary>
    public static List<Dictionary<string, object?>> Catalog()
    {
        var r = new List<Dictionary<string, object?>>();
        foreach (var id in Known())
        {
            TimeZoneInfo? tz;
            try { tz = TimeZoneInfo.FindSystemTimeZoneById(id); } catch { continue; }
            var parts = id.Split('/', 2);
            var region = parts.Length == 2 ? parts[0] : "Other";
            var name = parts.Length == 2 ? parts[1].Replace('_', ' ').Replace("/", " / ") : id;
            r.Add(new() { ["id"] = id, ["region"] = region, ["name"] = name, ["offset"] = (int)tz.GetUtcOffset(DateTime.UtcNow).TotalSeconds });
        }
        return r;
    }
}

// ---------------------------------------------------------------- Weer (Open-Meteo)

sealed class Weather
{
    sealed record Place(string Name, double Lat, double Lon);

    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(10) };
    readonly object gate = new();
    readonly Dictionary<string, Place> places = new();
    readonly Dictionary<string, Dictionary<string, object?>> data = new();
    readonly Dictionary<string, DateTime> fetchedAt = new();
    readonly HashSet<string> inFlight = new();
    public event Action? Updated;

    static Weather() => Http.DefaultRequestHeaders.UserAgent.ParseAdd("Cyberpad/0.1");

    static string Key(JsonObject? cfg) =>
        Lay.Num(cfg, "lat") is { } lat && Lay.Num(cfg, "lon") is { } lon
            ? $"{lat:0.000},{lon:0.000}" : (Lay.Str(cfg, "city") ?? "Amsterdam").ToLowerInvariant();

    public Dictionary<string, object?> Json(JsonObject? cfg)
    {
        lock (gate)
        {
            if (!data.TryGetValue(Key(cfg), out var d)) return new() { ["status"] = "loading" };
            var copy = new Dictionary<string, object?>(d);
            // Omschrijving steeds in de huidige taal.
            if (copy.TryGetValue("code", out var c) && c is int code) copy["desc"] = Describe(code, copy.TryGetValue("day", out var dy) && dy is bool b ? b : true).Text;
            copy.Remove("day");
            return copy;
        }
    }

    public void Refresh(JsonObject? cfg, bool force = false)
    {
        var k = Key(cfg);
        lock (gate)
        {
            if (inFlight.Contains(k)) return;
            if (!force && fetchedAt.TryGetValue(k, out var t) && (DateTime.UtcNow - t).TotalMinutes < 15) return;
            inFlight.Add(k);
        }
        var c = cfg?.DeepClone() as JsonObject;
        _ = Task.Run(async () =>
        {
            Dictionary<string, object?> result;
            bool ok = false;
            try
            {
                var (place, err) = await Resolve(c);
                if (place == null) result = new() { ["status"] = "error", ["error"] = err ?? L("Plaats niet gevonden") };
                else { result = await Forecast(place); ok = result["status"] as string == "ok"; }
            }
            catch { result = new() { ["status"] = "error", ["error"] = L("Geen internet") }; }
            lock (gate)
            {
                inFlight.Remove(k);
                data[k] = result;
                // Bij een fout over 5 minuten opnieuw proberen in plaats van na 15.
                fetchedAt[k] = ok ? DateTime.UtcNow : DateTime.UtcNow.AddMinutes(-10);
            }
            Updated?.Invoke();
        });
    }

    async Task<(Place?, string?)> Resolve(JsonObject? cfg)
    {
        if (Lay.Num(cfg, "lat") is { } lat && Lay.Num(cfg, "lon") is { } lon) return (new Place(Lay.Str(cfg, "city") ?? "", lat, lon), null);
        var city = Lay.Str(cfg, "city") ?? "Amsterdam";
        lock (gate) if (places.TryGetValue(city.ToLowerInvariant(), out var p0)) return (p0, null);
        var url = "https://geocoding-api.open-meteo.com/v1/search?count=1&language=nl&name=" + Uri.EscapeDataString(city);
        try
        {
            var obj = JsonNode.Parse(await Http.GetStringAsync(url));
            var first = (obj?["results"] as JsonArray)?.FirstOrDefault() as JsonObject;
            if (first == null || Lay.Num(first, "latitude") is not { } la || Lay.Num(first, "longitude") is not { } lo)
                return (null, L("Plaats “{0}” niet gevonden", city));
            var p = new Place(Lay.Str(first, "name") ?? city, la, lo);
            lock (gate) places[city.ToLowerInvariant()] = p;
            return (p, null);
        }
        catch { return (null, L("Geen internet")); }
    }

    static async Task<Dictionary<string, object?>> Forecast(Place p)
    {
        var inv = System.Globalization.CultureInfo.InvariantCulture;
        var url = "https://api.open-meteo.com/v1/forecast?latitude=" + p.Lat.ToString(inv) + "&longitude=" + p.Lon.ToString(inv) +
                  "&current=temperature_2m,weather_code,is_day,wind_speed_10m" +
                  "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=1";
        try
        {
            var obj = JsonNode.Parse(await Http.GetStringAsync(url)) as JsonObject;
            var cur = Lay.Obj(obj, "current");
            if (Lay.Num(cur, "temperature_2m") is not { } temp || Lay.Int(cur, "weather_code") is not { } code)
                return new() { ["status"] = "error", ["error"] = L("Onverwacht antwoord van Open-Meteo") };
            var daily = Lay.Obj(obj, "daily");
            double? first(string k) => daily?[k] is JsonArray a && a.FirstOrDefault() is JsonValue v && v.TryGetValue(out double d) ? d : null;
            var isDay = (Lay.Int(cur, "is_day") ?? 1) == 1;
            var desc = Describe(code, isDay);
            var o = new Dictionary<string, object?>
            {
                ["status"] = "ok", ["place"] = p.Name, ["temp"] = Math.Round(temp * 10) / 10, ["code"] = code, ["day"] = isDay,
                ["desc"] = desc.Text, ["icon"] = desc.Icon, ["updated"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
            };
            if (first("temperature_2m_max") is { } mx) o["max"] = Math.Round(mx);
            if (first("temperature_2m_min") is { } mn) o["min"] = Math.Round(mn);
            if (first("precipitation_probability_max") is { } rain) o["rain"] = (int)rain;
            if (Lay.Num(cur, "wind_speed_10m") is { } wind) o["wind"] = (int)Math.Round(wind);
            return o;
        }
        catch { return new() { ["status"] = "error", ["error"] = L("Geen internet") }; }
    }

    static (string Text, string Icon) Describe(int code, bool day) => code switch
    {
        0 => (L("Onbewolkt"), day ? "☀️" : "🌙"),
        1 => (L("Vrijwel onbewolkt"), day ? "🌤" : "🌙"),
        2 => (L("Half bewolkt"), day ? "⛅️" : "☁️"),
        3 => (L("Bewolkt"), "☁️"),
        45 or 48 => (L("Mist"), "🌫"),
        51 or 53 or 55 => (L("Motregen"), "🌦"),
        56 or 57 or 66 or 67 => (L("IJzel"), "🌧"),
        61 or 63 => (L("Regen"), "🌧"),
        65 => (L("Zware regen"), "🌧"),
        71 or 73 or 75 or 77 => (L("Sneeuw"), "🌨"),
        80 or 81 => (L("Buien"), "🌦"),
        82 => (L("Zware buien"), "⛈"),
        85 or 86 => (L("Sneeuwbuien"), "🌨"),
        95 or 96 or 99 => (L("Onweer"), "⛈"),
        _ => (L("Onbekend"), "🌡"),
    };
}

// ---------------------------------------------------------------- Timers en pomodoro

sealed class Timers
{
    sealed class State
    {
        public string Mode = "timer";
        public string Phase = "work";
        public double Duration;
        public double Remaining;
        public DateTime? EndsAt;
        public int Round = 1;
    }

    readonly object gate = new();
    Dictionary<string, State> timers = new();
    public event Action<string>? Finished;

    static double Duration(JsonObject t, string phase)
    {
        var cfg = Lay.Config(t);
        if (Lay.Kind(t) == "pomodoro")
        {
            var m = phase == "rest" ? (Lay.Int(cfg, "rest") ?? 5) : (Lay.Int(cfg, "work") ?? 25);
            return Math.Clamp(m, 1, 180) * 60;
        }
        return Math.Clamp(Lay.Int(cfg, "seconds") ?? 300, 5, 24 * 3600);
    }

    public void Sync(List<JsonObject> tiles)
    {
        lock (gate)
        {
            var keep = new Dictionary<string, State>();
            foreach (var t in tiles)
            {
                var kind = Lay.Kind(t);
                if (kind != "timer" && kind != "pomodoro") continue;
                var id = Lay.Str(t, "id") ?? "";
                timers.TryGetValue(id, out var s);
                var d = Duration(t, s?.Phase ?? "work");
                if (s != null)
                {
                    if (s.EndsAt == null && Math.Abs(s.Remaining - s.Duration) < 0.01 && Math.Abs(s.Duration - d) > 0.01) { s.Duration = d; s.Remaining = d; }
                }
                else s = new State { Mode = kind, Duration = d, Remaining = d };
                keep[id] = s;
            }
            timers = keep;
        }
    }

    public Dictionary<string, object?> Json(string id)
    {
        lock (gate)
        {
            if (!timers.TryGetValue(id, out var s)) return new();
            var d = new Dictionary<string, object?>
            {
                ["mode"] = s.Mode, ["phase"] = s.Phase, ["duration"] = (int)s.Duration, ["running"] = s.EndsAt != null, ["round"] = s.Round,
            };
            if (s.EndsAt is { } e) d["endsAt"] = new DateTimeOffset(e).ToUnixTimeMilliseconds();
            else d["remaining"] = (int)Math.Round(s.Remaining);
            return d;
        }
    }

    public void Handle(JsonObject tile, string action)
    {
        var id = Lay.Str(tile, "id") ?? "";
        lock (gate)
        {
            if (!timers.TryGetValue(id, out var s)) throw new ActionException(L("Timer niet gevonden"));
            switch (action)
            {
                case "toggle":
                    if (s.EndsAt is { } e) { s.Remaining = Math.Max(0, (e - DateTime.UtcNow).TotalSeconds); s.EndsAt = null; }
                    else { if (s.Remaining <= 0) s.Remaining = s.Duration; s.EndsAt = DateTime.UtcNow.AddSeconds(s.Remaining); }
                    break;
                case "reset":
                    var d = Duration(tile, "work");
                    timers[id] = new State { Mode = s.Mode, Duration = d, Remaining = d };
                    break;
                case "add":
                    if (s.EndsAt is { } e2) s.EndsAt = e2.AddSeconds(60); else s.Remaining += 60;
                    s.Duration += 60;
                    break;
                default: throw new ActionException(L("Onbekende timeractie"));
            }
        }
    }

    public void Tick(List<JsonObject> tiles)
    {
        var messages = new List<string>();
        lock (gate)
        {
            foreach (var (id, s) in timers)
            {
                if (s.EndsAt is not { } e || e > DateTime.UtcNow) continue;
                var tile = tiles.FirstOrDefault(t => Lay.Str(t, "id") == id);
                var label = tile != null ? Lay.Str(tile, "label") ?? "Timer" : "Timer";
                if (s.Mode == "pomodoro" && tile != null)
                {
                    var next = s.Phase == "work" ? "rest" : "work";
                    if (next == "work") s.Round++;
                    s.Phase = next;
                    s.Duration = Duration(tile, next);
                    s.Remaining = s.Duration;
                    s.EndsAt = DateTime.UtcNow.AddSeconds(s.Duration);
                    messages.Add(next == "rest" ? L("🍅 {0}: tijd voor pauze", label) : L("🍅 {0}: weer aan de slag (ronde {1})", label, s.Round));
                }
                else
                {
                    s.EndsAt = null;
                    s.Remaining = 0;
                    messages.Add(L("⏰ {0} is afgelopen", label));
                }
            }
        }
        if (messages.Count > 0) try { SystemSounds.Asterisk.Play(); } catch { }
        foreach (var m in messages) Finished?.Invoke(m);
    }
}

// ---------------------------------------------------------------- Systeem (CPU, RAM, netwerk, batterij)

sealed class Stats
{
    [StructLayout(LayoutKind.Sequential)]
    struct FILETIME { public uint Low; public uint High; public ulong Value => ((ulong)High << 32) | Low; }

    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out FILETIME idle, out FILETIME kernel, out FILETIME user);

    [StructLayout(LayoutKind.Sequential)]
    struct MEMORYSTATUSEX
    {
        public uint dwLength; public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys;
        public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);

    (ulong Idle, ulong Total)? lastCpu;
    (long Rx, long Tx, DateTime At)? lastNet;
    readonly object gate = new();
    Dictionary<string, object?> current = new();

    public Dictionary<string, object?> Current { get { lock (gate) return new(current); } }

    public void Sample()
    {
        var o = new Dictionary<string, object?>();
        try
        {
            if (GetSystemTimes(out var idle, out var kernel, out var user))
            {
                ulong i = idle.Value, total = kernel.Value + user.Value; // kernel bevat idle
                if (lastCpu is { } l && total > l.Total)
                {
                    var dt = total - l.Total; var di = i - l.Idle;
                    o["cpu"] = (int)Math.Round(100.0 * (dt - di) / dt);
                }
                lastCpu = (i, total);
            }
        }
        catch { }
        try
        {
            var m = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
            if (GlobalMemoryStatusEx(ref m))
            {
                var used = m.ullTotalPhys - m.ullAvailPhys;
                o["ram"] = new Dictionary<string, object?> { ["used"] = used, ["total"] = m.ullTotalPhys, ["percent"] = (int)Math.Round(100.0 * used / m.ullTotalPhys) };
            }
        }
        catch { }
        try
        {
            long rx = 0, tx = 0;
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var s = ni.GetIPStatistics();
                rx += s.BytesReceived; tx += s.BytesSent;
            }
            var now = DateTime.UtcNow;
            if (lastNet is { } l && now > l.At)
            {
                var dt = (now - l.At).TotalSeconds;
                o["net"] = new Dictionary<string, object?> { ["down"] = (int)Math.Max(0, (rx - l.Rx) / dt), ["up"] = (int)Math.Max(0, (tx - l.Tx) / dt) };
            }
            lastNet = (rx, tx, now);
        }
        catch { }
        try
        {
            var ps = SystemInformation.PowerStatus;
            if (!ps.BatteryChargeStatus.HasFlag(BatteryChargeStatus.NoSystemBattery) && ps.BatteryLifePercent <= 1)
                o["battery"] = new Dictionary<string, object?>
                {
                    ["percent"] = (int)Math.Round(ps.BatteryLifePercent * 100),
                    ["charging"] = ps.BatteryChargeStatus.HasFlag(BatteryChargeStatus.Charging),
                    ["plugged"] = ps.PowerLineStatus == PowerLineStatus.Online,
                };
        }
        catch { }
        lock (gate) current = o;
    }
}

// ---------------------------------------------------------------- Nu speelt (Windows-mediabediening)

sealed class NowPlaying
{
    readonly object gate = new();
    Dictionary<string, object?> current = new() { ["status"] = "idle" };
    GlobalSystemMediaTransportControlsSessionManager? manager;
    GlobalSystemMediaTransportControlsSession? session;
    bool busy;
    public event Action? Updated;

    public Dictionary<string, object?> Current { get { lock (gate) return new(current); } }

    static (string Id, string Name) AppOf(string aumid)
    {
        var a = aumid.ToLowerInvariant();
        if (a.Contains("spotify")) return ("spotify", "Spotify");
        if (a.Contains("zunemusic") || a.Contains("mediaplayer")) return ("music", "Media Player");
        if (a.Contains("chrome")) return ("chrome", "Chrome");
        if (a.Contains("msedge")) return ("edge", "Edge");
        if (a.Contains("firefox")) return ("firefox", "Firefox");
        if (a.Contains("vlc")) return ("vlc", "VLC");
        var name = aumid.Split('!', '\\').Last();
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
        return (name.ToLowerInvariant(), name);
    }

    public void Refresh(string? prefer)
    {
        lock (gate) { if (busy) return; busy = true; }
        _ = Task.Run(async () =>
        {
            Dictionary<string, object?> next = new() { ["status"] = "idle" };
            try
            {
                manager ??= await GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
                var sessions = manager.GetSessions().ToList();
                GlobalSystemMediaTransportControlsSession? pick = null;
                if (!string.IsNullOrEmpty(prefer))
                    pick = sessions.FirstOrDefault(s => AppOf(s.SourceAppUserModelId).Id == prefer);
                pick ??= sessions.FirstOrDefault(s => s.GetPlaybackInfo().PlaybackStatus == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing)
                         ?? manager.GetCurrentSession() ?? sessions.FirstOrDefault();
                session = pick;
                if (pick != null)
                {
                    var props = await pick.TryGetMediaPropertiesAsync();
                    var tl = pick.GetTimelineProperties();
                    var status = pick.GetPlaybackInfo().PlaybackStatus;
                    var (id, name) = AppOf(pick.SourceAppUserModelId);
                    var duration = (tl.EndTime - tl.StartTime).TotalSeconds;
                    var position = (tl.Position - tl.StartTime).TotalSeconds;
                    // De positie is van het moment van de laatste update; tijdens afspelen doorrekenen.
                    if (status == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing && tl.LastUpdatedTime.Year > 2000)
                        position += (DateTimeOffset.Now - tl.LastUpdatedTime).TotalSeconds;
                    if (duration > 0) position = Math.Clamp(position, 0, duration);
                    next = new()
                    {
                        ["status"] = "ok", ["app"] = id, ["appName"] = name,
                        ["state"] = status == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing ? "playing"
                                  : status == GlobalSystemMediaTransportControlsSessionPlaybackStatus.Paused ? "paused" : "stopped",
                        ["title"] = props?.Title ?? "", ["artist"] = props?.Artist ?? "", ["album"] = props?.AlbumTitle ?? "",
                        ["position"] = Math.Round(Math.Max(0, position), 1), ["duration"] = Math.Round(Math.Max(0, duration), 1),
                        ["at"] = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                    };
                    if (string.IsNullOrEmpty(props?.Title)) next = new() { ["status"] = "idle" };
                }
            }
            catch { next = new() { ["status"] = "idle" }; }
            bool changed;
            lock (gate)
            {
                changed = Strip(current) != Strip(next);
                current = next;
                busy = false;
            }
            if (changed) Updated?.Invoke();
        });
    }

    static string Strip(Dictionary<string, object?> d) =>
        string.Join("|", d.Where(kv => kv.Key != "at" && kv.Key != "position").Select(kv => kv.Key + "=" + kv.Value));

    public void Control(string action, double? value)
    {
        var s = session ?? throw new ActionException(L("Er speelt niets"));
        _ = action switch
        {
            "playpause" => s.TryTogglePlayPauseAsync().AsTask(),
            "next" => s.TrySkipNextAsync().AsTask(),
            "prev" => s.TrySkipPreviousAsync().AsTask(),
            "seek" when value is { } v && double.IsFinite(v) && v >= 0 =>
                s.TryChangePlaybackPositionAsync(TimeSpan.FromSeconds(v).Ticks + s.GetTimelineProperties().StartTime.Ticks).AsTask(),
            "seek" => throw new ActionException(L("Ongeldige positie")),
            _ => throw new ActionException(L("Onbekende bediening")),
        };
        Task.Delay(300).ContinueWith(_ => Refresh(null));
    }
}

// ---------------------------------------------------------------- Foto's

sealed class Photos
{
    static readonly string[] Exts = { ".jpg", ".jpeg", ".png", ".bmp", ".gif" };

    static string Folder(JsonObject? cfg)
    {
        var f = Lay.Str(cfg, "folder");
        var pictures = Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
        if (string.IsNullOrWhiteSpace(f)) return Path.Combine(pictures, "Cyberpad");
        // Een Mac-pad als ~/Pictures/Cyberpad werkt ook.
        if (f.StartsWith("~/Pictures", StringComparison.OrdinalIgnoreCase)) return Path.Combine(pictures, f[10..].TrimStart('/', '\\').Replace('/', '\\'));
        if (f.StartsWith("~")) return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), f[1..].TrimStart('/', '\\').Replace('/', '\\'));
        return Environment.ExpandEnvironmentVariables(f);
    }

    static (List<string> Files, string? Error) List(JsonObject? cfg)
    {
        var dir = Folder(cfg);
        if (!Directory.Exists(dir)) return (new(), L("Map {0} bestaat niet", dir));
        var files = Directory.EnumerateFiles(dir).Where(f => Exts.Contains(Path.GetExtension(f).ToLowerInvariant())).OrderBy(f => f).Take(500).ToList();
        return (files, files.Count == 0 ? L("Zet foto's in {0}", dir) : null);
    }

    public Dictionary<string, object?> Json(JsonObject? cfg)
    {
        var (files, err) = List(cfg);
        var d = new Dictionary<string, object?> { ["count"] = files.Count, ["interval"] = Math.Clamp(Lay.Int(cfg, "seconds") ?? 10, 3, 3600) };
        if (err != null) d["error"] = err;
        return d;
    }

    /// <summary>JPEG (max. 1280 px) van foto nummer index (rondgaand). Alleen bestanden uit de lijst.</summary>
    public byte[]? Image(JsonObject? cfg, int index)
    {
        var (files, _) = List(cfg);
        if (files.Count == 0) return null;
        var file = files[((index % files.Count) + files.Count) % files.Count];
        try
        {
            using var img = System.Drawing.Image.FromFile(file);
            var scale = Math.Min(1.0, 1280.0 / Math.Max(img.Width, img.Height));
            int w = Math.Max(1, (int)(img.Width * scale)), h = Math.Max(1, (int)(img.Height * scale));
            using var bmp = new Bitmap(w, h);
            using (var g = Graphics.FromImage(bmp))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(img, 0, 0, w, h);
            }
            using var ms = new MemoryStream();
            var enc = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
            var ps = new EncoderParameters(1) { Param = { [0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 82L) } };
            bmp.Save(ms, enc, ps);
            return ms.ToArray();
        }
        catch { return null; }
    }
}

// ---------------------------------------------------------------- Terminal

sealed class Terminal
{
    sealed class Run
    {
        public string Status = "idle";
        public int? Exit;
        public readonly StringBuilder Output = new();
        public DateTime? Started, Ended;
        public Process? Process;
        public string? StopReason;
    }

    const int MaxOutput = 6000;
    readonly object gate = new();
    readonly Dictionary<string, Run> runs = new();
    public event Action? Updated;

    public Dictionary<string, object?> Json(string id, JsonObject? cfg)
    {
        lock (gate)
        {
            runs.TryGetValue(id, out var r);
            r ??= new Run();
            var out_ = r.Output.ToString();
            var d = new Dictionary<string, object?> { ["status"] = r.Status, ["output"] = out_, ["dangerous"] = Lay.Bool(cfg, "dangerous") == true };
            if (r.Exit is { } e) d["exit"] = e;
            if (r.Started is { } s) d["started"] = new DateTimeOffset(s).ToUnixTimeMilliseconds();
            if (r.Ended is { } en) d["ended"] = new DateTimeOffset(en).ToUnixTimeMilliseconds();
            if (Lay.Str(cfg, "command") == null) d["error"] = L("Geen commando ingesteld");
            return d;
        }
    }

    public void Handle(JsonObject tile, string action, bool confirmed)
    {
        var id = Lay.Str(tile, "id") ?? "";
        var cfg = Lay.Config(tile);
        switch (action)
        {
            case "run":
                var cmd = Lay.Str(cfg, "command");
                if (string.IsNullOrEmpty(cmd)) throw new ActionException(L("Ontbreekt in layout: {0}", "config.command"));
                if (Lay.Bool(cfg, "dangerous") == true && !confirmed) throw new ActionException(L("Bevestig eerst op de tablet"));
                lock (gate) if (runs.TryGetValue(id, out var r) && r.Status == "running") throw new ActionException(L("Draait al"));
                Start(id, cmd, cfg);
                break;
            case "stop": Stop(id, "stopped"); break;
            case "clear": lock (gate) if (!runs.TryGetValue(id, out var r2) || r2.Status != "running") runs[id] = new Run(); break;
            default: throw new ActionException(L("Onbekende terminalactie"));
        }
        Updated?.Invoke();
    }

    void Start(string id, string cmd, JsonObject? cfg)
    {
        var run = new Run { Status = "running", Started = DateTime.UtcNow };
        var psi = new ProcessStartInfo("cmd.exe")
        {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
        };
        // chcp 65001: uitvoer als UTF-8, zodat accenten goed overkomen.
        psi.ArgumentList.Add("/d"); psi.ArgumentList.Add("/s"); psi.ArgumentList.Add("/c");
        psi.ArgumentList.Add("chcp 65001 >nul & " + cmd);
        var cwd = Lay.Str(cfg, "cwd");
        if (!string.IsNullOrEmpty(cwd))
        {
            var dir = cwd.StartsWith("~") ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), cwd[1..].TrimStart('/', '\\')) : cwd;
            if (Directory.Exists(dir)) psi.WorkingDirectory = dir;
        }
        var p = new Process { StartInfo = psi, EnableRaisingEvents = true };
        void append(string? line)
        {
            if (line == null) return;
            lock (gate)
            {
                run.Output.Append(line).Append('\n');
                if (run.Output.Length > MaxOutput) run.Output.Remove(0, run.Output.Length - MaxOutput);
            }
            Updated?.Invoke();
        }
        p.OutputDataReceived += (_, e) => append(e.Data);
        p.ErrorDataReceived += (_, e) => append(e.Data);
        p.Exited += (_, _) =>
        {
            lock (gate)
            {
                run.Exit = p.ExitCode;
                run.Ended = DateTime.UtcNow;
                run.Status = run.StopReason ?? (p.ExitCode == 0 ? "done" : "failed");
                run.Process = null;
            }
            Updated?.Invoke();
        };
        try
        {
            p.Start();
            p.StandardInput.Close();
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();
        }
        catch (Exception e)
        {
            run.Status = "failed";
            run.Output.Append(L("Kon niet starten: {0}", e.Message));
            run.Ended = DateTime.UtcNow;
        }
        run.Process = run.Status == "running" ? p : null;
        lock (gate) runs[id] = run;
        var timeout = Math.Clamp(Lay.Int(cfg, "timeout") ?? 60, 1, 600);
        Task.Delay(TimeSpan.FromSeconds(timeout)).ContinueWith(_ => Stop(id, "timeout", run));
    }

    void Stop(string id, string reason, Run? only = null)
    {
        Process? p;
        lock (gate)
        {
            if (!runs.TryGetValue(id, out var r) || r.Status != "running" || (only != null && r != only)) return;
            r.StopReason = reason;
            p = r.Process;
        }
        try { p?.Kill(entireProcessTree: true); } catch { }
    }
}
