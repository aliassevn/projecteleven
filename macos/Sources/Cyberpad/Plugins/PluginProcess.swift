import Foundation

/// Eén draaiende plugin. Berichten zijn JSON, één per regel, via stdin/stdout. stderr is alleen voor logging.
final class PluginProcess {
    private let process = Process()
    private let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    private var buffer = Data()
    private(set) var stderrTail = ""
    private var pending: [Int: (Bool, [String: Any]) -> Void] = [:]
    private var nextID = 1
    private var exited = false

    var onMessage: (([String: Any]) -> Void)?
    var onExit: ((Int32, String) -> Void)?

    static let maxLine = 256 << 10

    init(command: [String], dir: URL, env: [String: String]) throws {
        guard let first = command.first else { throw PluginError.failed(L("Geen opdracht")) }
        if first.contains("/") {
            let exe = first.hasPrefix("/") ? URL(fileURLWithPath: first) : dir.appendingPathComponent(first).standardizedFileURL
            process.executableURL = exe
            process.arguments = Array(command.dropFirst())
        } else {
            // Naam zonder pad (python3, node…): opzoeken in PATH.
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        process.currentDirectoryURL = dir
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            DispatchQueue.main.async { self?.received(d) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.stderrTail = String((self.stderrTail + s).suffix(2000))
            }
        }
        process.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            DispatchQueue.main.async { self?.finished(code) }
        }
        try process.run()
    }

    var isRunning: Bool { !exited && process.isRunning }

    func send(_ msg: [String: Any]) {
        guard !exited, var data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        data.append(0x0A)
        // write(contentsOf:) gooit een Swift-fout als de plugin weg is (geen crash van Cyberpad).
        do { try stdinPipe.fileHandleForWriting.write(contentsOf: data) } catch { stop() }
    }

    /// Bericht met een `id`; het antwoord (`{"type":"result","id":…}`) gaat naar `done`.
    func request(_ msg: [String: Any], timeout: TimeInterval = 10, done: @escaping (Bool, [String: Any]) -> Void) {
        let id = nextID
        nextID += 1
        var m = msg
        m["id"] = id
        pending[id] = done
        send(m)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let cb = self?.pending.removeValue(forKey: id) else { return }
            cb(false, ["error": L("Plugin antwoordt niet (na {0} s)", Int(timeout))])
        }
    }

    func stop() {
        guard !exited else { return }
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let p = process
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if p.isRunning { kill(p.processIdentifier, SIGKILL) } }
    }

    private func received(_ d: Data) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer = Data(buffer[(nl + 1)...])
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if obj["type"] as? String == "result", let id = (obj["id"] as? NSNumber)?.intValue,
               let cb = pending.removeValue(forKey: id) {
                cb(obj["ok"] as? Bool ?? true, obj)
            } else {
                onMessage?(obj)
            }
        }
        if buffer.count > Self.maxLine {
            stderrTail += "\n" + L("Te lange regel zonder einde; plugin gestopt.")
            buffer = Data()
            stop()
        }
    }

    private func finished(_ code: Int32) {
        guard !exited else { return }
        exited = true
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let waiting = pending
        pending = [:]
        for cb in waiting.values { cb(false, ["error": L("Plugin is gestopt")]) }
        onExit?(code, stderrTail.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
