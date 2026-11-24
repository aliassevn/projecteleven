import AppKit

/// Bepaalt per tablet welk profiel geldt en welke contextpagina bij de actieve app hoort.
///
/// Profiel per tablet, in deze volgorde:
/// 1. vast profiel van die tablet (menu › Gekoppelde tablets)
/// 2. handmatig gekozen profiel (menu, of `cyberpad://profile/<id>` vanuit Opdrachten/Focus)
/// 3. eerste profiel waarvan een tijdregel nu past
/// 4. profiel met `"default": true`, anders het eerste; zonder profielen: alle pagina's
final class ContextEngine: ObservableObject {
    struct App: Equatable {
        var bundleID: String
        var name: String
    }

    @Published private(set) var frontApp: App?
    /// Handmatig gekozen profiel (nil = automatisch).
    @Published private(set) var override: String?
    @Published private(set) var autoProfile: Profile?

    private var layout: Layout
    private var observer: NSObjectProtocol?
    private let defaultsKey = "profileOverride"

    /// Contextpagina veranderd → status uitsturen.
    var onContextChange: (() -> Void)?
    /// Profiel (voor een of meer tablets) veranderd → layout opnieuw uitsturen.
    var onProfileChange: (() -> Void)?

    init(layout: Layout) {
        self.layout = layout
        override = UserDefaults.standard.string(forKey: defaultsKey)
        autoProfile = Self.timeProfile(layout, Date())
        if let a = NSWorkspace.shared.frontmostApplication { frontApp = Self.app(a) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.activated(a)
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    private static func app(_ a: NSRunningApplication) -> App? {
        guard let id = a.bundleIdentifier else { return nil }
        return App(bundleID: id, name: a.localizedName ?? id)
    }

    private func activated(_ a: NSRunningApplication) {
        // Cyberpad zelf (menu openen) telt niet mee.
        guard a.bundleIdentifier != Bundle.main.bundleIdentifier, let app = Self.app(a), app != frontApp else { return }
        let before = contextPage
        frontApp = app
        if contextPage != before { onContextChange?() }
    }

    func update(_ l: Layout) {
        layout = l
        if let o = override, !(l.profiles ?? []).contains(where: { $0.id == o }) { setOverride(nil) }
        autoProfile = Self.timeProfile(l, Date())
    }

    /// Elke minuut (of vaker): tijdprofiel opnieuw bepalen.
    func tick() {
        let p = Self.timeProfile(layout, Date())
        if p != autoProfile {
            autoProfile = p
            onProfileChange?()
        }
    }

    // MARK: Profielen

    var profiles: [Profile] { layout.profiles ?? [] }

    static func timeProfile(_ l: Layout, _ date: Date) -> Profile? {
        let ps = l.profiles ?? []
        if let p = ps.first(where: { ($0.when ?? []).contains { $0.matches(date) } }) { return p }
        return ps.first { $0.default == true } ?? ps.first
    }

    /// nil of "auto" = automatisch. Onbekende profielen worden genegeerd.
    @discardableResult
    func setOverride(_ id: String?) -> Bool {
        let v = (id == "auto" || id?.isEmpty == true) ? nil : id
        if let v, !profiles.contains(where: { $0.id == v }) { return false }
        guard v != override else { return true }
        override = v
        UserDefaults.standard.set(v, forKey: defaultsKey)
        onProfileChange?()
        return true
    }

    func profile(deviceProfile: String?) -> Profile? {
        if let d = deviceProfile, let p = profiles.first(where: { $0.id == d }) { return p }
        if let o = override, let p = profiles.first(where: { $0.id == o }) { return p }
        return autoProfile
    }

    /// De pagina's die een tablet met dit profiel ziet, in de volgorde van het profiel.
    func pages(for profile: Profile?) -> [Page] {
        guard let profile else { return layout.pages }
        let pages = profile.pages.compactMap { id in layout.pages.first { $0.id == id } }
        return pages.isEmpty ? layout.pages : pages
    }

    // MARK: Contextpagina

    /// Id van de pagina die bij de actieve app hoort (of nil).
    var contextPage: String? {
        guard let a = frontApp else { return nil }
        return layout.pages.first { p in
            (p.apps ?? []).contains { $0.caseInsensitiveCompare(a.bundleID) == .orderedSame || $0.caseInsensitiveCompare(a.name) == .orderedSame }
        }?.id
    }

    /// Alleen de pagina-id: welke app je gebruikt gaat niet naar de tablet.
    func json() -> [String: Any] {
        ["page": contextPage ?? NSNull()]
    }

    // MARK: cyberpad://-links (Opdrachten, Focus-automatisering)

    /// cyberpad://profile/werk · cyberpad://profile/auto · cyberpad://profile?id=werk
    func handle(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "cyberpad" else { return nil }
        let host = url.host?.lowercased()
        guard host == "profile" || host == "profiel" else { return "Onbekende Cyberpad-link: \(url.absoluteString)" }
        let id = url.pathComponents.dropFirst().first
            ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "id" }?.value
        guard setOverride(id) else { return L("Onbekend profiel: {0}", id ?? "") }
        return nil
    }
}
