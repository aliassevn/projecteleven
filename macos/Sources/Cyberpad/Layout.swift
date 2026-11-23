import Foundation

/// Vrije JSON-waarde, voor `data` van een Home Assistant-dienst.
enum JSONValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    /// Als gewone Foundation-waarde, voor JSONSerialization.
    var any: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v && abs(v) < 1e15 ? Int(v) as Any : v
        case .bool(let v): return v
        case .object(let v): return v.mapValues(\.any)
        case .array(let v): return v.map(\.any)
        case .null: return NSNull()
        }
    }
}

/// Wat een knop doet. De tablet stuurt alleen het id van een tegel; de actie zelf staat hier, op de Mac.
struct ActionSpec: Codable, Equatable {
    var type: String
    var app: String?        // app.open
    var url: String?        // url.open
    var keys: String?       // keys.press, bijv. "cmd+shift+a"
    var text: String?       // text.type
    var shortcut: String?   // shortcut.run (naam in de Opdrachten-app)
    var preset: String?     // preset: id uit de shortcut-bibliotheek, bijv. "zoom.mute"
    var steps: [ActionSpec]? // macro
    var ms: Int?            // delay (alleen binnen een macro)
    // Home Assistant: ha.toggle, ha.service, ha.level (schuif)
    var entity: String?     // bijv. "light.woonkamer"
    var service: String?    // ha.service, bijv. "light.turn_on"
    var data: [String: JSONValue]? // extra gegevens voor de dienst
    // Webhook: webhook.call (`url` of de naam van een webhook uit integrations.json)
    var webhook: String?
    var method: String?
    var headers: [String: String]?
    var body: String?
    // MQTT: mqtt.publish
    var topic: String?
    var payload: String?
    var retain: Bool?
    // Plugin: {"type": "plugin", "plugin": "hallo", "action": "greet", "params": {...}}
    var plugin: String?
    var action: String?
    var params: [String: JSONValue]?

    init(type: String, app: String? = nil, url: String? = nil, keys: String? = nil, text: String? = nil,
         shortcut: String? = nil, preset: String? = nil, steps: [ActionSpec]? = nil, ms: Int? = nil,
         entity: String? = nil, service: String? = nil, data: [String: JSONValue]? = nil,
         webhook: String? = nil, method: String? = nil, headers: [String: String]? = nil, body: String? = nil,
         topic: String? = nil, payload: String? = nil, retain: Bool? = nil,
         plugin: String? = nil, action: String? = nil, params: [String: JSONValue]? = nil) {
        self.type = type; self.app = app; self.url = url; self.keys = keys; self.text = text
        self.shortcut = shortcut; self.preset = preset; self.steps = steps; self.ms = ms
        self.entity = entity; self.service = service; self.data = data
        self.webhook = webhook; self.method = method; self.headers = headers; self.body = body
        self.topic = topic; self.payload = payload; self.retain = retain
        self.plugin = plugin; self.action = action; self.params = params
    }
}

/// Instellingen voor widget-tegels. Alleen de velden die bij het soort tegel horen worden gebruikt.
struct WidgetConfig: Codable, Equatable {
    // weather
    var city: String?
    var lat: Double?
    var lon: Double?
    // timer: duur in seconden · photos: seconden per foto
    var seconds: Int?
    // pomodoro: minuten werk / pauze
    var work: Int?
    var rest: Int?
    // worldclock: tijdzones, bijv. "America/New_York"
    var zones: [String]?
    // photos: map met foto's (standaard ~/Pictures/Cyberpad)
    var folder: String?
    // terminal
    var command: String?
    var cwd: String?
    var dangerous: Bool?
    var timeout: Int?
    // stats: welke regels (cpu, ram, net, battery, accessories)
    var show: [String]?
    // nowplaying: "music" of "spotify" (standaard: wat er speelt)
    var player: String?
    // ha: entiteit om te tonen (sensor, lamp, thermostaat…)
    var entity: String?
    // mqtt-widget: topic om te tonen · knop: topic met de actuele stand (aan/uit)
    var topic: String?
    var unit: String?
    /// mqtt: veld uit een JSON-bericht, bijv. "temperature" of "sensor.temp"
    var field: String?
    // plugin-widget: welke plugin en welke widget daarvan, met instellingen
    var plugin: String?
    var widget: String?
    var params: [String: JSONValue]?
    // touchpad: snelheid (standaard 1,5) en natuurlijk scrollen (standaard aan)
    var speed: Double?
    var natural: Bool?
    // dial: stap per tik van de draaiknop (0…1 voor volume/helderheid, standaard 0,03)
    var step: Double?

