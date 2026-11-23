import AppKit
import ApplicationServices
import IOKit.pwr_mgt

/// Voert acties uit. Alles wat de tablet kan laten gebeuren staat in deze ene lijst.
final class ActionRunner {
    let audio = AudioController()
    let pointer = PointerController()
    var catalog = ShortcutCatalog.empty
    /// Home Assistant, MQTT en webhooks (fase 7).
    weak var integrations: Integrations?
    /// Plugins (fase 8).
    weak var plugins: PluginManager?
    /// De tegel en het gebaar van de lopende druk (voor plugins).
    private var currentTile: Tile?
    private var currentGesture = "tap"
    /// Fouten die pas later optreden (macro-stappen, Opdrachten) — Core stuurt ze als melding naar de tablets.
    var onAsyncError: ((String) -> Void)?
    /// Stand van aan/uit-knoppen per tegel-id.
    private(set) var toggles: [String: Bool] = [:]

    private var keepAwakeID: IOPMAssertionID?
    /// Lopende Opdrachten vasthouden, anders ruimt Foundation het proces op en komt de afloop nooit binnen.
    private var runningProcesses: [ObjectIdentifier: Process] = [:]
    private var askedForAccessibility = false

    static let maxMacroSteps = 50
    static let maxDelayMs = 10_000

    enum ActionError: LocalizedError {
        case unknown(String), needsAccessibility, missing(String), failed(String)
        var errorDescription: String? {
            switch self {
            case .unknown(let t): return "Onbekende actie: \(t)"
            case .needsAccessibility: return "Geef Cyberpad toegang via Systeeminstellingen › Privacy › Toegankelijkheid"
            case .missing(let w): return "Ontbreekt in layout: \(w)"
            case .failed(let w): return w
            }
        }
    }

    /// Statuswaarden die de tablet toont (aan/uit-knoppen, volumeschuif).
    func state() -> [String: Any] {
        var s: [String: Any] = [
            "micMuted": audio.micMuted,
            "keepAwake": keepAwakeID != nil,
            "darkMode": NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            "toggles": toggles,
        ]
        if let v = audio.volume { s["volume"] = (Double(v) * 100).rounded() / 100 }
        if let m = audio.muted { s["muted"] = m }
        if let v = audio.micVolume { s["micVolume"] = (Double(v) * 100).rounded() / 100 }
        return s
    }

    /// Welke ingebouwde statuswaarde bij een actietype hoort (voor het oplichten van de knop).
    static func stateKey(for type: String?) -> String? {
        switch type {
        case "audio.mute": return "muted"
        case "audio.micMute": return "micMuted"
        case "system.keepAwake": return "keepAwake"
        case "system.darkMode": return "darkMode"
        case "audio.volume": return "volume"
        case "audio.micVolume": return "micVolume"
        default: return nil
        }
    }

    // MARK: Uitvoeren

    /// Een tegel indrukken. Bij een aan/uit-knop wisselt de stand en wordt bij "uit" `offAction` gebruikt.
    func press(_ tile: Tile, gesture: String) throws {
        currentTile = tile
        currentGesture = gesture
        defer { currentTile = nil; currentGesture = "tap" }
        let action: ActionSpec?
        switch gesture {
        case "long": action = tile.longPress
        case "double": action = tile.doubleTap
        default:
            if tile.toggle == true {
                // Met een status-topic geldt de echte stand van het apparaat, niet wat Cyberpad onthield.
                let current: Bool
                if let topic = tile.config?.topic, let v = integrations?.mqtt.values[topic] {
                    current = Integrations.truthy(v)
                } else {
                    current = toggles[tile.id] ?? false
                }
                let on = !current
                action = on ? tile.action : (tile.offAction ?? tile.action)
                guard let action else { throw ActionError.missing("action") }
                toggles[tile.id] = on
                do {
                    try run(action) { [weak self] in self?.toggles[tile.id] = !on } // mislukt later → terugzetten
                } catch {
                    toggles[tile.id] = !on
                    throw error
                }
                return
            }
            action = tile.action
        }
        guard let action else { throw ActionError.missing(gesture == "long" ? "longPress" : gesture == "double" ? "doubleTap" : "action") }
        try run(action)
    }

