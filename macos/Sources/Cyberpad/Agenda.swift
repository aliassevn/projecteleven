import AppKit
import EventKit

/// Volgende afspraak uit Agenda (EventKit), met vergaderlink als die erin staat.
final class AgendaProvider {
    struct Item: Equatable {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var link: URL?
        var linkApp: String?  // zoom, teams, meet, webex, facetime, whereby
    }

    enum Access: String { case granted, notDetermined, denied }

    private var store = EKEventStore()
    private(set) var access: Access = .notDetermined
    private(set) var next: Item?
    private var lastRefresh = Date.distantPast
    var onChange: (() -> Void)?

    init() {
        access = Self.currentAccess()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(force: true)
        }
    }

    static func currentAccess() -> Access {
        let s = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            switch s {
            case .fullAccess: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        } else {
            switch s {
            case .authorized: return .granted
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        }
    }

    /// Vraagt toegang (toont de macOS-melding). Bij "geweigerd" opent het de instellingen.
    func requestAccess() {
        if fake { return }
        switch Self.currentAccess() {
        case .granted:
            access = .granted
            refresh(force: true)
        case .denied:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        case .notDetermined:
            let done: (Bool, Error?) -> Void = { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.store = EKEventStore() // nieuwe store ziet de net gegeven toegang
                    self.access = Self.currentAccess()
                    self.refresh(force: true)
                    self.onChange?()
                }
            }
            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents(completion: done)
            } else {
                store.requestAccess(to: .event, completion: done)
            }
        }
    }

    /// Ververst hoogstens eens per 30 s, tenzij `force`.
    /// Alleen om te testen: CYBERPAD_FAKE_AGENDA=1 toont een nep-afspraak over 3 minuten (opent een voorbeeldlink).
    private let fake = ProcessInfo.processInfo.environment["CYBERPAD_FAKE_AGENDA"] != nil
    private lazy var fakeItem = Item(id: "fake", title: "Weekstart Project Eleven", start: Date().addingTimeInterval(180),
                                     end: Date().addingTimeInterval(1980), link: URL(string: "https://example.com/"), linkApp: "zoom")

    func refresh(force: Bool = false) {
        guard force || Date().timeIntervalSince(lastRefresh) > 30 else { return }
        lastRefresh = Date()
        if fake { access = .granted; if next != fakeItem { next = fakeItem; onChange?() }; return }
        access = Self.currentAccess()
        guard access == .granted else {
            if next != nil { next = nil; onChange?() }
            return
        }

        let now = Date()
        let pred = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600),
                                            end: now.addingTimeInterval(24 * 3600), calendars: nil)
        let events = store.events(matching: pred)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled && !Self.declinedByMe($0) }
            .sorted { $0.startDate < $1.startDate }

        let item = events.first.map { e -> Item in
            let link = Self.meetingLink(e)
            return Item(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "(zonder titel)",
                        start: e.startDate, end: e.endDate, link: link?.url, linkApp: link?.app)
        }
        if item != next { next = item; onChange?() }
    }

    func json() -> [String: Any] {
        guard access == .granted else { return ["status": access == .denied ? "denied" : "noAccess"] }
        guard let n = next else { return ["status": "none"] }
        var d: [String: Any] = [
            "status": "ok", "title": n.title,
            "start": Int(n.start.timeIntervalSince1970 * 1000),
            "end": Int(n.end.timeIntervalSince1970 * 1000),
            "hasLink": n.link != nil,
        ]
        if let a = n.linkApp { d["app"] = a }
        return d
    }

    /// Opent de vergaderlink van de volgende afspraak. De tablet stuurt nooit zelf een link.
    func joinNext() throws {
        guard access == .granted else { throw ActionRunner.ActionError.failed("Geef Cyberpad toegang tot Agenda (menubalk)") }
        guard let link = next?.link else { throw ActionRunner.ActionError.failed("Deze afspraak heeft geen vergaderlink") }
        NSWorkspace.shared.open(link)
    }

    // MARK: Hulpjes

    private static func declinedByMe(_ e: EKEvent) -> Bool {
        e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    static let knownHosts: [(suffix: String, app: String)] = [
        ("zoom.us", "zoom"), ("zoomgov.com", "zoom"),
        ("teams.microsoft.com", "teams"), ("teams.live.com", "teams"),
        ("meet.google.com", "meet"),
        ("webex.com", "webex"),
        ("facetime.apple.com", "facetime"),
        ("whereby.com", "whereby"),
    ]

    /// Zoekt een bekende vergaderlink in url, locatie en notities.
    static func meetingLink(_ e: EKEvent) -> (url: URL, app: String)? {
        let texts = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }
        return meetingLink(in: texts)
    }

    static func meetingLink(in texts: [String]) -> (url: URL, app: String)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for m in detector.matches(in: text, range: range) {
                guard let url = m.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host?.lowercased() else { continue }
                if let known = knownHosts.first(where: { host == $0.suffix || host.hasSuffix("." + $0.suffix) }) {
                    return (url, known.app)
                }
            }
        }
        return nil
    }
}