    init(city: String? = nil, lat: Double? = nil, lon: Double? = nil, seconds: Int? = nil, work: Int? = nil,
         rest: Int? = nil, zones: [String]? = nil, folder: String? = nil, command: String? = nil, cwd: String? = nil,
         dangerous: Bool? = nil, timeout: Int? = nil, show: [String]? = nil, player: String? = nil,
         entity: String? = nil, topic: String? = nil, unit: String? = nil, field: String? = nil,
         plugin: String? = nil, widget: String? = nil, params: [String: JSONValue]? = nil,
         speed: Double? = nil, natural: Bool? = nil, step: Double? = nil) {
        self.city = city; self.lat = lat; self.lon = lon; self.seconds = seconds; self.work = work; self.rest = rest
        self.zones = zones; self.folder = folder; self.command = command; self.cwd = cwd; self.dangerous = dangerous
        self.timeout = timeout; self.show = show; self.player = player
        self.entity = entity; self.topic = topic; self.unit = unit; self.field = field
        self.plugin = plugin; self.widget = widget; self.params = params
        self.speed = speed; self.natural = natural; self.step = step
    }
}

struct Tile: Codable, Equatable {
    var id: String
    var label: String
    var icon: String?
    /// "button" (standaard), "slider" of "clock"
    var kind: String?
    /// Tik
    var action: ActionSpec?
    /// Lang indrukken (± 0,5 s)
    var longPress: ActionSpec?
    /// Dubbeltikken
    var doubleTap: ActionSpec?
    /// Aan/uit-knop: Cyberpad onthoudt de stand. Bij "uit" wordt `offAction` gebruikt (als die er is).
    var toggle: Bool?
    var offAction: ActionSpec?
    /// Instellingen voor widgets (weer, timer, terminal, …)
    var config: WidgetConfig?
    var x: Int
    var y: Int
    var w: Int?
    var h: Int?

    init(id: String, label: String, icon: String? = nil, kind: String? = nil, action: ActionSpec? = nil,
         longPress: ActionSpec? = nil, doubleTap: ActionSpec? = nil, toggle: Bool? = nil, offAction: ActionSpec? = nil,
         config: WidgetConfig? = nil, x: Int, y: Int, w: Int? = nil, h: Int? = nil) {
        self.id = id; self.label = label; self.icon = icon; self.kind = kind; self.action = action
        self.longPress = longPress; self.doubleTap = doubleTap; self.toggle = toggle; self.offAction = offAction
        self.config = config
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    var isButton: Bool { kind == nil || kind == "button" }

    static let widgetKinds: Set<String> = ["weather", "nowplaying", "timer", "pomodoro", "worldclock", "photos", "stats", "terminal", "ha", "mqtt", "plugin"]
    var isWidget: Bool { Self.widgetKinds.contains(kind ?? "") }
}

struct Page: Codable, Equatable {
    var id: String
    var name: String
    var tiles: [Tile]
    /// Contextpagina: als een van deze apps vooraan komt, springt de tablet naar deze pagina.
    /// Bundle-id (com.adobe.Photoshop) of app-naam (Photoshop).
    var apps: [String]?

    init(id: String, name: String, tiles: [Tile], apps: [String]? = nil) {
        self.id = id; self.name = name; self.tiles = tiles; self.apps = apps
    }
}

/// Tijdvenster voor een profiel. Dagen: 1 = maandag … 7 = zondag. `from` later dan `to` = over middernacht.
struct TimeRule: Codable, Equatable {
    var days: [Int]?
    var from: String?   // "08:00"
    var to: String?     // "18:00"

