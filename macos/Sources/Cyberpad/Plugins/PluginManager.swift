import Foundation
import Combine

/// Zoekt plugins, houdt bij welke je hebt toegestaan en praat met de draaiende plugins.
/// Een plugin draait pas als jij hem aanzet én een tegel hem gebruikt.
final class PluginManager: ObservableObject {
    enum Status: Equatable {
        case off            // niet toegestaan
        case idle           // toegestaan, draait (nog) niet
        case running
        case changed        // bestanden gewijzigd sinds je hem toestond
        case failed(String)

        var text: String {
            switch self {
            case .off: return L("uit")
            case .idle: return L("aan")
            case .running: return L("actief")
            case .changed: return L("gewijzigd — opnieuw toestaan")
            case .failed(let m): return m
            }
        }
    }

    final class Plugin {
        let manifest: PluginManifest
        let dir: URL
        let builtIn: Bool
        var status: Status = .off
        var process: PluginProcess?
        var crashes: [Date] = []
        var nextStart = Date.distantPast
        init(manifest: PluginManifest, dir: URL, builtIn: Bool) {
            self.manifest = manifest; self.dir = dir; self.builtIn = builtIn
        }
    }

    let userDir: URL
    let builtInDir: URL?
    private let approvalsURL: URL
    private let dataDir: URL

    @Published private(set) var plugins: [String: Plugin] = [:]
    @Published private(set) var problems: [String] = []
    private var approved: [String: String] = [:]
    private var fingerprint = ""
    private var usedPlugins: Set<String> = []
    private var widgetTiles: [Tile] = []
    private var widgetData: [String: [String: Any]] = [:]
    private var widgetBusy: Set<String> = []
    private var lastPoll: [String: Date] = [:]

    var onChange: (() -> Void)?
    var onToast: ((String) -> Void)?

