import AppKit
import Combine

/// Houdt alle onderdelen bij elkaar en levert de status voor het menubalk-venster.
final class Core: ObservableObject {
    static let shared = Core()

    let supportDir: URL
    let pairing: PairingManager
    let layouts: LayoutStore
    let actions = ActionRunner()
    let server: Server
    private let alias = HostAlias()

    @Published private(set) var ips: [String] = []
    @Published private(set) var online: Set<String> = []
    @Published private(set) var serverError: String?
    @Published private(set) var hasAccessibility = false
    @Published private(set) var layoutError: String?

    private var timers: [Timer] = []
    private var lastState: NSDictionary = [:]
    private var bag: Set<AnyCancellable> = []

    static let hostURL = "http://cyberpad.local:\(Server.port)"

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("Cyberpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        pairing = PairingManager(dir: supportDir)
        layouts = LayoutStore(dir: supportDir)
        server = Server(pairing: pairing, layouts: layouts, actions: actions, padDir: Self.findPadDir())

        // Wijzigingen in PairingManager doorgeven aan de UI.
        pairing.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        pairing.onRevoke = { [weak self] id in self?.server.disconnect(deviceID: id) }
        layouts.onChange = { [weak self] _ in
            self?.server.broadcastLayout()
            self?.layoutError = self?.layouts.lastError
        }
        server.onClientsChanged = { [weak self] in
            guard let self else { return }
            self.online = self.server.onlineDeviceIDs
            self.serverError = self.server.lastError
        }
    }

    func start() {
        do {
            try server.start(serviceName: "Cyberpad (\(Host.current().localizedName ?? "Mac"))")
        } catch {
            serverError = "Server kon niet starten: \(error.localizedDescription)"
        }
        refreshNetwork()
        hasAccessibility = actions.hasAccessibility

        timers = [
            // Status (volume, mute…) doorsturen als die op de Mac zelf verandert.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() },
            Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshNetwork() },
        ]
        if ProcessInfo.processInfo.environment["CYBERPAD_DEBUG"] != nil {
            NSLog("Cyberpad: koppelcode %@", pairing.code)
        }
    }

    private func tick() {
        pairing.rotateIfExpired()
        let s = actions.state() as NSDictionary
        if s != lastState {
            lastState = s
            server.broadcast(["type": "state", "state": s])
        }
        if hasAccessibility != actions.hasAccessibility { hasAccessibility = actions.hasAccessibility }
        if layoutError != layouts.lastError { layoutError = layouts.lastError }
    }

    private func refreshNetwork() {
        let now = NetUtil.localIPv4s()
        if now != ips { ips = now }
        alias.update(ipv4s: now)
    }

    var directURL: String? { ips.first.map { "http://\($0):\(Server.port)" } }

    // MARK: Acties vanuit het menu

    func openLayoutFile() { NSWorkspace.shared.open(layouts.url) }
    func openSupportFolder() { NSWorkspace.shared.open(supportDir) }
    func requestAccessibility() {
        actions.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Volgorde: omgevingsvariabele (ontwikkelen) → in de app-bundel → ./pad
    private static func findPadDir() -> URL {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["CYBERPAD_PAD_DIR"] {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("pad", isDirectory: true),
           fm.fileExists(atPath: res.appendingPathComponent("index.html").path) {
            return res
        }
        return URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("pad", isDirectory: true)
    }
}