    static func minutes(_ s: String?) -> Int? {
        guard let s else { return nil }
        let p = s.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        let wd = calendar.component(.weekday, from: date)      // 1 = zondag
        let day = wd == 1 ? 7 : wd - 1                          // 1 = maandag
        let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let f = Self.minutes(from) ?? 0, t = Self.minutes(to) ?? 24 * 60
        if f <= t {
            guard days?.contains(day) ?? true else { return false }
            return now >= f && now < t
        }
        // Over middernacht: het deel na middernacht hoort bij de dag ervoor.
        if now >= f { return days?.contains(day) ?? true }
        if now < t { return days?.contains(day == 1 ? 7 : day - 1) ?? true }
        return false
    }
}

/// Profiel: welke pagina's een tablet ziet. Automatisch op tijd, of gekozen via menu, Focus (Opdrachten) of per tablet.
struct Profile: Codable, Equatable {
    var id: String
    var name: String
    var pages: [String]
    var when: [TimeRule]?
    /// Profiel als er geen tijdregel past.
    var `default`: Bool?
}

struct Layout: Codable, Equatable {
    var version: Int
    var columns: Int
    var rows: Int
    var theme: String
    var pages: [Page]
    var profiles: [Profile]? = nil

    func tile(id: String) -> Tile? {
        for p in pages { if let t = p.tiles.first(where: { $0.id == id }) { return t } }
        return nil
    }

