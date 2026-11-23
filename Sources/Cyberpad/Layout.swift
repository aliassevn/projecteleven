import Foundation

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

    init(type: String, app: String? = nil, url: String? = nil, keys: String? = nil, text: String? = nil,
         shortcut: String? = nil, preset: String? = nil, steps: [ActionSpec]? = nil, ms: Int? = nil) {
        self.type = type; self.app = app; self.url = url; self.keys = keys; self.text = text
        self.shortcut = shortcut; self.preset = preset; self.steps = steps; self.ms = ms
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
    var x: Int
    var y: Int
    var w: Int?
    var h: Int?

    init(id: String, label: String, icon: String? = nil, kind: String? = nil, action: ActionSpec? = nil,
         longPress: ActionSpec? = nil, doubleTap: ActionSpec? = nil, toggle: Bool? = nil, offAction: ActionSpec? = nil,
         x: Int, y: Int, w: Int? = nil, h: Int? = nil) {
        self.id = id; self.label = label; self.icon = icon; self.kind = kind; self.action = action
        self.longPress = longPress; self.doubleTap = doubleTap; self.toggle = toggle; self.offAction = offAction
        self.x = x; self.y = y; self.w = w; self.h = h
    }

    var isButton: Bool { kind == nil || kind == "button" }
}

struct Page: Codable, Equatable {
    var id: String
    var name: String
    var tiles: [Tile]
}

struct Layout: Codable, Equatable {
    var version: Int
    var columns: Int
    var rows: Int
    var theme: String
    var pages: [Page]

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
                Tile(id: "clock", label: "Tijd", kind: "clock", x: 1, y: 2, w: 2),
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
            ]),
            Page(id: "system", name: "Systeem", tiles: [
                Tile(id: "lock", label: "Vergrendel", icon: "🔒", action: .init(type: "system.lock"), x: 0, y: 0),
                Tile(id: "display", label: "Scherm uit", icon: "🌑", action: .init(type: "system.displayOff"), x: 1, y: 0),
                Tile(id: "shot", label: "Screenshot", icon: "📸", action: .init(type: "system.screenshot"), x: 2, y: 0),
                Tile(id: "shotarea", label: "Selectie", icon: "✂️", action: .init(type: "system.screenshotArea"), x: 3, y: 0),
                Tile(id: "finder", label: "Finder", icon: "🗂", action: .init(type: "app.open", app: "com.apple.finder"), x: 4, y: 0),
                Tile(id: "github", label: "GitHub", icon: "🌐", action: .init(type: "url.open", url: "https://github.com"), x: 0, y: 1),
                Tile(id: "clock2", label: "Tijd", kind: "clock", x: 1, y: 1, w: 4, h: 2),
            ]),
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
