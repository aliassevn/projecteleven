import Foundation

/// Wat een knop doet. De tablet stuurt alleen het id van een tegel; de actie zelf staat hier, op de Mac.
struct ActionSpec: Codable, Equatable {
    var type: String
    var app: String?
    var url: String?
}

struct Tile: Codable, Equatable {
    var id: String
    var label: String
    var icon: String?
    /// "button" (standaard), "slider" of "clock"
    var kind: String?
    var action: ActionSpec?
    var x: Int
    var y: Int
    var w: Int?
    var h: Int?

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
                Tile(id: "prev", label: "Vorige", icon: "⏮", kind: nil, action: .init(type: "media.previous"), x: 0, y: 0),
                Tile(id: "play", label: "Play / pauze", icon: "⏯", kind: nil, action: .init(type: "media.playPause"), x: 1, y: 0),
                Tile(id: "next", label: "Volgende", icon: "⏭", kind: nil, action: .init(type: "media.next"), x: 2, y: 0),
                Tile(id: "mute", label: "Geluid uit", icon: "🔇", kind: nil, action: .init(type: "audio.mute"), x: 3, y: 0),
                Tile(id: "mic", label: "Mic uit", icon: "🎙", kind: nil, action: .init(type: "audio.micMute"), x: 4, y: 0),
                Tile(id: "volume", label: "Volume", icon: nil, kind: "slider", action: .init(type: "audio.volume"), x: 0, y: 1, w: 3),
                Tile(id: "voldown", label: "Vol −", icon: "🔉", kind: nil, action: .init(type: "audio.volumeDown"), x: 3, y: 1),
                Tile(id: "volup", label: "Vol +", icon: "🔊", kind: nil, action: .init(type: "audio.volumeUp"), x: 4, y: 1),
                Tile(id: "safari", label: "Safari", icon: "🧭", kind: nil, action: .init(type: "app.open", app: "com.apple.Safari"), x: 0, y: 2),
                Tile(id: "clock", label: "Tijd", icon: nil, kind: "clock", action: nil, x: 1, y: 2, w: 2),
                Tile(id: "dark", label: "Dark mode", icon: "🌗", kind: nil, action: .init(type: "system.darkMode"), x: 3, y: 2),
                Tile(id: "awake", label: "Wakker", icon: "☕️", kind: nil, action: .init(type: "system.keepAwake"), x: 4, y: 2),
            ]),
            Page(id: "system", name: "Systeem", tiles: [
                Tile(id: "lock", label: "Vergrendel", icon: "🔒", kind: nil, action: .init(type: "system.lock"), x: 0, y: 0),
                Tile(id: "display", label: "Scherm uit", icon: "🌑", kind: nil, action: .init(type: "system.displayOff"), x: 1, y: 0),
                Tile(id: "shot", label: "Screenshot", icon: "📸", kind: nil, action: .init(type: "system.screenshot"), x: 2, y: 0),
                Tile(id: "shotarea", label: "Selectie", icon: "✂️", kind: nil, action: .init(type: "system.screenshotArea"), x: 3, y: 0),
                Tile(id: "finder", label: "Finder", icon: "🗂", kind: nil, action: .init(type: "app.open", app: "com.apple.finder"), x: 4, y: 0),
                Tile(id: "github", label: "GitHub", icon: "🌐", kind: nil, action: .init(type: "url.open", url: "https://github.com"), x: 0, y: 1),
                Tile(id: "clock2", label: "Tijd", icon: nil, kind: "clock", action: nil, x: 1, y: 1, w: 4, h: 2),
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
