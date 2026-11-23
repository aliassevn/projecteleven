import Foundation

/// Voert een in de layout vastgelegd commando uit en toont de uitvoer live op de tablet.
/// De tablet kan alleen starten en stoppen; het commando zelf staat alleen op de Mac.
final class TerminalService {
    struct Run {
        var status: String = "idle"   // idle, running, done, failed, stopped, timeout
        var exit: Int32?
        var output = ""
        var started: Date?
        var ended: Date?
        var process: Process?
        var timeoutItem: DispatchWorkItem?
        var stopReason: String?
    }

    static let maxOutput = 6000
    static let defaultTimeout = 60
    static let maxTimeout = 600

    private var runs: [String: Run] = [:]
    var onUpdate: (() -> Void)?
    private var updatePending = false

    func json(_ id: String, cfg: WidgetConfig?) -> [String: Any] {
        let r = runs[id] ?? Run()
        var d: [String: Any] = ["status": r.status, "output": r.output, "dangerous": cfg?.dangerous == true]
        if let e = r.exit { d["exit"] = Int(e) }
        if let s = r.started { d["started"] = Int(s.timeIntervalSince1970 * 1000) }
        if let e = r.ended { d["ended"] = Int(e.timeIntervalSince1970 * 1000) }
        if cfg?.command == nil { d["error"] = "Geen commando ingesteld" }
        return d
    }

    /// run (value 1 = bevestigd), stop, clear
    func handle(_ tile: Tile, action: String, confirmed: Bool) throws {
        switch action {
        case "run":
            guard let cmd = tile.config?.command, !cmd.isEmpty else { throw ActionRunner.ActionError.missing("config.command") }
            if tile.config?.dangerous == true && !confirmed {
                throw ActionRunner.ActionError.failed("Bevestig eerst op de tablet")
            }
            if runs[tile.id]?.status == "running" { throw ActionRunner.ActionError.failed("Draait al") }
            start(tile.id, cmd, cfg: tile.config)
        case "stop":
            stop(tile.id, reason: "stopped")
        case "clear":
            if runs[tile.id]?.status != "running" { runs[tile.id] = Run() }
        default:
            throw ActionRunner.ActionError.failed("Onbekende terminalactie")
        }
        notify()
    }

    private func start(_ id: String, _ cmd: String, cfg: WidgetConfig?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", cmd] // login-shell, zodat je eigen PATH (Homebrew e.d.) werkt
        if let cwd = cfg?.cwd {
            p.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        var run = Run(status: "running", started: Date(), process: p)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
            DispatchQueue.main.async { self?.append(id, text) }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                // Laatste restje uitvoer meenemen.
                if let rest = try? pipe.fileHandleForReading.readToEnd(), let t = String(data: rest, encoding: .utf8), !t.isEmpty {
                    self?.append(id, t)
                }
                self?.finished(id, code)
            }
        }

        do {
            try p.run()
        } catch {
            run.status = "failed"
            run.output = "Kon niet starten: \(error.localizedDescription)"
            run.ended = Date()
            runs[id] = run
            return
        }

        let secs = min(max(cfg?.timeout ?? Self.defaultTimeout, 1), Self.maxTimeout)
        let item = DispatchWorkItem { [weak self] in self?.stop(id, reason: "timeout") }
        run.timeoutItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(secs), execute: item)
        runs[id] = run
    }

    private func stop(_ id: String, reason: String) {
        guard var r = runs[id], r.status == "running", let p = r.process else { return }
        r.stopReason = reason
        runs[id] = r
        // Eerst de kinderen (bijv. ping) en dan de shell; na 2 s hard afbreken.
        let pid = p.processIdentifier
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-TERM", "-P", String(pid)]
        try? killer.run()
        p.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func append(_ id: String, _ text: String) {
        guard var r = runs[id] else { return }
        r.output += Self.stripANSI(text)
        if r.output.count > Self.maxOutput { r.output = String(r.output.suffix(Self.maxOutput)) }
        runs[id] = r
        notify()
    }

    private func finished(_ id: String, _ code: Int32) {
        guard var r = runs[id] else { return }
        r.timeoutItem?.cancel()
        r.exit = code
        r.ended = Date()
        r.process = nil
        switch r.stopReason {
        case "timeout": r.status = "timeout"
        case "stopped": r.status = "stopped"
        default: r.status = code == 0 ? "done" : "failed"
        }
        runs[id] = r
        notify()
    }

    /// Hoogstens ~4× per seconde een update naar de tablets.
    private func notify() {
        guard !updatePending else { return }
        updatePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.updatePending = false
            self?.onUpdate?()
        }
    }

    static func stripANSI(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
