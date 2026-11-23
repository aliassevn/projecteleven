import AppKit
import SwiftUI

/// Toegang tot de layout-editor (shared/editor).
/// - Op de Mac zelf: met een geheim token dat alleen het editorvenster kent, en alleen vanaf 127.0.0.1.
/// - Op een tablet: pas nadat je het op de Mac goedkeurt; dan 30 minuten (verlengd bij gebruik).
final class EditorService: ObservableObject {
    static let grantDuration: TimeInterval = 30 * 60

    let token = PairingManager.randomHex(bytes: 32)
    @Published private(set) var pending: [String] = []
    private var grants: [String: Date] = [:]
    private var appsCache: (at: Date, list: [[String: String]])?

    weak var pairing: PairingManager?
    /// Nieuw verzoek van een tablet → Core toont een venster om toe te staan of te weigeren.
    var onRequest: ((Device) -> Void)?

    enum Who { case mac, device(String) }

    /// Mag dit verzoek de editor gebruiken?
    func authorize(_ req: HTTPRequest, loopback: Bool) -> Who? {
        if loopback, let t = req.headers["x-cyberpad-editor"], PairingManager.constantTimeEqual(t, token) { return .mac }
        guard let d = pairing?.authenticate(token: req.headers["x-cyberpad-token"]),
              let until = grants[d.id], until > Date() else { return nil }
        grants[d.id] = Date().addingTimeInterval(Self.grantDuration) // verlengen zolang je bewerkt
        return .device(d.id)
    }

    /// Tablet vraagt om te mogen bewerken. Antwoord: "granted", "pending" of "denied".
    func request(_ device: Device) -> String {
        if let until = grants[device.id], until > Date() { return "granted" }
        if !pending.contains(device.id) {
            pending.append(device.id)
            onRequest?(device)
        }
        return "pending"
    }

    func status(_ deviceID: String) -> String {
        if let until = grants[deviceID], until > Date() { return "granted" }
        return pending.contains(deviceID) ? "pending" : "denied"
    }

    func approve(_ deviceID: String) {
        pending.removeAll { $0 == deviceID }
        grants[deviceID] = Date().addingTimeInterval(Self.grantDuration)
    }

    func deny(_ deviceID: String) {
        pending.removeAll { $0 == deviceID }
        grants[deviceID] = nil
    }

    func revokeAll(for deviceID: String) {
        pending.removeAll { $0 == deviceID }
        grants[deviceID] = nil
    }

    // MARK: Catalogus voor de editor (wat er te kiezen valt)

    func catalog(presets: ShortcutCatalog, plugins: PluginManager) -> [String: Any] {
        [
            "platform": PluginManifest.platform,
            "presets": presets.apps.flatMap { app in
                app.shortcuts.map { ["id": "\(app.id).\($0.id)", "app": app.name, "name": $0.label, "keys": $0.keys] }
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
        ]
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

/// Klein venster: "iPad wil de layout bewerken" met Toestaan / Weigeren. Blokkeert de rest van Cyberpad niet.
final class EditorApprovalPanel {
    private var panels: [String: NSPanel] = [:]

    func show(_ device: Device, approve: @escaping () -> Void, deny: @escaping () -> Void) {
        guard panels[device.id] == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Cyberpad"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        let close = { [weak self] in
            self?.panels[device.id]?.close()
            self?.panels[device.id] = nil
        }
        panel.contentView = NSHostingView(rootView: VStack(alignment: .leading, spacing: 10) {
            Text("“\(device.name)” wil de layout bewerken").font(.headline)
            Text("Na toestaan kan deze tablet 30 minuten knoppen, acties en pagina’s wijzigen. Sta het alleen toe als jij dat net vroeg.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Weigeren") { deny(); close() }
                Button("Toestaan") { approve(); close() }.keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 360))
        panel.center()
        panels[device.id] = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
