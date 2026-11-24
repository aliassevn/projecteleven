import Foundation

/// Verzamelt de gegevens van alle widget-tegels. De tablet krijgt ze als `state.widgets[tegel-id]`.
final class WidgetHub {
    let weather = WeatherService()
    let nowPlaying = NowPlayingService()
    let stats = SystemStats()
    let timers = TimerService()
    let photos = PhotoService()
    let terminal = TerminalService()

    weak var integrations: Integrations?
    weak var plugins: PluginManager?
    private var tiles: [Tile] = []
    private var tickCount = 0
    /// Wordt aangeroepen als er iets nieuws is (weer binnen, terminaluitvoer…), zodat de server de status uitstuurt.
    var onChange: (() -> Void)? {
        didSet {
            weather.onUpdate = onChange
            nowPlaying.onUpdate = onChange
            terminal.onUpdate = onChange
        }
    }
    var onToast: ((String) -> Void)? {
        didSet { timers.onFinish = onToast }
    }

    func update(_ layout: Layout) {
        tiles = layout.pages.flatMap(\.tiles).filter(\.isWidget)
        timers.sync(tiles)
        for t in tiles where t.kind == "weather" { weather.refresh(t.config) }
    }

    private func has(_ kind: String) -> Bool { tiles.contains { $0.kind == kind } }

    /// Elke seconde. `active` = er is een tablet verbonden; zonder tablet wordt er niets opgevraagd.
    func tick(active: Bool) {
        tickCount += 1
        timers.tick(tiles)
        guard active else { return }
        plugins?.pollWidgets()
        if tickCount % 2 == 0 {
            if has("stats") { stats.sample() }
            if let np = tiles.first(where: { $0.kind == "nowplaying" }) { nowPlaying.refresh(prefer: np.config?.player) }
        }
        if tickCount % 60 == 0 {
            for t in tiles where t.kind == "weather" { weather.refresh(t.config) }
        }
    }

    func state() -> [String: Any] {
        var out: [String: Any] = [:]
        for t in tiles {
            switch t.kind {
            case "weather": out[t.id] = weather.json(for: t.config)
            case "nowplaying": out[t.id] = nowPlaying.current
            case "stats":
                if let show = t.config?.show { out[t.id] = stats.current.filter { show.contains($0.key) } } else { out[t.id] = stats.current }
            case "timer", "pomodoro": out[t.id] = timers.json(t.id)
            case "photos": out[t.id] = photos.json(for: t.config)
            case "terminal": out[t.id] = terminal.json(t.id, cfg: t.config)
            case "worldclock": out[t.id] = ["zones": Self.zones(t.config)]
            case "ha": out[t.id] = integrations?.ha.entityJSON(t.config?.entity) ?? [:]
            case "mqtt": out[t.id] = integrations?.mqttJSON(t.config) ?? [:]
            case "plugin": out[t.id] = plugins?.widgetJSON(t) ?? [:]
            default: break
            }
        }
        return out
    }

    /// Acties vanaf de tablet. Alleen vaste acties per soort tegel.
    func handle(_ tile: Tile, action: String, value: Double?) throws {
        switch tile.kind {
        case "timer", "pomodoro":
            try timers.handle(tile, action: action)
        case "nowplaying":
            try nowPlaying.control(action, value: value)
        case "terminal":
            try terminal.handle(tile, action: action, confirmed: value == 1)
        case "ha":
            guard let i = integrations, let e = tile.config?.entity else { throw ActionRunner.ActionError.missing("config.entity") }
            switch action {
            case "toggle": try i.ha.perform(ActionSpec(type: "ha.toggle", entity: e), onFail: nil)
            case "up": try i.ha.stepClimate(e, by: 1)
            case "down": try i.ha.stepClimate(e, by: -1)
            default: throw ActionRunner.ActionError.failed(L("Onbekende actie"))
            }
        case "plugin":
            guard let pm = plugins else { throw ActionRunner.ActionError.failed(L("Plugins niet beschikbaar")) }
            do { try pm.widgetAction(tile, action: action, value: value) } catch let e as PluginError {
                throw ActionRunner.ActionError.failed(e.localizedDescription)
            }
        case "weather":
            guard action == "refresh" else { throw ActionRunner.ActionError.failed(L("Onbekende actie")) }
            weather.refresh(tile.config)
        default:
            throw ActionRunner.ActionError.failed(L("Deze tegel heeft geen acties"))
        }
        onChange?()
    }

    // MARK: Wereldklok

    /// Tijdverschil per zone; de tablet rekent zelf de tijd uit (oude Safari kent geen tijdzones).
    static func zones(_ cfg: WidgetConfig?) -> [[String: Any]] {
        let ids = cfg?.zones ?? ["America/New_York", "Asia/Tokyo"]
        return ids.prefix(4).compactMap { id -> [String: Any]? in
            guard let tz = TimeZone(identifier: id) else { return ["label": id, "error": "onbekende zone"] }
            let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
            return ["label": city, "offset": tz.secondsFromGMT(), "abbr": tz.abbreviation() ?? ""]
        }
    }
}
