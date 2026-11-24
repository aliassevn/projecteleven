import AppKit
import SwiftUI

/// Toegang tot de layout-editor (shared/editor).
/// - Op de Mac zelf: met een geheim token dat alleen het editorvenster kent, en alleen vanaf 127.0.0.1.
/// - Op een tablet: elke gekoppelde tablet mag meteen bewerken (met zijn apparaat-token), zonder extra toestemming.
final class EditorService: ObservableObject {
    let token = PairingManager.randomHex(bytes: 32)
    private var appsCache: (at: Date, list: [[String: String]])?
    /// Namen uit de Opdrachten-app; op de achtergrond ververst (`shortcuts list`).
    private var shortcutNames: [String] = []
    private var shortcutsFetched = Date.distantPast
    private var shortcutsBusy = false

    weak var pairing: PairingManager?

    enum Who { case mac, device(String) }

    /// Mag dit verzoek de editor gebruiken? Het Mac-venster of een gekoppelde tablet.
    func authorize(_ req: HTTPRequest, loopback: Bool) -> Who? {
        if loopback, let t = req.headers["x-cyberpad-editor"], PairingManager.constantTimeEqual(t, token) { return .mac }
        guard let d = pairing?.authenticate(token: req.headers["x-cyberpad-token"]) else { return nil }
        return .device(d.id)
    }

    // MARK: Catalogus voor de editor (wat er te kiezen valt)

    func catalog(presets: ShortcutCatalog, plugins: PluginManager) -> [String: Any] {
        [
            "platform": PluginManifest.platform,
            "presets": presets.apps.flatMap { app in
                app.shortcuts.map { ["id": "\(app.id).\($0.id)", "app": app.name, "name": L($0.label), "keys": $0.keys] }
            },
            "plugins": plugins.sorted.map { p -> [String: Any] in
                let m = p.manifest
                func params(_ ps: [PluginManifest.Param]?) -> [[String: Any]] {
                    (ps ?? []).map { ["id": $0.id, "name": $0.name ?? $0.id, "type": $0.type ?? "string", "default": $0.default?.any ?? NSNull()] }
                }
                return ["id": m.id, "name": m.name, "icon": m.icon ?? "🧩", "enabled": plugins.isApproved(m.id),
                        "actions": (m.actions ?? []).map { ["id": $0.id, "name": $0.name, "params": params($0.params)] },
                        "widgets": (m.widgets ?? []).map { ["id": $0.id, "name": $0.name, "params": params($0.params)] }]
            },
            "apps": installedApps(),
            "shortcuts": shortcutsList(),
        ]
    }

    /// Geeft de laatst bekende lijst en ververst hem op de achtergrond (hoogstens eens per minuut).
    private func shortcutsList() -> [String] {
        if !shortcutsBusy, Date().timeIntervalSince(shortcutsFetched) > 60 {
            shortcutsBusy = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let names = Self.fetchShortcuts()
                DispatchQueue.main.async {
                    self?.shortcutNames = names
                    self?.shortcutsFetched = Date()
                    self?.shortcutsBusy = false
                }
            }
        }
        return shortcutNames
    }

    private static func fetchShortcuts() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["list"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(500)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Geïnstalleerde apps (naam + bundle-id) voor de app-kiezer; eens per 5 minuten opnieuw gelezen.
    private func installedApps() -> [[String: String]] {
        if let c = appsCache, Date().timeIntervalSince(c.at) < 300 { return c.list }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var seen = Set<String>(), out: [[String: String]] = []
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "\(home)/Applications"] {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in items where name.hasSuffix(".app") {
                guard let b = Bundle(path: "\(dir)/\(name)"), let id = b.bundleIdentifier, seen.insert(id).inserted else { continue }
                let display = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? String(name.dropLast(4))
                out.append(["name": display, "id": id])
            }
        }
        out.sort { $0["name"]!.localizedCaseInsensitiveCompare($1["name"]!) == .orderedAscending }
        appsCache = (Date(), out)
        return out
    }
}
