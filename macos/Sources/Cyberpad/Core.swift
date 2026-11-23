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
    let meeting: MeetingMonitor
    let agenda = AgendaProvider()
    let widgets = WidgetHub()
    let integrations: Integrations
    let plugins: PluginManager
    let context: ContextEngine
    let editor = EditorService()
    private let approvals = EditorApprovalPanel()
    private let alias = HostAlias()

    @Published private(set) var ips: [String] = []
    @Published private(set) var online: Set<String> = []
    @Published private(set) var serverError: String?
    @Published private(set) var hasAccessibility = false
    @Published private(set) var layoutError: String?
    @Published private(set) var meetingInfo: MeetingInfo?
    @Published private(set) var agendaAccess: AgendaProvider.Access = .notDetermined

    private var timers: [Timer] = []
    private var lastState: NSDictionary = [:]
    private var tickCount = 0
    private var bag: Set<AnyCancellable> = []

    static let hostURL = "http://cyberpad.local:\(Server.port)"

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDir = base.appendingPathComponent("Cyberpad", isDirectory: true)
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        pairing = PairingManager(dir: supportDir)
        integrations = Integrations(dir: supportDir)
        plugins = PluginManager(supportDir: supportDir, builtInDir: Self.findResource("plugins", env: "CYBERPAD_PLUGINS_DIR"))
        layouts = LayoutStore(dir: supportDir)
        context = ContextEngine(layout: layouts.layout)
        server = Server(pairing: pairing, layouts: layouts, actions: actions, padDir: Self.findResource("pad", env: "CYBERPAD_PAD_DIR"))
        meeting = MeetingMonitor(actions: actions)
        actions.catalog = ShortcutCatalog.load(from: Self.findResource("catalog", env: "CYBERPAD_CATALOG_DIR")
            .appendingPathComponent("shortcuts.json"))
        actions.onAsyncError = { [weak self] msg in self?.server.broadcast(["type": "toast", "text": msg]) }
        server.meeting = meeting
        server.agenda = agenda
        server.widgets = widgets
        server.integrations = integrations
        actions.integrations = integrations
        widgets.integrations = integrations
        integrations.update(layouts.layout)
        integrations.onChange = { [weak self] in self?.server.scheduleStateBroadcast() }
        integrations.onError = { [weak self] msg in self?.server.broadcast(["type": "toast", "text": msg]) }
        integrations.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        actions.plugins = plugins
        widgets.plugins = plugins
        plugins.onChange = { [weak self] in self?.server.scheduleStateBroadcast() }
        plugins.onToast = { [weak self] msg in self?.server.broadcast(["type": "toast", "text": msg]) }
        plugins.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        plugins.scan()
        plugins.update(layouts.layout)
        server.context = context
        context.onContextChange = { [weak self] in self?.server.scheduleStateBroadcast() }
        context.onProfileChange = { [weak self] in self?.server.broadcastLayout() }
        context.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        pairing.onProfileChange = { [weak self] _ in self?.server.broadcastLayout() }
        editor.pairing = pairing
        server.editor = editor
        server.plugins = plugins
        server.editorDir = Self.findResource("editor", env: "CYBERPAD_EDITOR_DIR")
        editor.onRequest = { [weak self] device in
            guard let self else { return }
            self.approvals.show(device, approve: { self.editor.approve(device.id) }, deny: { self.editor.deny(device.id) })
        }
        widgets.update(layouts.layout)
        widgets.onChange = { [weak self] in self?.server.scheduleStateBroadcast() }
        widgets.onToast = { [weak self] msg in self?.server.broadcast(["type": "toast", "text": msg]) }
        agenda.onChange = { [weak self] in
            guard let self else { return }
            self.agendaAccess = self.agenda.access
            self.server.scheduleStateBroadcast()
        }

        // Wijzigingen in PairingManager doorgeven aan de UI.
        pairing.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        pairing.onRevoke = { [weak self] id in
            self?.editor.revokeAll(for: id)
            self?.server.disconnect(deviceID: id)
        }
        layouts.onChange = { [weak self] l in
            self?.context.update(l)
            self?.widgets.update(l)
            self?.integrations.update(l)
            self?.plugins.update(l)
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
        integrations.start()
        hasAccessibility = actions.hasAccessibility
        agendaAccess = agenda.access
        // Alleen om Agenda-toegang vragen als er een agendategel in de layout staat.
        if agenda.access == .notDetermined, layoutHasAgenda { agenda.requestAccess() }
        agenda.refresh(force: true)

        timers = [
            // Status (volume, mute…) doorsturen als die op de Mac zelf verandert.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() },
            Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshNetwork() },
        ]
        if ProcessInfo.processInfo.environment["CYBERPAD_DEBUG"] != nil {
            NSLog("Cyberpad: koppelcode %@", pairing.code)
            NSLog("Cyberpad: editor http://127.0.0.1:%d/editor/#mac=%@", Int(Server.port), editor.token)
        }
    }

    private func tick() {
        pairing.rotateIfExpired()
        tickCount += 1
        if tickCount % 2 == 0 {
            meeting.refresh()
            if meetingInfo != meeting.current { meetingInfo = meeting.current }
        }
        agenda.refresh()
        if tickCount % 3 == 0 { integrations.reloadIfChanged(); plugins.rescanIfChanged() }
        if tickCount % 15 == 0 { context.tick() }
        widgets.tick(active: server.hasActiveClients)
        let s = server.fullState() as NSDictionary
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

    var layoutHasAgenda: Bool {
        layouts.layout.pages.contains { $0.tiles.contains { $0.kind == "agenda" } }
    }

    func requestAgendaAccess() { agenda.requestAccess() }

    var directURL: String? { ips.first.map { "http://\($0):\(Server.port)" } }

    // MARK: Acties vanuit het menu

    func openLayoutFile() { NSWorkspace.shared.open(layouts.url) }
    func openEditor() { EditorWindow.shared.show(token: editor.token) }
    func openSupportFolder() { NSWorkspace.shared.open(supportDir) }
    func openIntegrations() { IntegrationsWindow.shared.show() }
    /// cyberpad://profile/<id> (bijv. vanuit een Focus-automatisering in Opdrachten).
    func handle(url: URL) {
        if let err = context.handle(url) {
            NSLog("Cyberpad: %@", err)
            server.broadcast(["type": "toast", "text": err])
        }
    }

    func openPluginFolder() { NSWorkspace.shared.open(plugins.userDir) }

    /// Een plugin draait met jouw rechten; daarom eerst een duidelijke vraag.
    func approvePlugin(_ id: String) {
        guard let p = plugins.plugins[id] else { return }
        let alert = NSAlert()
        alert.messageText = "Plugin “\(p.manifest.name)” aanzetten?"
        var info = "Een plugin is een programma dat met jouw rechten op deze Mac draait. Zet hem alleen aan als je de maker vertrouwt."
        if let a = p.manifest.author { info += "\n\nMaker: \(a)" }
        info += "\nMap: \(p.dir.path)\nOpdracht: \((p.manifest.command ?? []).joined(separator: " "))"
        info += "\n\nVerandert er later iets aan de bestanden, dan staat de plugin weer uit tot je hem opnieuw toestaat."
        alert.informativeText = info
        alert.addButton(withTitle: "Aanzetten")
        alert.addButton(withTitle: "Annuleer")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        plugins.approve(id)
    }

    /// Standaard-layout terugzetten; de oude wordt eerst als back-up bewaard.
    func resetLayout() {
        let alert = NSAlert()
        alert.messageText = "Standaard-layout terugzetten?"
        alert.informativeText = "Je huidige layout.json wordt eerst bewaard als back-up in de Cyberpad-map."
        alert.addButton(withTitle: "Terugzetten")
        alert.addButton(withTitle: "Annuleer")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        layouts.resetToDefault()
    }
    func requestAccessibility() {
        actions.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Volgorde: omgevingsvariabele (ontwikkelen) → in de app-bundel → shared/<naam> in de repo
    static func findResource(_ name: String, env: String) -> URL {
        let fm = FileManager.default
        if let dir = ProcessInfo.processInfo.environment[env] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        if let res = Bundle.main.resourceURL?.appendingPathComponent(name, isDirectory: true),
           fm.fileExists(atPath: res.path) {
            return res
        }
        // Ontwikkelen vanuit de repo: shared/<naam> (vanuit de hoofdmap of vanuit macos/).
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        let candidates = [cwd.appendingPathComponent("shared/\(name)"), cwd.appendingPathComponent("../shared/\(name)")]
        return (candidates.first { fm.fileExists(atPath: $0.path) } ?? cwd.appendingPathComponent(name)).standardizedFileURL
    }
}
