import Foundation

/// Home Assistant via de WebSocket-API: live status van gevolgde entiteiten en diensten aanroepen.
/// Alleen entiteiten die in de layout staan worden bewaard en naar de tablet gestuurd.
final class HomeAssistantClient {
    private(set) var status: LinkStatus = .off { didSet { if status != oldValue { onChange?() } } }
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?

    private var baseURL: URL?
    private var token: String?
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var nextID = 1
    private var pending: [Int: (Bool, [String: Any]) -> Void] = [:]
    private(set) var entities: [String: [String: Any]] = [:]
    private var tracked: Set<String> = []
    private var retryDelay: TimeInterval = 2
    private var retryItem: DispatchWorkItem?
    private var pingTimer: Timer?
    private var awaitingPong = false
    private var levelBusy: Set<String> = []
    private var levelPending: [String: Double] = [:]

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        session = URLSession(configuration: cfg, delegate: nil, delegateQueue: .main)
    }

    // MARK: Instellen

    func configure(url: String?, token: String?) {
        let newURL = url.flatMap(Self.normalize)
        if url != nil && newURL == nil {
            teardown()
            baseURL = nil; self.token = token
            status = .error(L("Ongeldig adres; gebruik bijv. http://homeassistant.local:8123"))
            return
        }
        guard newURL != baseURL || token != self.token || status == .off && newURL != nil else { return }
        baseURL = newURL
        self.token = token
        retryDelay = 2
        connect()
    }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              u.host?.isEmpty == false else { return nil }
        return u
    }

    func track(_ ids: Set<String>) {
        let added = !ids.subtracting(tracked).isEmpty
        tracked = ids
        entities = entities.filter { ids.contains($0.key) }
        if added, status == .connected { fetchStates() }
    }

    // MARK: Verbinding

    private func connect() {
        teardown()
        guard let base = baseURL else { status = .off; return }
        guard let token, !token.isEmpty else { status = .error(L("Geen token ingesteld (Koppelingen…)")); return }
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return }
        comps.scheme = base.scheme?.lowercased() == "https" ? "wss" : "ws"
        comps.path += "/api/websocket"
        guard let wsURL = comps.url else { return }
        let t = session.webSocketTask(with: wsURL)
        t.maximumMessageSize = 32 << 20 // get_states kan groot zijn bij veel apparaten
        task = t
        generation += 1
        let gen = generation
        status = .connecting
        t.resume()
        receive(gen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, gen == self.generation, self.status == .connecting else { return }
            self.failed(L("Home Assistant antwoordt niet"))
        }
    }

    private func teardown() {
        generation += 1
        retryItem?.cancel(); retryItem = nil
        pingTimer?.invalidate(); pingTimer = nil
        awaitingPong = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        let waiting = pending
        pending = [:]
        for cb in waiting.values { cb(false, ["error": ["message": "verbinding verbroken"]]) }
    }

    private func failed(_ msg: String, retry: Bool = true) {
        teardown()
        status = .error(msg)
        guard retry else { return }
        let item = DispatchWorkItem { [weak self] in self?.connect() }
        retryItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: item)
        retryDelay = min(retryDelay * 2, 60)
    }

    private func receive(_ gen: Int) {
        task?.receive { [weak self] result in
            guard let self, gen == self.generation else { return }
            switch result {
            case .failure(let e):
                NSLog("Cyberpad: Home Assistant: %@", e.localizedDescription)
                self.failed(L("Geen verbinding met Home Assistant; opnieuw proberen…"))
            case .success(let m):
                var data: Data?
                switch m {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: break
                }
                if let data, let obj = try? JSONSerialization.jsonObject(with: data) {
                    // HA bundelt soms meerdere berichten in één array.
                    if let list = obj as? [[String: Any]] { list.forEach(self.handle) }
                    else if let one = obj as? [String: Any] { self.handle(one) }
                }
                if gen == self.generation { self.receive(gen) }
            }
        }
    }

    private func handle(_ m: [String: Any]) {
        switch m["type"] as? String {
        case "auth_required":
            sendRaw(["type": "auth", "access_token": token ?? ""])
        case "auth_ok":
            status = .connected
            retryDelay = 2
            send(["type": "subscribe_events", "event_type": "state_changed"])
            fetchStates()
            startPing()
        case "auth_invalid":
            // Niet blijven proberen met een fout token.
            failed(L("Token geweigerd door Home Assistant"), retry: false)
        case "result", "pong":
            if let id = m["id"] as? Int, let cb = pending.removeValue(forKey: id) {
                cb(m["type"] as? String == "pong" || m["success"] as? Bool == true, m)
            }
        case "event":
            guard let ev = m["event"] as? [String: Any], let data = ev["data"] as? [String: Any],
                  let id = data["entity_id"] as? String, tracked.contains(id) else { return }
            entities[id] = data["new_state"] as? [String: Any]
            onChange?()
        default:
            break
        }
    }

    private func fetchStates() {
        send(["type": "get_states"]) { [weak self] ok, m in
            guard let self, ok, let list = m["result"] as? [[String: Any]] else { return }
            var found: [String: [String: Any]] = [:]
            for s in list {
                if let id = s["entity_id"] as? String, self.tracked.contains(id) { found[id] = s }
            }
            self.entities = found
            self.onChange?()
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.awaitingPong { self.failed(L("Home Assistant antwoordt niet meer")); return }
            self.awaitingPong = true
            self.send(["type": "ping"]) { [weak self] _, _ in self?.awaitingPong = false }
        }
    }

    private func send(_ msg: [String: Any], done: ((Bool, [String: Any]) -> Void)? = nil) {
        var m = msg
        let id = nextID
        nextID += 1
        m["id"] = id
        if let done { pending[id] = done }
        sendRaw(m)
    }

    private func sendRaw(_ m: [String: Any]) {
        guard let task, let data = try? JSONSerialization.data(withJSONObject: m),
              let s = String(data: data, encoding: .utf8) else { return }
        let gen = generation
        task.send(.string(s)) { [weak self] err in
            guard let err else { return }
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.failed(L("Versturen naar Home Assistant mislukt: {0}", err.localizedDescription))
            }
        }
    }

    // MARK: Diensten

    private func ensureConnected() throws {
        guard status == .connected else {
            throw ActionRunner.ActionError.failed(status == .off ? L("Home Assistant is niet gekoppeld (menubalk › Koppelingen…)")
                                                                  : status.text)
        }
    }

    static func domain(_ entity: String) -> String {
        String(entity.split(separator: ".", maxSplits: 1).first ?? "")
    }

    static func validEntity(_ e: String) -> Bool {
        e == "all" || e.range(of: "^[a-z0-9_]+\\.[a-z0-9_]+$", options: .regularExpression) != nil
    }

    /// Roept een dienst aan, bijv. "light.turn_on". Weigert HA, dan volgt een melding en `onFail`.
    func call(_ service: String, entity: String?, data: [String: Any] = [:], onFail: (() -> Void)? = nil) throws {
        guard service.range(of: "^[a-z0-9_]+\\.[a-z0-9_]+$", options: .regularExpression) != nil else {
            throw ActionRunner.ActionError.failed(L("Ongeldige dienst: {0} (verwacht bijv. light.turn_on)", service))
        }
        if let entity, !Self.validEntity(entity) { throw ActionRunner.ActionError.failed(L("Ongeldige entiteit: {0}", entity)) }
        try ensureConnected()
        let parts = service.split(separator: ".", maxSplits: 1).map(String.init)
        var msg: [String: Any] = ["type": "call_service", "domain": parts[0], "service": parts[1], "service_data": data]
        if let entity { msg["target"] = ["entity_id": entity] }
        send(msg) { [weak self] ok, m in
            guard !ok else { return }
            let err = (m["error"] as? [String: Any])?["message"] as? String ?? L("onbekende fout")
            onFail?()
            self?.onError?("Home Assistant: \(err)")
        }
    }

    /// `ha.toggle` en `ha.service` uit de layout.
    func perform(_ a: ActionSpec, onFail: (() -> Void)?) throws {
        switch a.type {
        case "ha.toggle":
            guard let e = a.entity, !e.isEmpty else { throw ActionRunner.ActionError.missing("entity") }
            let (service, data) = try toggleCall(e)
            try call(service, entity: e, data: data, onFail: onFail)
        case "ha.service":
            guard let s = a.service else { throw ActionRunner.ActionError.missing("service") }
            try call(s, entity: a.entity, data: (a.data ?? [:]).mapValues(\.any), onFail: onFail)
        default:
            throw ActionRunner.ActionError.unknown(a.type)
        }
    }

    /// Wat "aan/uit" betekent per soort apparaat. Een slot gaat met een tik alleen óp slot, nooit open.
    private func toggleCall(_ e: String) throws -> (String, [String: Any]) {
        switch Self.domain(e) {
        case "scene": return ("scene.turn_on", [:])
        case "script": return ("script.turn_on", [:])
        case "button", "input_button": return ("\(Self.domain(e)).press", [:])
        case "cover": return ("cover.toggle", [:])
        case "media_player": return ("media_player.media_play_pause", [:])
        case "lock":
            if entities[e]?["state"] as? String == "locked" {
                throw ActionRunner.ActionError.failed(L("Ontgrendelen kan alleen met een ha.service-knop (lock.unlock)"))
            }
            return ("lock.lock", [:])
        case "alarm_control_panel":
            throw ActionRunner.ActionError.failed(L("Een alarm bedien je met ha.service, niet met aan/uit"))
        case let d where Self.toggleDomains.contains(d):
            return ("homeassistant.toggle", [:])
        default:
            throw ActionRunner.ActionError.failed(L("{0} kan niet aan of uit (gebruik ha.service)", e))
        }
    }

    /// Soorten die met homeassistant.toggle aan/uit kunnen; sensoren en dergelijke niet.
    static let toggleDomains: Set<String> = ["light", "switch", "fan", "input_boolean", "automation", "humidifier",
                                             "siren", "climate", "water_heater", "vacuum", "remote", "group"]

    /// Schuif (0…1) voor lampen, rolluiken, mediaspelers, ventilatoren en getallen.
    /// Tijdens het slepen hoogstens 4 aanroepen per seconde; de laatste waarde komt altijd aan.
    func setLevel(_ e: String, _ v: Double) throws {
        let call = try levelCall(e, v)
        if levelBusy.contains(e) { levelPending[e] = v; return }
        try self.call(call.0, entity: e, data: call.1)
        levelBusy.insert(e)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.levelBusy.remove(e)
            if let next = self.levelPending.removeValue(forKey: e) { try? self.setLevel(e, next) }
        }
    }

    private func levelCall(_ e: String, _ v: Double) throws -> (String, [String: Any]) {
        let pct = Int((v * 100).rounded())
        switch Self.domain(e) {
        case "light": return pct == 0 ? ("light.turn_off", [:]) : ("light.turn_on", ["brightness_pct": pct])
        case "cover": return ("cover.set_cover_position", ["position": pct])
        case "media_player": return ("media_player.volume_set", ["volume_level": (v * 100).rounded() / 100])
        case "fan": return ("fan.set_percentage", ["percentage": pct])
        case "input_number", "number":
            let a = entities[e]?["attributes"] as? [String: Any] ?? [:]
            let lo = (a["min"] as? Double) ?? 0, hi = (a["max"] as? Double) ?? 100
            let step = (a["step"] as? Double) ?? 1
            let value = ((lo + v * (hi - lo)) / step).rounded() * step
            return ("\(Self.domain(e)).set_value", ["value": value])
        default:
            throw ActionRunner.ActionError.failed(L("Een schuif werkt niet voor {0}", e))
        }
    }

    /// Thermostaat een stap hoger of lager.
    func stepClimate(_ e: String, by dir: Double) throws {
        try ensureConnected()
        let a = entities[e]?["attributes"] as? [String: Any] ?? [:]
        guard let target = Self.number(a["temperature"]) else { throw ActionRunner.ActionError.failed(L("Geen doeltemperatuur voor {0}", e)) }
        let step = Self.number(a["target_temp_step"]) ?? 0.5
        var t = ((target + dir * step) / step).rounded() * step
        if let lo = Self.number(a["min_temp"]) { t = max(t, lo) }
        if let hi = Self.number(a["max_temp"]) { t = min(t, hi) }
        try call("climate.set_temperature", entity: e, data: ["temperature": t])
    }

    // MARK: Status voor de tablet

    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    static let onStates: Set<String> = ["on", "open", "opening", "playing", "unlocked", "home", "heat", "cool",
                                        "heat_cool", "auto", "dry", "fan_only", "active"]

    func stateMap() -> [String: Any] {
        var out: [String: Any] = [:]
        for id in tracked { out[id] = entityJSON(id) }
        return out
    }

    /// Alleen de velden die de tablet toont, niet alle attributen.
    func entityJSON(_ id: String?) -> [String: Any] {
        guard let id else { return ["status": "error", "error": L("Geen entiteit ingesteld")] }
        guard status == .connected else { return ["status": status.code, "error": status.text] }
        guard let s = entities[id] else { return ["status": "error", "error": L("Onbekend in Home Assistant: {0}", id)] }
        let a = s["attributes"] as? [String: Any] ?? [:]
        let state = s["state"] as? String ?? "unknown"
        let domain = Self.domain(id)
        var d: [String: Any] = [
            // "unknown" is normaal voor scènes en knoppen die nog nooit gebruikt zijn; alleen "unavailable" is offline.
            "status": state == "unavailable" ? "unavailable" : "ok",
            "state": state, "domain": domain, "on": Self.onStates.contains(state),
            "name": a["friendly_name"] as? String ?? id,
        ]
        if let u = a["unit_of_measurement"] as? String { d["unit"] = u }
        switch domain {
        case "light":
            if let b = Self.number(a["brightness"]) { d["level"] = (b / 255 * 100).rounded() / 100 } else { d["level"] = 0 }
        case "cover":
            if let p = Self.number(a["current_position"]) { d["level"] = p / 100 }
        case "media_player":
            if let v = Self.number(a["volume_level"]) { d["level"] = v }
        case "fan":
            if let p = Self.number(a["percentage"]) { d["level"] = p / 100 }
        case "input_number", "number":
            if let v = Double(state), let lo = Self.number(a["min"]), let hi = Self.number(a["max"]), hi > lo {
                d["level"] = (v - lo) / (hi - lo)
            }
        case "climate":
            if let c = Self.number(a["current_temperature"]) { d["current"] = c }
            if let t = Self.number(a["temperature"]) { d["target"] = t }
            if let h = a["hvac_action"] as? String { d["action"] = h }
        default:
            break
        }
        return d
    }
}