    init(supportDir: URL, builtInDir: URL?) {
        userDir = supportDir.appendingPathComponent("Plugins", isDirectory: true)
        dataDir = supportDir.appendingPathComponent("PluginData", isDirectory: true)
        approvalsURL = supportDir.appendingPathComponent("plugins.json")
        self.builtInDir = builtInDir
        try? FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: approvalsURL),
           let obj = try? JSONDecoder().decode([String: [String: String]].self, from: d) {
            approved = obj["approved"] ?? [:]
        }
    }

    var sorted: [Plugin] { plugins.values.sorted { $0.manifest.name.localizedCompare($1.manifest.name) == .orderedAscending } }

    // MARK: Zoeken

    /// Goedkope controle (namen + wijzigingsdatums); alleen bij verschil opnieuw inlezen.
    func rescanIfChanged() {
        let fp = currentFingerprint()
        if fp != fingerprint { scan() }
    }

    private func pluginDirs() -> [(URL, Bool)] {
        var out: [(URL, Bool)] = []
        for (base, builtIn) in [(builtInDir, true), (Optional(userDir), false)] {
            guard let base, let items = try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for d in items where FileManager.default.fileExists(atPath: d.appendingPathComponent("plugin.json").path) {
                out.append((d, builtIn))
            }
        }
        return out
    }

    private func currentFingerprint() -> String {
        pluginDirs().map { d, _ -> String in
            let m = (try? FileManager.default.attributesOfItem(atPath: d.appendingPathComponent("plugin.json").path))?[.modificationDate] as? Date
            return "\(d.path)@\(m?.timeIntervalSince1970 ?? 0)"
        }.sorted().joined(separator: "|")
    }

    func scan() {
        fingerprint = currentFingerprint()
        var found: [String: Plugin] = [:]
        var errs: [String] = []
        for (dir, builtIn) in pluginDirs() {
            do {
                let m = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: dir.appendingPathComponent("plugin.json")))
                try m.validate()
                if let other = found[m.id], !other.builtIn || builtIn {
                    errs.append(L("{0}: id “{1}” bestaat al", dir.lastPathComponent, m.id))
                    continue
                }
                found[m.id] = Plugin(manifest: m, dir: dir, builtIn: builtIn)
            } catch {
                errs.append("\(dir.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // Lopende processen houden als de plugin hetzelfde bleef; anders stoppen.
        for (id, old) in plugins {
            if let new = found[id], new.manifest == old.manifest, new.dir == old.dir {
                new.process = old.process; new.status = old.status; new.crashes = old.crashes; new.nextStart = old.nextStart
            } else {
                old.process?.stop()
            }
        }
        for p in found.values where p.process == nil { p.status = approved[p.manifest.id] == nil ? .off : .idle }
        plugins = found
        problems = errs
        for e in errs { NSLog("Cyberpad plugin: %@", e) }
        onChange?()
    }

    // MARK: Toestaan

    func isApproved(_ id: String) -> Bool { approved[id] != nil }

    func approve(_ id: String) {
        guard let p = plugins[id] else { return }
        do {
            approved[id] = try PluginHash.of(p.dir)
            p.status = .idle
            p.crashes = []
            p.nextStart = .distantPast
        } catch {
            p.status = .failed(error.localizedDescription)
        }
        saveApprovals()
        objectWillChange.send()
        onChange?()
    }

    func revoke(_ id: String) {
        approved[id] = nil
        if let p = plugins[id] {
            p.process?.stop()
            p.process = nil
            p.status = .off
        }
        saveApprovals()
        objectWillChange.send()
        onChange?()
    }

    private func saveApprovals() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(["approved": approved]) {
            try? d.write(to: approvalsURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: approvalsURL.path)
        }
    }

    // MARK: Layout

    func update(_ layout: Layout) {
        var used = Set<String>()
        func scanAction(_ a: ActionSpec?) {
            guard let a else { return }
            if a.type == "plugin", let p = a.plugin { used.insert(p) }
            a.steps?.forEach(scanAction)
        }
        let tiles = layout.pages.flatMap(\.tiles)
        for t in tiles {
            [t.action, t.longPress, t.doubleTap, t.offAction].forEach(scanAction)
            if t.kind == "plugin", let p = t.config?.plugin { used.insert(p) }
        }
        usedPlugins = used
        widgetTiles = tiles.filter { $0.kind == "plugin" }
        let ids = Set(widgetTiles.map(\.id))
        widgetData = widgetData.filter { ids.contains($0.key) }
        // Plugins die niet meer gebruikt worden stoppen.
        for p in plugins.values where !used.contains(p.manifest.id) && p.process != nil {
            p.process?.stop()
            p.process = nil
            if p.status == .running { p.status = .idle }
        }
    }

    // MARK: Starten

    private func env(for p: Plugin) -> [String: String] {
        let sys = ProcessInfo.processInfo.environment
        let data = dataDir.appendingPathComponent(p.manifest.id, isDirectory: true)
        try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        // Bewust een kleine omgeving: geen geheimen of ontwikkelinstellingen van Cyberpad zelf.
        var env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "PYTHONUNBUFFERED": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "CYBERPAD_PLATFORM": PluginManifest.platform,
            "CYBERPAD_PLUGIN_DIR": p.dir.path,
            "CYBERPAD_DATA_DIR": data.path,
        ]
        for k in ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL"] { env[k] = sys[k] }
        return env
    }

    /// Geeft een draaiende plugin terug, of een duidelijke fout waarom niet.
    private func running(_ id: String) throws -> (Plugin, PluginProcess) {
        guard let p = plugins[id] else { throw PluginError.failed(L("Plugin “{0}” niet gevonden", id)) }
        guard let ok = approved[id] else {
            throw PluginError.failed(L("Plugin “{0}” staat uit (menubalk › Plugins)", p.manifest.name))
        }
        if let proc = p.process, proc.isRunning { return (p, proc) }
        if p.status == .changed { throw PluginError.failed(L("Plugin “{0}” is gewijzigd; sta hem opnieuw toe", p.manifest.name)) }
        if Date() < p.nextStart {
            throw PluginError.failed(L("Plugin “{0}” is gecrasht; nieuwe poging over {1} s", p.manifest.name, Int(p.nextStart.timeIntervalSinceNow.rounded(.up))))
        }
        // Controleren of de bestanden nog dezelfde zijn als toen je de plugin toestond.
        let hash: String
        do { hash = try PluginHash.of(p.dir) } catch { p.status = .failed(error.localizedDescription); throw error }
        guard hash == ok else {
            p.status = .changed
            objectWillChange.send()
            throw PluginError.failed(L("Plugin “{0}” is gewijzigd; sta hem opnieuw toe (menubalk › Plugins)", p.manifest.name))
        }
        guard let cmd = p.manifest.command else { throw PluginError.failed(L("Geen opdracht voor macOS")) }
        let proc: PluginProcess
        do {
            proc = try PluginProcess(command: cmd, dir: p.dir, env: env(for: p))
        } catch {
            p.status = .failed(L("Start mislukt: {0}", error.localizedDescription))
            objectWillChange.send()
            throw PluginError.failed(L("Plugin “{0}” start niet: {1}", p.manifest.name, error.localizedDescription))
        }
        let pid = id
        proc.onMessage = { [weak self] m in self?.message(from: pid, m) }
        proc.onExit = { [weak self, weak proc] code, err in
            guard let self, let p = self.plugins[pid], p.process === proc else { return }
            self.crashed(p, code: code, stderr: err)
        }
        p.process = proc
        p.status = .running
        proc.send(["type": "hello", "version": 1, "host": "Cyberpad", "platform": PluginManifest.platform,
                   "dataDir": env(for: p)["CYBERPAD_DATA_DIR"] ?? ""])
        objectWillChange.send()
        return (p, proc)
    }

    private func crashed(_ p: Plugin, code: Int32, stderr: String) {
        p.process = nil
        let now = Date()
        p.crashes = p.crashes.filter { now.timeIntervalSince($0) < 120 } + [now]
        let delay = min(pow(2, Double(p.crashes.count)), 60)
        p.nextStart = now.addingTimeInterval(delay)
        let last = stderr.split(separator: "\n").last.map(String.init) ?? ""
        p.status = .failed("gestopt (code \(code))\(last.isEmpty ? "" : ": \(last.prefix(160))")")
        NSLog("Cyberpad plugin %@ gestopt (code %d): %@", p.manifest.id, code, stderr)
        for t in widgetTiles where t.config?.plugin == p.manifest.id { widgetBusy.remove(t.id) }
        objectWillChange.send()
        onChange?()
    }

    // MARK: Berichten van een plugin

    private func message(from id: String, _ m: [String: Any]) {
        switch m["type"] as? String {
        case "toast":
            if let t = m["text"] as? String, !t.isEmpty {
                let name = plugins[id]?.manifest.name ?? id
                onToast?("\(name): \(t.prefix(200))")
            }
        case "update":
            // Widget-gegevens die de plugin uit zichzelf stuurt (bijv. bij een gebeurtenis).
            guard let tile = m["tile"] as? String,
                  widgetTiles.contains(where: { $0.id == tile && $0.config?.plugin == id }),
                  let data = m["data"] as? [String: Any] else { return }
            widgetData[tile] = Self.sanitize(data)
            onChange?()
        case "log":
            if let t = m["text"] as? String { NSLog("Cyberpad plugin %@: %@", id, String(t.prefix(500))) }
        default:
            break
        }
    }

    // MARK: Acties

    func invoke(_ a: ActionSpec, tile: Tile?, gesture: String, onFail: (() -> Void)?) throws {
        guard let id = a.plugin else { throw ActionRunner.ActionError.missing("plugin") }
        guard let action = a.action else { throw ActionRunner.ActionError.missing(L("action (naam van de plugin-actie)")) }
        guard let p = plugins[id] else { throw ActionRunner.ActionError.failed(L("Plugin “{0}” niet gevonden", id)) }
        guard p.manifest.actions?.contains(where: { $0.id == action }) == true else {
            throw ActionRunner.ActionError.failed(L("Plugin “{0}” kent geen actie “{1}”", p.manifest.name, action))
        }
        let (_, proc) = try running(id)
        let def = p.manifest.actions?.first { $0.id == action }
        var msg: [String: Any] = ["type": "invoke", "action": action,
                                  "params": Self.params(def?.params, (a.params ?? [:])), "gesture": gesture]
        if let tile { msg["tile"] = tile.id }
        proc.request(msg) { [weak self] ok, r in
            guard !ok else { return }
            onFail?()
            self?.onToast?("\(p.manifest.name): \(r["error"] as? String ?? "actie mislukt")")
        }
    }

    /// Standaardwaarden uit plugin.json aangevuld met wat in de layout staat.
    private static func params(_ defs: [PluginManifest.Param]?, _ given: [String: JSONValue]) -> [String: Any] {
        var out: [String: Any] = [:]
        for d in defs ?? [] { if let v = d.default { out[d.id] = v.any } }
        for (k, v) in given { out[k] = v.any }
        return out
    }

    // MARK: Widgets

    /// Elke seconde vanuit WidgetHub (alleen als er een tablet verbonden is).
    func pollWidgets() {
        let now = Date()
        for t in widgetTiles {
            guard let id = t.config?.plugin, let wid = t.config?.widget, let p = plugins[id], approved[id] != nil,
                  let def = p.manifest.widgets?.first(where: { $0.id == wid }) else { continue }
            let interval = TimeInterval(min(max(def.interval ?? 10, 1), 3600))
            if widgetBusy.contains(t.id) { continue }
            if let last = lastPoll[t.id], now.timeIntervalSince(last) < interval { continue }
            if now < p.nextStart || p.status == .changed { continue }
            lastPoll[t.id] = now
            requestWidget(t, p, def)
        }
    }

    private func requestWidget(_ t: Tile, _ p: Plugin, _ def: PluginManifest.WidgetDef) {
        guard let (_, proc) = try? running(p.manifest.id) else { onChange?(); return }
        widgetBusy.insert(t.id)
        let msg: [String: Any] = ["type": "widget", "widget": def.id, "tile": t.id,
                                  "params": Self.params(def.params, t.config?.params ?? [:])]
        proc.request(msg) { [weak self] ok, r in
            guard let self else { return }
            self.widgetBusy.remove(t.id)
            if ok, let data = r["data"] as? [String: Any] {
                self.widgetData[t.id] = Self.sanitize(data)
            } else if !ok {
                self.widgetData[t.id] = ["error": String((r["error"] as? String ?? L("geen gegevens")).prefix(200))]
            }
            self.onChange?()
        }
    }

    func widgetAction(_ tile: Tile, action: String, value: Double?) throws {
        guard let id = tile.config?.plugin, let wid = tile.config?.widget else { throw ActionRunner.ActionError.missing("config.plugin / config.widget") }
        guard action.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else {
            throw ActionRunner.ActionError.failed(L("Ongeldige actie"))
        }
        let (p, proc) = try running(id)
        let def = p.manifest.widgets?.first { $0.id == wid }
        var msg: [String: Any] = ["type": "widgetAction", "widget": wid, "tile": tile.id, "action": action,
                                  "params": Self.params(def?.params, tile.config?.params ?? [:])]
        if let value, value.isFinite { msg["value"] = value }
        proc.request(msg) { [weak self] ok, r in
            guard let self else { return }
            if ok, let data = r["data"] as? [String: Any] {
                self.widgetData[tile.id] = Self.sanitize(data)
                self.onChange?()
            } else if !ok {
                self.onToast?("\(p.manifest.name): \(r["error"] as? String ?? "mislukt")")
            }
            self.lastPoll[tile.id] = nil // meteen verversen
        }
    }

    func widgetJSON(_ tile: Tile) -> [String: Any] {
        guard let id = tile.config?.plugin, let wid = tile.config?.widget else {
            return ["status": "error", "error": L("Stel config.plugin en config.widget in")]
        }
        guard let p = plugins[id] else { return ["status": "error", "error": L("Plugin “{0}” niet gevonden", id)] }
        guard p.manifest.widgets?.contains(where: { $0.id == wid }) == true else {
            return ["status": "error", "error": L("Plugin “{0}” heeft geen widget “{1}”", p.manifest.name, wid)]
        }
        guard approved[id] != nil else { return ["status": "off", "error": L("Plugin staat uit (menubalk › Plugins)")] }
        switch p.status {
        case .changed: return ["status": "error", "error": L("Plugin gewijzigd — opnieuw toestaan")]
        case .failed(let m) where p.process == nil: return ["status": "error", "error": m]
        default: break
        }
        var d = widgetData[tile.id] ?? ["status": "waiting"]
        if d["status"] == nil { d["status"] = d["error"] == nil ? "ok" : "error" }
        return d
    }

    /// Alleen bekende velden, met grenzen; de tablet tekent er een standaardtegel van.
    static func sanitize(_ d: [String: Any]) -> [String: Any] {
        func str(_ v: Any?, _ n: Int = 200) -> String? {
            switch v {
            case let s as String: return String(s.prefix(n))
            case let x as NSNumber: return x.stringValue
            default: return nil
            }
        }
        var out: [String: Any] = [:]
        for k in ["title", "value", "unit", "sub", "icon", "error"] { if let s = str(d[k]) { out[k] = s } }
        if let p = d["progress"] as? NSNumber, p.doubleValue.isFinite { out["progress"] = min(max(p.doubleValue, 0), 1) }
        if let a = d["active"] as? Bool { out["active"] = a }
        if let lines = d["lines"] as? [[String: Any]] {
            out["lines"] = lines.prefix(8).map { ["label": str($0["label"], 40) ?? "", "value": str($0["value"], 80) ?? ""] }
        }
        if let btns = d["buttons"] as? [[String: Any]] {
            out["buttons"] = btns.prefix(4).compactMap { b -> [String: String]? in
                guard let id = str(b["id"], 64), id.range(of: "^[A-Za-z0-9_.-]{1,64}$", options: .regularExpression) != nil else { return nil }
                return ["id": id, "label": str(b["label"], 24) ?? id]
            }
        }
        return out
    }

    func stopAll() {
        for p in plugins.values { p.process?.stop() }
    }
}