    static let `default` = Layout(
        version: 1, columns: 5, rows: 3, theme: "cyberdeck",
        pages: [
            Page(id: "main", name: "Main", tiles: [
                Tile(id: "prev", label: "Vorige", icon: "⏮", action: .init(type: "media.previous"), x: 0, y: 0),
                Tile(id: "play", label: "Play / pauze", icon: "⏯", action: .init(type: "media.playPause"), x: 1, y: 0),
                Tile(id: "next", label: "Volgende", icon: "⏭", action: .init(type: "media.next"), x: 2, y: 0),
                Tile(id: "mute", label: "Geluid uit", icon: "🔇", action: .init(type: "audio.mute"), x: 3, y: 0),
                Tile(id: "mic", label: "Mic uit", icon: "🎙", action: .init(type: "audio.micMute"), x: 4, y: 0),
                Tile(id: "volume", label: "Volume", kind: "slider", action: .init(type: "audio.volume"), x: 0, y: 1, w: 3),
                Tile(id: "voldown", label: "Vol −", icon: "🔉", action: .init(type: "audio.volumeDown"), x: 3, y: 1),
                Tile(id: "volup", label: "Vol +", icon: "🔊", action: .init(type: "audio.volumeUp"), x: 4, y: 1),
                Tile(id: "safari", label: "Safari", icon: "🧭", action: .init(type: "app.open", app: "com.apple.Safari"), x: 0, y: 2),
                Tile(id: "agenda", label: "Volgende afspraak", kind: "agenda", x: 1, y: 2, w: 2),
                Tile(id: "dark", label: "Dark mode", icon: "🌗", action: .init(type: "system.darkMode"), x: 3, y: 2),
                Tile(id: "awake", label: "Wakker", icon: "☕️", action: .init(type: "system.keepAwake"), x: 4, y: 2),
            ]),
            Page(id: "work", name: "Werk", tiles: [
                Tile(id: "zoom-mic", label: "Zoom mic", icon: "🎤", action: .init(type: "preset", preset: "zoom.mute"), x: 0, y: 0),
                Tile(id: "zoom-cam", label: "Zoom camera", icon: "📹", action: .init(type: "preset", preset: "zoom.video"), x: 1, y: 0),
                Tile(id: "teams-mic", label: "Teams mic", icon: "🎤", action: .init(type: "preset", preset: "teams.mute"), x: 2, y: 0),
                Tile(id: "meet-mic", label: "Meet mic", icon: "🎤", action: .init(type: "preset", preset: "meet.mute"), x: 3, y: 0),
                Tile(id: "slack-mic", label: "Slack huddle", icon: "🎧", action: .init(type: "preset", preset: "slack.huddleMute"), x: 4, y: 0),
                Tile(id: "copy", label: "Kopieer · lang: knip", icon: "📋",
                     action: .init(type: "keys.press", keys: "cmd+c"),
                     longPress: .init(type: "keys.press", keys: "cmd+x"), x: 0, y: 1),
                Tile(id: "paste", label: "Plak · 2×: zonder opmaak", icon: "📥",
                     action: .init(type: "keys.press", keys: "cmd+v"),
                     doubleTap: .init(type: "keys.press", keys: "cmd+alt+shift+v"), x: 1, y: 1),
                Tile(id: "spotlight", label: "Spotlight", icon: "🔎", action: .init(type: "keys.press", keys: "cmd+space"), x: 2, y: 1),
                Tile(id: "greeting", label: "Groet typen", icon: "✍️",
                     action: .init(type: "text.type", text: "Met vriendelijke groet,"), x: 3, y: 1),
                Tile(id: "note", label: "Nieuwe notitie", icon: "🗒",
                     action: .init(type: "macro", steps: [
                        .init(type: "app.open", app: "com.apple.Notes"),
                        .init(type: "delay", ms: 800),
                        .init(type: "keys.press", keys: "cmd+n"),
                        .init(type: "delay", ms: 300),
                        .init(type: "text.type", text: "Notitie van Cyberpad"),
                     ]), x: 4, y: 1),
                Tile(id: "focus", label: "Focus (Opdracht)", icon: "🌙",
                     action: .init(type: "shortcut.run", shortcut: "Focus aan"),
                     toggle: true,
                     offAction: .init(type: "shortcut.run", shortcut: "Focus uit"), x: 0, y: 2, w: 2),
                Tile(id: "shortcuts", label: "Opdrachten", icon: "⚡️", action: .init(type: "app.open", app: "com.apple.shortcuts"), x: 2, y: 2),
                Tile(id: "mission", label: "Mission Control", icon: "🪟", action: .init(type: "keys.press", keys: "ctrl+up"), x: 3, y: 2),
                Tile(id: "expose", label: "App-vensters", icon: "🗂", action: .init(type: "keys.press", keys: "ctrl+down"), x: 4, y: 2),
            ], apps: ["us.zoom.xos", "com.microsoft.teams2", "com.tinyspeck.slackmacgap", "com.microsoft.VSCode"]),
            Page(id: "widgets", name: "Widgets", tiles: [
                Tile(id: "nowplaying", label: "Nu speelt", kind: "nowplaying", x: 0, y: 0, w: 3),
                Tile(id: "weather", label: "Weer", kind: "weather", config: .init(city: "Amsterdam"), x: 3, y: 0, w: 2),
                Tile(id: "stats", label: "Systeem", kind: "stats", x: 0, y: 1, w: 2),
                Tile(id: "timer", label: "Timer", kind: "timer", config: .init(seconds: 300), x: 2, y: 1),
                Tile(id: "pomodoro", label: "Pomodoro", kind: "pomodoro", config: .init(work: 25, rest: 5), x: 3, y: 1),
                Tile(id: "world", label: "Wereldklok", kind: "worldclock",
                     config: .init(zones: ["America/New_York", "Asia/Tokyo"]), x: 4, y: 1),
                Tile(id: "ping", label: "Ping", kind: "terminal",
                     config: .init(command: "ping -c 5 1.1.1.1", timeout: 30), x: 0, y: 2, w: 3),
                Tile(id: "photos", label: "Foto's", kind: "photos", config: .init(seconds: 10), x: 3, y: 2, w: 2),
            ]),
            // Voorbeelden; pas de entiteiten en topics aan je eigen huis aan (zie README).
            Page(id: "home", name: "Huis", tiles: [
                Tile(id: "ha-lamp", label: "Woonkamer", icon: "💡",
                     action: .init(type: "ha.toggle", entity: "light.woonkamer"), x: 0, y: 0),
                Tile(id: "ha-dim", label: "Helderheid", kind: "slider",
                     action: .init(type: "ha.level", entity: "light.woonkamer"), x: 1, y: 0, w: 2),
                Tile(id: "ha-film", label: "Scène film", icon: "🎬",
                     action: .init(type: "ha.toggle", entity: "scene.film"), x: 3, y: 0),
                Tile(id: "ha-alloff", label: "Alle lampen uit", icon: "🌚",
                     action: .init(type: "ha.service", entity: "all", service: "light.turn_off"), x: 4, y: 0),
                Tile(id: "ha-thermo", label: "Thermostaat", kind: "ha",
                     config: .init(entity: "climate.woonkamer"), x: 0, y: 1, w: 2),
                Tile(id: "ha-outside", label: "Buiten", kind: "ha",
                     config: .init(entity: "sensor.buiten_temperatuur"), x: 2, y: 1),
                Tile(id: "mqtt-attic", label: "Zolder", kind: "mqtt",
                     config: .init(topic: "huis/zolder/temperatuur", unit: "°C"), x: 3, y: 1),
                Tile(id: "mqtt-fan", label: "Ventilator", icon: "🌀",
                     action: .init(type: "mqtt.publish", topic: "huis/ventilator/set", payload: "ON"),
                     toggle: true,
                     offAction: .init(type: "mqtt.publish", topic: "huis/ventilator/set", payload: "OFF"),
                     config: .init(topic: "huis/ventilator/state"), x: 4, y: 1),
                Tile(id: "ha-coffee", label: "Koffie", icon: "☕️",
                     action: .init(type: "ha.toggle", entity: "switch.koffiezetapparaat"), x: 0, y: 2),
                Tile(id: "hook-n8n", label: "n8n-flow", icon: "🪝",
                     action: .init(type: "webhook.call", webhook: "n8n"), x: 1, y: 2),
            ]),
            // Tablet als trackpad en draaiknoppen (fase 10). Muis en scrollen vereisen Toegankelijkheid.
            Page(id: "touch", name: "Bediening", tiles: [
                Tile(id: "touchpad", label: "Aanraakpad", kind: "touchpad", config: .init(speed: 1.5, natural: true),
                     x: 0, y: 0, w: 3, h: 3),
                Tile(id: "dial-volume", label: "Volume", kind: "dial", action: .init(type: "audio.volume"),
                     config: .init(step: 0.03), x: 3, y: 0),
                Tile(id: "dial-scroll", label: "Scrollen", kind: "dial", action: .init(type: "pointer.scroll"), x: 4, y: 0),
                Tile(id: "dial-spaces", label: "Bureaubladen", kind: "dial",
                     action: .init(type: "keys.press", keys: "ctrl+right"),
                     offAction: .init(type: "keys.press", keys: "ctrl+left"), x: 3, y: 1),
                Tile(id: "dial-zoom", label: "Zoomen", kind: "dial",
                     action: .init(type: "keys.press", keys: "cmd+="),
                     offAction: .init(type: "keys.press", keys: "cmd+-"), x: 4, y: 1),
                Tile(id: "dial-light", label: "Woonkamer", kind: "dial",
                     action: .init(type: "ha.level", entity: "light.woonkamer"), config: .init(step: 0.05), x: 3, y: 2),
                Tile(id: "mission2", label: "Mission Control", icon: "🪟", action: .init(type: "keys.press", keys: "ctrl+up"), x: 4, y: 2),
            ]),
            // Voorbeeldplugins uit shared/plugins; ze werken pas na Aanzetten in de menubalk.
            Page(id: "plugins", name: "Plugins", tiles: [
                Tile(id: "pl-hallo", label: "Zeg hallo", icon: "👋",
                     action: .init(type: "plugin", plugin: "hallo", action: "groet", params: ["naam": .string("Cyberpad")]), x: 0, y: 0),
                Tile(id: "pl-teller", label: "Teller", kind: "plugin",
                     config: .init(plugin: "hallo", widget: "teller"), x: 1, y: 0, w: 2),
                Tile(id: "pl-cloudflare", label: "Cloudflare", kind: "plugin",
                     config: .init(plugin: "bereikbaar", widget: "server", params: ["host": .string("1.1.1.1"), "port": .number(443)]),
                     x: 3, y: 0, w: 2),
                Tile(id: "pl-router", label: "Router", kind: "plugin",
                     config: .init(plugin: "bereikbaar", widget: "server", params: ["host": .string("192.168.1.1"), "port": .number(80)]),
                     x: 0, y: 1, w: 2),
            ]),
            Page(id: "system", name: "Systeem", tiles: [
                Tile(id: "lock", label: "Vergrendel", icon: "🔒", action: .init(type: "system.lock"), x: 0, y: 0),
                Tile(id: "display", label: "Scherm uit", icon: "🌑", action: .init(type: "system.displayOff"), x: 1, y: 0),
                Tile(id: "shot", label: "Screenshot", icon: "📸", action: .init(type: "system.screenshot"), x: 2, y: 0),
                Tile(id: "shotarea", label: "Selectie", icon: "✂️", action: .init(type: "system.screenshotArea"), x: 3, y: 0),
                Tile(id: "finder", label: "Finder", icon: "🗂", action: .init(type: "app.open", app: "com.apple.finder"), x: 4, y: 0),
                Tile(id: "github", label: "GitHub", icon: "🌐", action: .init(type: "url.open", url: "https://github.com"), x: 0, y: 1),
                Tile(id: "mic-level", label: "Mic-volume", kind: "slider", action: .init(type: "audio.micVolume"), x: 0, y: 2),
                Tile(id: "clock2", label: "Tijd", kind: "clock", x: 1, y: 1, w: 4, h: 2),
            ]),
        ],
        profiles: [
            Profile(id: "werk", name: "Werkdag", pages: ["main", "work", "touch", "widgets", "plugins", "system"],
                    when: [TimeRule(days: [1, 2, 3, 4, 5], from: "08:00", to: "18:00")]),
            Profile(id: "thuis", name: "Thuis", pages: ["main", "home", "touch", "widgets", "plugins", "system"], default: true),

        ]
    )
}

/// Laadt `layout.json` uit Application Support en houdt het bestand in de gaten, zodat bewerken direct doorkomt.
final class LayoutStore {
    let url: URL
    private(set) var layout: Layout
    private(set) var lastError: String?
    private var mtime: Date?
    private var timer: Timer?
    var onChange: ((Layout) -> Void)?

