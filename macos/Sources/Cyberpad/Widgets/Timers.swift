import AppKit

/// Timers en Pomodoro's lopen op de Mac, zodat ze doorlopen als de tablet slaapt en alle tablets gelijk lopen.
final class TimerService {
    struct State {
        var mode: String            // "timer" of "pomodoro"
        var phase: String = "work"  // pomodoro: work / rest
        var duration: TimeInterval  // lengte van de huidige fase
        var remaining: TimeInterval // als gepauzeerd
        var endsAt: Date?           // als hij loopt
        var round: Int = 1
    }

    private var timers: [String: State] = [:]
    var onFinish: ((String) -> Void)?  // melding naar de tablets

    /// Zorgt dat elke timer-/pomodorotegel een status heeft (en past de duur aan als die in de layout veranderde).
    func sync(_ tiles: [Tile]) {
        var keep = Set<String>()
        for t in tiles {
            guard t.kind == "timer" || t.kind == "pomodoro" else { continue }
            keep.insert(t.id)
            let d = Self.duration(t, phase: timers[t.id]?.phase ?? "work")
            if var s = timers[t.id] {
                if s.endsAt == nil, s.remaining == s.duration, s.duration != d { s.duration = d; s.remaining = d; timers[t.id] = s }
            } else {
                timers[t.id] = State(mode: t.kind!, duration: d, remaining: d)
            }
        }
        timers = timers.filter { keep.contains($0.key) }
    }

    static func duration(_ t: Tile, phase: String) -> TimeInterval {
        if t.kind == "pomodoro" {
            let m = phase == "rest" ? (t.config?.rest ?? 5) : (t.config?.work ?? 25)
            return TimeInterval(min(max(m, 1), 180) * 60)
        }
        return TimeInterval(min(max(t.config?.seconds ?? 300, 5), 24 * 3600))
    }

    func json(_ id: String) -> [String: Any] {
        guard let s = timers[id] else { return [:] }
        var d: [String: Any] = ["mode": s.mode, "phase": s.phase, "duration": Int(s.duration),
                                "running": s.endsAt != nil, "round": s.round]
        if let e = s.endsAt { d["endsAt"] = Int(e.timeIntervalSince1970 * 1000) } else { d["remaining"] = Int(s.remaining.rounded()) }
        return d
    }

    /// toggle (start/pauze), reset, add (+1 minuut)
    func handle(_ tile: Tile, action: String) throws {
        guard var s = timers[tile.id] else { throw ActionRunner.ActionError.failed(L("Timer niet gevonden")) }
        switch action {
        case "toggle":
            if let e = s.endsAt {
                s.remaining = max(0, e.timeIntervalSinceNow)
                s.endsAt = nil
            } else {
                if s.remaining <= 0 { s.remaining = s.duration }
                s.endsAt = Date().addingTimeInterval(s.remaining)
            }
        case "reset":
            s = State(mode: s.mode, duration: Self.duration(tile, phase: "work"), remaining: Self.duration(tile, phase: "work"))
        case "add":
            if let e = s.endsAt { s.endsAt = e.addingTimeInterval(60) } else { s.remaining += 60 }
            s.duration += 60
        default:
            throw ActionRunner.ActionError.failed(L("Onbekende timeractie"))
        }
        timers[tile.id] = s
    }

    /// Elke seconde: afgelopen timers afhandelen.
    func tick(_ tiles: [Tile]) {
        for (id, var s) in timers {
            guard let e = s.endsAt, e <= Date() else { continue }
            NSSound(named: "Glass")?.play()
            let label = tiles.first { $0.id == id }?.label ?? "Timer"
            if s.mode == "pomodoro", let tile = tiles.first(where: { $0.id == id }) {
                // Werk → pauze → werk … loopt vanzelf door.
                let next = s.phase == "work" ? "rest" : "work"
                if next == "work" { s.round += 1 }
                s.phase = next
                s.duration = Self.duration(tile, phase: next)
                s.remaining = s.duration
                s.endsAt = Date().addingTimeInterval(s.duration)
                onFinish?(next == "rest" ? L("🍅 {0}: tijd voor pauze", label) : L("🍅 {0}: weer aan de slag (ronde {1})", label, s.round))
            } else {
                s.endsAt = nil
                s.remaining = 0
                onFinish?(L("⏰ {0} is afgelopen", label))
            }
            timers[id] = s
        }
    }
}