    /// `onLateFailure` wordt aangeroepen als een actie pas na afloop mislukt (Opdrachten, macro-stappen).
    func run(_ a: ActionSpec, onLateFailure: (() -> Void)? = nil) throws {
        switch a.type {
        // Media
        case "media.playPause": try mediaKey(16)
        case "media.next": try mediaKey(17)
        case "media.previous": try mediaKey(18)

        // Audio
        case "audio.volumeUp": audio.changeVolume(by: 1 / 16)
        case "audio.volumeDown": audio.changeVolume(by: -1 / 16)
        case "audio.mute": audio.toggleMute()
        case "audio.micMute": audio.toggleMic()

        // Apps en links
        case "app.open":
            guard let app = a.app else { throw ActionError.missing("app") }
            try openApp(app)
        case "url.open":
            guard let s = a.url, let url = URL(string: s), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                throw ActionError.missing("geldige http(s)-url")
            }
            NSWorkspace.shared.open(url)

        // Toetsen en tekst
        case "keys.press":
            guard let k = a.keys else { throw ActionError.missing("keys") }
            let combo = try Keys.parse(k)
            try ensureAccessibility()
            Keys.press(combo)
        case "text.type":
            guard let t = a.text, !t.isEmpty else { throw ActionError.missing("text") }
            try ensureAccessibility()
            Keys.type(t)
        case "preset":
            guard let p = a.preset else { throw ActionError.missing("preset") }
            try runPreset(p)

        // Opdrachten-app (Shortcuts)
        case "shortcut.run":
            guard let name = a.shortcut, !name.isEmpty else { throw ActionError.missing("shortcut") }
            runShortcut(name, onFail: onLateFailure)

        // Macro's
        case "macro":
            try runMacro(a.steps ?? [], onFail: onLateFailure)
        case "delay":
            throw ActionError.failed("Een pauze (delay) kan alleen binnen een macro")

        // Systeem
        case "system.darkMode": try toggleDarkMode()
        case "system.lock": try keyCombo(12, [.maskCommand, .maskControl])           // ⌃⌘Q
        case "system.screenshot": try keyCombo(20, [.maskCommand, .maskShift])       // ⇧⌘3
        case "system.screenshotArea": try keyCombo(21, [.maskCommand, .maskShift])   // ⇧⌘4
        case "system.keepAwake": toggleKeepAwake()
        case "system.displayOff": launch("/usr/bin/pmset", ["displaysleepnow"])

        // Smart home en koppelingen
        case "ha.toggle", "ha.service":
            guard let i = integrations else { throw ActionError.failed("Koppelingen niet beschikbaar") }
            try i.ha.perform(a, onFail: onLateFailure)
        case "webhook.call":
            guard let i = integrations else { throw ActionError.failed("Koppelingen niet beschikbaar") }
            try i.webhooks.call(a, onFail: onLateFailure)
        case "mqtt.publish":
            guard let i = integrations else { throw ActionError.failed("Koppelingen niet beschikbaar") }
            guard let topic = a.topic else { throw ActionError.missing("topic") }
            try i.mqtt.publish(topic: topic, payload: a.payload ?? "", retain: a.retain ?? false)

        // Plugins
        case "plugin":
            guard let pm = plugins else { throw ActionError.failed("Plugins niet beschikbaar") }
            do {
                try pm.invoke(a, tile: currentTile, gesture: currentGesture, onFail: onLateFailure)
            } catch let e as PluginError {
                throw ActionError.failed(e.localizedDescription)
            }

        default: throw ActionError.unknown(a.type)
        }
    }

    /// Draaiknop: `steps` tikken (positief = met de klok mee).
    /// Volume, mic-volume en ha.level veranderen relatief; `pointer.scroll` scrollt;
    /// anders: `action` met de klok mee en `offAction` tegen de klok in (max. 10 keer per bericht).
    func dial(_ tile: Tile, steps: Int) throws {
        guard let a = tile.action else { throw ActionError.missing("action") }
        let n = max(min(steps, 20), -20)
        guard n != 0 else { return }
        let step = min(max(tile.config?.step ?? 0.03, 0.005), 0.5)
        switch a.type {
        case "audio.volume":
            audio.changeVolume(by: Float32(Double(n) * step))
        case "audio.micVolume":
            audio.setMicVolume(min(max((audio.micVolume ?? 0) + Float32(Double(n) * step), 0), 1))
        case "ha.level":
            guard let e = a.entity, let i = integrations else { throw ActionError.missing("entity") }
            let cur = i.ha.entityJSON(e)["level"] as? Double ?? 0
            try i.ha.setLevel(e, min(max(cur + Double(n) * step, 0), 1))
        case "pointer.scroll":
            try ensureAccessibility()
            pointer.scroll(dx: 0, dy: Double(n) * 40 * (tile.config?.speed ?? 1), natural: tile.config?.natural ?? true)
        default:
            let act: ActionSpec
            if n > 0 { act = a } else {
                guard let off = tile.offAction else { throw ActionError.missing("offAction (tegen de klok in)") }
                act = off
            }
            for _ in 0..<min(abs(n), 10) { try run(act) }
        }
    }

    func setSlider(_ a: ActionSpec, value: Double) throws {
        switch a.type {
        case "audio.volume": audio.setVolume(Float32(value))
        case "audio.micVolume": audio.setMicVolume(Float32(value))
        case "ha.level":
            guard let e = a.entity else { throw ActionError.missing("entity") }
            guard let i = integrations else { throw ActionError.failed("Koppelingen niet beschikbaar") }
            try i.ha.setLevel(e, value)
        default: throw ActionError.unknown(a.type)
        }
    }

    // MARK: Shortcut-bibliotheek

    private func runPreset(_ id: String) throws {
        guard let (app, sc) = catalog.find(id) else { throw ActionError.failed("Onbekende sneltoets uit de bibliotheek: \(id)") }
        let combo = try Keys.parse(sc.keys)
        try ensureAccessibility()

        guard app.activate, !app.bundleIds.isEmpty else { Keys.press(combo); return }
        guard let running = NSWorkspace.shared.runningApplications.first(where: { app.bundleIds.contains($0.bundleIdentifier ?? "") }) else {
            throw ActionError.failed("\(app.name) draait niet")
        }
        if running.isActive {
            Keys.press(combo)
        } else {
            running.activate()
            // Even wachten tot de app vooraan staat, anders gaat de toets naar de vorige app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { Keys.press(combo) }
        }
    }

    // MARK: Macro's

    /// Controleert de hele macro vooraf en voert daarna de stappen na elkaar uit (pauzes zonder te blokkeren).
    private func runMacro(_ steps: [ActionSpec], onFail: (() -> Void)?) throws {
        guard !steps.isEmpty else { throw ActionError.missing("steps") }
        guard steps.count <= Self.maxMacroSteps else { throw ActionError.failed("Een macro mag maximaal \(Self.maxMacroSteps) stappen hebben") }
        if steps.contains(where: { $0.type == "macro" }) { throw ActionError.failed("Een macro kan geen andere macro bevatten") }
        for s in steps where s.type == "keys.press" { _ = try Keys.parse(s.keys ?? "") }
        if steps.contains(where: { ["keys.press", "text.type", "preset"].contains($0.type) }) { try ensureAccessibility() }
        runSteps(steps[...], onFail: onFail)
    }

    private func runSteps(_ steps: ArraySlice<ActionSpec>, onFail: (() -> Void)?) {
        guard let step = steps.first else { return }
        let rest = steps.dropFirst()
        if step.type == "delay" {
            let ms = min(max(step.ms ?? 0, 0), Self.maxDelayMs)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in self?.runSteps(rest, onFail: onFail) }
            return
        }
        do {
            try run(step, onLateFailure: onFail)
        } catch {
            onFail?()
            onAsyncError?("Macro gestopt: \(error.localizedDescription)")
            return
        }
        // Korte adempauze tussen stappen zodat apps de toetsen bijhouden.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) { [weak self] in self?.runSteps(rest, onFail: onFail) }
    }

    // MARK: Opdrachten-app

    private func runShortcut(_ name: String, onFail: (() -> Void)?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        p.arguments = ["run", name]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice // anders wacht `shortcuts` op invoer
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "Error: ", with: "") ?? ""
            DispatchQueue.main.async {
                self?.runningProcesses[ObjectIdentifier(proc)] = nil
                guard status != 0 else { return }
                onFail?()
                self?.onAsyncError?("Opdracht “\(name)” mislukt\(msg.isEmpty ? "" : ": \(msg)")")
            }
        }
        do {
            try p.run()
            runningProcesses[ObjectIdentifier(p)] = p
        } catch {
            onFail?()
            onAsyncError?("Opdrachten-app niet gevonden")
        }
    }

    // MARK: Toetsen (vereist Toegankelijkheid)

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func ensureAccessibility() throws {
        guard AXIsProcessTrusted() else {
            if !askedForAccessibility { askedForAccessibility = true; requestAccessibility() }
            throw ActionError.needsAccessibility
        }
    }

    private func mediaKey(_ key: Int) throws {
        try ensureAccessibility()
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private func keyCombo(_ key: CGKeyCode, _ flags: CGEventFlags) throws {
        try ensureAccessibility()
        Keys.press(.init(code: key, flags: flags))
    }

    // MARK: Overig

    private func openApp(_ app: String) throws {
        let ws = NSWorkspace.shared
        var url = ws.urlForApplication(withBundleIdentifier: app)
        if url == nil {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "\(home)/Applications"]
            url = dirs.map { URL(fileURLWithPath: $0).appendingPathComponent("\(app).app") }
                .first { FileManager.default.fileExists(atPath: $0.path) }
        }
        guard let url else { throw ActionError.failed("App niet gevonden: \(app)") }
        ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func toggleDarkMode() throws {
        let src = "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "onbekende fout"
            throw ActionError.failed("Dark mode lukt niet (sta Automatisering › System Events toe): \(msg)")
        }
    }

    private func toggleKeepAwake() {
        if let id = keepAwakeID {
            IOPMAssertionRelease(id)
            keepAwakeID = nil
        } else {
            var id = IOPMAssertionID(0)
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Cyberpad: wakker houden" as CFString, &id)
            if r == kIOReturnSuccess { keepAwakeID = id }
        }
    }

    private func launch(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }
}