    init(dir: URL) {
        url = dir.appendingPathComponent("layout.json")
        layout = .default
        if !FileManager.default.fileExists(atPath: url.path) { save(.default) }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkForChanges() }
    }

    func save(_ l: Layout) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? enc.encode(l) { try? data.write(to: url, options: .atomic) }
    }

    /// Zet de standaard-layout terug. Het huidige bestand wordt eerst bewaard als `layout-backup-<datum>.json`.
    @discardableResult
    func resetToDefault() -> URL? {
        var backup: URL?
        if FileManager.default.fileExists(atPath: url.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            let b = url.deletingLastPathComponent().appendingPathComponent("layout-backup-\(f.string(from: Date())).json")
            try? FileManager.default.copyItem(at: url, to: b)
            backup = b
        }
        save(.default)
        reload()
        return backup
    }

    /// Vingerafdruk van het bestand zoals het nu op schijf staat (tegen gelijktijdig bewerken).
    var revision: String {
        guard let d = try? Data(contentsOf: url) else { return "" }
        return PairingManager.sha256(String(decoding: d, as: UTF8.self))
    }

    enum EditorSave { case ok(String), conflict, invalid([String]) }

    /// Opslaan vanuit de editor: alleen als niemand anders intussen iets veranderde, met back-up (laatste 20 bewaard).
    func saveFromEditor(_ l: Layout, baseRevision: String?) -> EditorSave {
        if let base = baseRevision, base != revision { return .conflict }
        let problems = l.problems()
        guard problems.isEmpty else { return .invalid(problems) }
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        try? fm.copyItem(at: url, to: dir.appendingPathComponent("layout-backup-editor-\(f.string(from: Date())).json"))
        if let old = try? fm.contentsOfDirectory(atPath: dir.path).filter({ $0.hasPrefix("layout-backup-editor-") }).sorted(),
           old.count > 20 {
            for name in old.prefix(old.count - 20) { try? fm.removeItem(at: dir.appendingPathComponent(name)) }
        }
        save(l)
        reload()
        return .ok(revision)
    }

    private func modDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func checkForChanges() {
        let m = modDate()
        if m != mtime { reload() }
    }

    private func reload() {
        mtime = modDate()
        do {
            let data = try Data(contentsOf: url)
            let l = try JSONDecoder().decode(Layout.self, from: data)
            lastError = nil
            if l != layout { layout = l; onChange?(l) }
        } catch {
            lastError = "layout.json kon niet worden gelezen: \(error.localizedDescription)"
            NSLog("Cyberpad: %@", lastError!)
        }
    }
}


