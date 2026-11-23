import AppKit
import ApplicationServices
import IOKit.pwr_mgt

/// Voert acties uit. Alles wat de tablet kan laten gebeuren staat in deze ene lijst.
final class ActionRunner {
    let audio = AudioController()
    private var keepAwakeID: IOPMAssertionID?
    private var askedForAccessibility = false

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
        ]
        if let v = audio.volume { s["volume"] = (Double(v) * 100).rounded() / 100 }
        if let m = audio.muted { s["muted"] = m }
        return s
    }

    func run(_ a: ActionSpec) throws {
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

        // Systeem
        case "system.darkMode": try toggleDarkMode()
        case "system.lock": try keyCombo(12, [.maskCommand, .maskControl])           // ⌃⌘Q
        case "system.screenshot": try keyCombo(20, [.maskCommand, .maskShift])       // ⇧⌘3
        case "system.screenshotArea": try keyCombo(21, [.maskCommand, .maskShift])   // ⇧⌘4
        case "system.keepAwake": toggleKeepAwake()
        case "system.displayOff": run("/usr/bin/pmset", ["displaysleepnow"])

        default: throw ActionError.unknown(a.type)
        }
    }

    func setSlider(_ a: ActionSpec, value: Double) throws {
        switch a.type {
        case "audio.volume": audio.setVolume(Float32(value))
        default: throw ActionError.unknown(a.type)
        }
    }

    // MARK: Toetsen (vereist Toegankelijkheid)

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func ensureAccessibility() throws {
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
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
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

    private func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }
}
