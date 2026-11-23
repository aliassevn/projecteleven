import AppKit
import ApplicationServices

/// Een lopende vergadering zoals de tablet hem te zien krijgt.
struct MeetingInfo: Equatable {
    var app: String          // catalogus-id: zoom, teams, meet, webex
    var name: String
    var pid: pid_t
    var muted: Bool?
    var video: Bool?
    /// "app" = uit de app gelezen, "estimated" = bijgehouden door Cyberpad, "none" = onbekend
    var statusSource: String
    var since: Date
    var actions: [String]

    func json() -> [String: Any] {
        [
            "app": app, "name": name,
            "muted": muted.map { $0 as Any } ?? NSNull(),
            "video": video.map { $0 as Any } ?? NSNull(),
            "statusSource": statusSource,
            "since": Int(since.timeIntervalSince1970 * 1000),
            "actions": actions,
        ]
    }
}

/// Herkent of je in een vergadering zit (Zoom, Teams, Webex, Google Meet in de browser) en bedient die.
///
/// Herkenning: een vergader-app draait én gebruikt de microfoon (macOS 14.2+ per app, anders per apparaat).
/// Meet wordt herkend aan de venstertitel in de browser (vereist Toegankelijkheid).
/// Mute-status: Zoom via menu-titels (vereist Toegankelijkheid); anders houdt Cyberpad het zelf bij.
final class MeetingMonitor {
    static let actionOrder = ["mute", "video", "hand", "share", "leave"]
    static let browsers = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac", "company.thebrowser.Browser",
                           "com.brave.Browser", "org.mozilla.firefox", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]

    private let actions: ActionRunner
    private(set) var current: MeetingInfo?
    private var estimatedMuted: Bool?
    private var estimatedVideo: Bool?
    private let fakeApp = ProcessInfo.processInfo.environment["CYBERPAD_FAKE_MEETING"]

    init(actions: ActionRunner) {
        self.actions = actions
    }

    private var catalog: ShortcutCatalog { actions.catalog }

    // MARK: Herkennen

    /// Werkt `current` bij. Geeft true als er iets veranderd is.
    @discardableResult
    func refresh() -> Bool {
        let before = current
        guard let found = detect() else {
            current = nil
            estimatedMuted = nil
            estimatedVideo = nil
            return before != nil
        }

        let sameMeeting = before?.app == found.app.id && before?.pid == found.pid
        if !sameMeeting { estimatedMuted = nil; estimatedVideo = nil }

        var info = MeetingInfo(app: found.app.id, name: found.app.name, pid: found.pid,
                               muted: nil, video: nil, statusSource: "none",
                               since: sameMeeting ? before!.since : Date(),
                               actions: Self.actionOrder.filter { catalog.find("\(found.app.id).\($0)") != nil })

        if let patterns = found.app.status, AXIsProcessTrusted(), fakeApp == nil,
           let s = menuStatus(pid: found.pid, patterns: patterns), s.muted != nil || s.video != nil {
            info.muted = s.muted
            info.video = s.video
            info.statusSource = "app"
        } else if estimatedMuted != nil || estimatedVideo != nil {
            info.muted = estimatedMuted
            info.video = estimatedVideo
            info.statusSource = "estimated"
        }
        current = info
        return info != before
    }

    private struct Found {
        let app: ShortcutCatalog.App
        let pid: pid_t
    }

    private func detect() -> Found? {
        let meetingApps = catalog.apps.filter { $0.meeting == true }
        if let fake = fakeApp, let a = catalog.app(fake) {
            return Found(app: a, pid: ProcessInfo.processInfo.processIdentifier) // alleen om te testen
        }

        let users = actions.audio.micUsers()
        let micBusy = users.map { !$0.isEmpty } ?? actions.audio.micInUse
        guard micBusy else { return nil }

        func usesMic(_ app: NSRunningApplication) -> Bool {
            guard let users else { return true } // ouder macOS: alleen "er wordt ergens opgenomen"
            let bid = app.bundleIdentifier ?? ""
            return users.contains { u in
                u.pid == app.processIdentifier
                    || (!bid.isEmpty && u.bundleID.hasPrefix(bid))
                    || (bid == "com.apple.Safari" && u.bundleID.hasPrefix("com.apple.WebKit"))
            }
        }

        let running = NSWorkspace.shared.runningApplications
        var candidates: [(ShortcutCatalog.App, NSRunningApplication)] = []
        for a in meetingApps where !a.bundleIds.isEmpty {
            for r in running where a.bundleIds.contains(r.bundleIdentifier ?? "") && usesMic(r) {
                candidates.append((a, r))
            }
        }
        if let meet = catalog.app("meet"), AXIsProcessTrusted() {
            for r in running where Self.browsers.contains(r.bundleIdentifier ?? "") && usesMic(r) {
                if meetWindow(pid: r.processIdentifier) != nil { candidates.append((meet, r)) }
            }
        }

        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let pick = candidates.first(where: { $0.1.processIdentifier == front }) ?? candidates.first else { return nil }
        return Found(app: pick.0, pid: pick.1.processIdentifier)
    }

    // MARK: Bedienen

    func perform(_ action: String) throws {
        guard let m = current else { throw ActionRunner.ActionError.failed("Er loopt geen vergadering") }
        guard m.actions.contains(action), let (app, sc) = catalog.find("\(m.app).\(action)") else {
            throw ActionRunner.ActionError.failed("Niet beschikbaar voor \(m.name)")
        }
        let combo = try Keys.parse(sc.keys)
        if fakeApp == nil { try actions.ensureAccessibility() }

        if fakeApp != nil {
            NSLog("Cyberpad (test): zou %@ sturen naar %@", sc.keys, app.name)
        } else if app.id == "meet" {
            // Juiste browservenster vooraan zetten, anders gaat ⌘D naar een andere app (in Finder = dupliceren!).
            guard let win = meetWindow(pid: m.pid),
                  let browser = NSRunningApplication(processIdentifier: m.pid) else {
                throw ActionRunner.ActionError.failed("Meet-venster niet gevonden")
            }
            browser.activate()
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { Keys.press(combo) }
        } else {
            try actions.run(ActionSpec(type: "preset", preset: "\(m.app).\(action)"))
        }

        if current?.statusSource != "app" {
            if action == "mute" { estimatedMuted = !(estimatedMuted ?? false) }
            if action == "video" { estimatedVideo = !(estimatedVideo ?? true) }
        }
        refresh()
    }

    // MARK: Toegankelijkheid (AX)

    private func meetWindow(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        for w in Self.elements(app, kAXWindowsAttribute) {
            guard let title = Self.string(w, kAXTitleAttribute) else { continue }
            if title.hasPrefix("Meet - ") || title.hasPrefix("Meet – ") || title.contains("meet.google.com") { return w }
        }
        return nil
    }

    /// Leest de menubalk van de app en zoekt menu-items als "Mute audio" / "Unmute audio".
    private func menuStatus(pid: pid_t, patterns p: ShortcutCatalog.StatusPatterns) -> (muted: Bool?, video: Bool?)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let bar = Self.element(app, kAXMenuBarAttribute) else { return nil }

        func norm(_ list: [String]?) -> Set<String> { Set((list ?? []).map { $0.lowercased() }) }
        let mutedWhen = norm(p.mutedWhen), unmutedWhen = norm(p.unmutedWhen)
        let videoOn = norm(p.videoOnWhen), videoOff = norm(p.videoOffWhen)

        var muted: Bool?, video: Bool?
        for top in Self.elements(bar, kAXChildrenAttribute) {
            for menu in Self.elements(top, kAXChildrenAttribute) {
                for item in Self.elements(menu, kAXChildrenAttribute) {
                    guard let t = Self.string(item, kAXTitleAttribute)?.trimmingCharacters(in: .whitespaces).lowercased(),
                          !t.isEmpty else { continue }
                    if mutedWhen.contains(t) { muted = true }
                    if unmutedWhen.contains(t) { muted = false }
                    if videoOn.contains(t) { video = true }
                    if videoOff.contains(t) { video = false }
                }
            }
        }
        return (muted, video)
    }

    private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }
}