// MARK: Controle (editor)

extension Layout {
    static let maxColumns = 12
    static let maxRows = 8

    /// Fouten die opslaan tegenhouden. Leeg = in orde.
    func problems() -> [String] {
        var out: [String] = []
        if !(1...Self.maxColumns).contains(columns) { out.append("Kolommen moet tussen 1 en \(Self.maxColumns) liggen") }
        if !(1...Self.maxRows).contains(rows) { out.append("Rijen moet tussen 1 en \(Self.maxRows) liggen") }
        if pages.isEmpty { out.append("Er moet minstens één pagina zijn") }
        var pageIDs = Set<String>(), tileIDs = Set<String>()
        for p in pages {
            if p.id.isEmpty || !pageIDs.insert(p.id).inserted { out.append("Pagina-id “\(p.id)” is leeg of dubbel") }
            if p.name.trimmingCharacters(in: .whitespaces).isEmpty { out.append("Pagina “\(p.id)” heeft geen naam") }
            var taken = Set<Int>()
            for t in p.tiles {
                if t.id.isEmpty || !tileIDs.insert(t.id).inserted { out.append("Tegel-id “\(t.id)” is leeg of dubbel") }
                let w = t.w ?? 1, h = t.h ?? 1
                if t.x < 0 || t.y < 0 || w < 1 || h < 1 || t.x + w > columns || t.y + h > rows {
                    out.append("“\(t.label)” op \(p.name) valt buiten het raster")
                    continue
                }
                for dy in 0..<h {
                    for dx in 0..<w where !taken.insert((t.y + dy) * 100 + t.x + dx).inserted {
                        out.append("“\(t.label)” op \(p.name) overlapt een andere tegel")
                    }
                }
            }
        }
        var profileIDs = Set<String>()
        for pr in profiles ?? [] {
            if pr.id.isEmpty || !profileIDs.insert(pr.id).inserted { out.append("Profiel-id “\(pr.id)” is leeg of dubbel") }
            for pid in pr.pages where !pageIDs.contains(pid) { out.append("Profiel “\(pr.name)” noemt een onbekende pagina “\(pid)”") }
            for r in pr.when ?? [] {
                if r.from != nil && TimeRule.minutes(r.from) == nil || r.to != nil && TimeRule.minutes(r.to) == nil {
                    out.append("Profiel “\(pr.name)”: tijd moet als UU:MM")
                }
                if let d = r.days, d.contains(where: { !(1...7).contains($0) }) { out.append("Profiel “\(pr.name)”: dagen zijn 1 (ma) t/m 7 (zo)") }
            }
        }
        // Dubbele meldingen (bijv. een overlap over meerdere vakken) één keer tonen.
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}
