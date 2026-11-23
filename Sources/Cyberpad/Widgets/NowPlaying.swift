import AppKit

/// Wat er speelt in Muziek of Spotify, via AppleScript (vraagt eenmalig om Automatisering-toestemming per app).
/// Er wordt alleen gevraagd als de app al draait, zodat Cyberpad nooit zelf Muziek of Spotify opstart.
final class NowPlayingService {
    static let apps: [(id: String, name: String, bundle: String)] = [
        ("spotify", "Spotify", "com.spotify.client"),
        ("music", "Muziek", "com.apple.Music"),
    ]

    private(set) var current: [String: Any] = ["status": "idle"]
    private var busy = false
    private let queue = DispatchQueue(label: "cyberpad.nowplaying")
    var onUpdate: (() -> Void)?

    // Tab-gescheiden zodat titels met komma's geen probleem zijn.
    private static func script(_ appName: String, spotify: Bool) -> String {
        let dur = spotify ? "(duration of t) / 1000" : "duration of t"
        return """
        tell application "\(appName)"
          set pState to player state as string
          if pState is "stopped" then return "stopped"
          set t to current track
          return pState & tab & (name of t) & tab & (artist of t) & tab & (album of t) & tab & (player position as string) & tab & ((\(dur)) as string)
        end tell
        """
    }

    private func runningApps(prefer: String?) -> [(id: String, name: String, bundle: String)] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Self.apps.filter { running.contains($0.bundle) && (prefer == nil || $0.id == prefer) }
    }

    func refresh(prefer: String?) {
        guard !busy else { return }
        let apps = runningApps(prefer: prefer)
        guard !apps.isEmpty else {
            if current["status"] as? String != "idle" { current = ["status": "idle"]; onUpdate?() }
            return
        }
        busy = true
        queue.async {
            var results: [[String: Any]] = []
            for a in apps {
                let r = Self.osascript(Self.script(a.id == "spotify" ? "Spotify" : "Music", spotify: a.id == "spotify"))
                if let err = r.error {
                    results.append(["status": "error", "app": a.id, "appName": a.name,
                                    "error": err.contains("-1743") ? "Sta Automatisering › \(a.name) toe voor Cyberpad" : err])
                    continue
                }
                let parts = r.output.components(separatedBy: "\t")
                guard parts.count >= 6 else { continue } // gestopt
                func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
                results.append([
                    "status": "ok", "app": a.id, "appName": a.name,
                    "state": parts[0], "title": parts[1], "artist": parts[2], "album": parts[3],
                    "position": num(parts[4]), "duration": num(parts[5]),
                    "at": Int(Date().timeIntervalSince1970 * 1000),
                ])
            }
            // Wat speelt gaat voor; anders iets dat gepauzeerd is; anders een eventuele fout.
            let pick = results.first { $0["state"] as? String == "playing" }
                ?? results.first { $0["status"] as? String == "ok" }
                ?? results.first
                ?? ["status": "idle"]
            DispatchQueue.main.async {
                self.busy = false
                self.current = pick
                self.onUpdate?()
            }
        }
    }

    /// playpause, next, prev, seek (seconden)
    func control(_ action: String, value: Double?) throws {
        guard let id = current["app"] as? String, current["status"] as? String == "ok" else {
            throw ActionRunner.ActionError.failed("Er speelt niets in Muziek of Spotify")
        }
        let app = id == "spotify" ? "Spotify" : "Music"
        let cmd: String
        switch action {
        case "playpause": cmd = "playpause"
        case "next": cmd = "next track"
        case "prev": cmd = "previous track"
        case "seek":
            guard let v = value, v.isFinite, v >= 0 else { throw ActionRunner.ActionError.failed("Ongeldige positie") }
            cmd = "set player position to \(Int(v))"
        default: throw ActionRunner.ActionError.failed("Onbekende bediening")
        }
        queue.async { [weak self] in
            _ = Self.osascript("tell application \"\(app)\" to \(cmd)")
            DispatchQueue.main.async {
                self?.busy = false
                self?.refresh(prefer: id)
            }
        }
    }

    private static func osascript(_ source: String) -> (output: String, error: String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return ("", "osascript niet gevonden") }
        let o = out.fileHandleForReading.readDataToEndOfFile()
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let es = String(data: e, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (String(data: o, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                p.terminationStatus == 0 ? nil : (es.isEmpty ? "AppleScript-fout" : es))
    }
}
