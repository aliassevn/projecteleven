import Foundation

/// De shortcut-bibliotheek (`catalog/shortcuts.json`): standaard-sneltoetsen per app.
struct ShortcutCatalog: Codable {
    struct Shortcut: Codable {
        var id: String
        var label: String
        var keys: String
    }
    struct App: Codable {
        var id: String
        var name: String
        var bundleIds: [String]
        var activate: Bool
        var shortcuts: [Shortcut]
    }
    var version: Int
    var apps: [App]

    static let empty = ShortcutCatalog(version: 1, apps: [])

    /// Zoekt "zoom.mute" op.
    func find(_ preset: String) -> (app: App, shortcut: Shortcut)? {
        let parts = preset.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, let app = apps.first(where: { $0.id == parts[0] }),
              let sc = app.shortcuts.first(where: { $0.id == parts[1] }) else { return nil }
        return (app, sc)
    }

    static func load(from url: URL) -> ShortcutCatalog {
        guard let data = try? Data(contentsOf: url) else {
            NSLog("Cyberpad: shortcut-bibliotheek niet gevonden op %@", url.path)
            return .empty
        }
        do { return try JSONDecoder().decode(ShortcutCatalog.self, from: data) } catch {
            NSLog("Cyberpad: shortcut-bibliotheek ongeldig: %@", error.localizedDescription)
            return .empty
        }
    }
}
