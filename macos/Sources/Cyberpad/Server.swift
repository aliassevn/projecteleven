import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String] = [:]
    var headers: [String: String] // sleutels in kleine letters
    var body: Data

    func json() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}

/// HTTP- en WebSocket-server op één poort. Alles draait op de main queue.
final class Server {
    static let port: UInt16 = 7420
    static let maxHeader = 16 * 1024
    static let maxBody = 64 * 1024

    let pairing: PairingManager
    let layouts: LayoutStore
    let actions: ActionRunner
    let padDir: URL

    var meeting: MeetingMonitor?
    var agenda: AgendaProvider?
    var widgets: WidgetHub?
    var integrations: Integrations?
    /// Laatste keer dat een tablet iets vroeg (ook via XHR), om te weten of widgets bijgewerkt moeten worden.
    private(set) var lastActivity = Date.distantPast
    func touch() { lastActivity = Date() }
    var hasActiveClients: Bool { !onlineDeviceIDs.isEmpty || Date().timeIntervalSince(lastActivity) < 30 }

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Connection] = [:]
    private(set) var lastError: String?
    var onClientsChanged: (() -> Void)?

    init(pairing: PairingManager, layouts: LayoutStore, actions: ActionRunner, padDir: URL) {
        self.pairing = pairing
        self.layouts = layouts
        self.actions = actions
        self.padDir = padDir
    }

    var onlineDeviceIDs: Set<String> {
        Set(connections.values.compactMap { $0.isWebSocket ? $0.deviceID : nil })
    }

    // MARK: Starten

    func start(serviceName: String) throws {
        let params = NWParameters.tcp
        let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: Self.port)!)
        l.service = NWListener.Service(name: serviceName, type: "_http._tcp")
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let e):
                self?.lastError = "Server gestopt: \(e.localizedDescription)"
                NSLog("Cyberpad: %@", self?.lastError ?? "")
            case .ready:
                self?.lastError = nil
            default: break
            }
            self?.onClientsChanged?()
        }
        l.serviceRegistrationUpdateHandler = { change in
            if case .add(let ep) = change { NSLog("Cyberpad: Bonjour-dienst actief: %@", "\(ep)") }
        }
        l.newConnectionHandler = { [weak self] nw in self?.accept(nw) }
        l.start(queue: .main)
        listener = l
    }

    private func accept(_ nw: NWConnection) {
        guard NetUtil.isLocal(nw.endpoint) else {
            NSLog("Cyberpad: verbinding van buiten het lokale netwerk geweigerd (%@)", NetUtil.describe(nw.endpoint))
            nw.cancel()
            return
        }
        let c = Connection(nw, server: self)
        connections[ObjectIdentifier(c)] = c
        c.start()
    }

    fileprivate func remove(_ c: Connection) {
        if connections.removeValue(forKey: ObjectIdentifier(c)) != nil, c.isWebSocket { onClientsChanged?() }
    }

    // MARK: Uitzenden

    func broadcast(_ msg: [String: Any]) {
        for c in connections.values where c.isWebSocket && c.deviceID != nil { c.sendJSON(msg) }
    }

    func broadcastLayout() {
        broadcast(["type": "layout", "layout": layoutJSON()])
    }

    func disconnect(deviceID: String) {
        for c in connections.values where c.deviceID == deviceID {
            c.rejectAndClose()
        }
    }

    /// De layout zoals de tablet hem krijgt: alleen wat nodig is om te tekenen.
    /// Wat een knop doet (toetsen, teksten, opdrachten) blijft op de Mac.
    func layoutJSON() -> Any {
        let l = layouts.layout
        return [
            "version": l.version, "columns": l.columns, "rows": l.rows, "theme": l.theme,
            "pages": l.pages.map { p -> [String: Any] in
                ["id": p.id, "name": p.name, "tiles": p.tiles.map(Self.padTile)]
            },
        ]
    }

    private static func padTile(_ t: Tile) -> [String: Any] {
        var d: [String: Any] = ["id": t.id, "label": t.label, "kind": t.kind ?? "button", "x": t.x, "y": t.y]
        if let v = t.icon { d["icon"] = v }
        if let v = t.w { d["w"] = v }
        if let v = t.h { d["h"] = v }
        if t.kind == "terminal", t.config?.dangerous == true { d["dangerous"] = true }
        if t.longPress != nil { d["hasLong"] = true }
        if t.doubleTap != nil { d["hasDouble"] = true }
        if let key = integrationStateKey(t) {
            // De echte stand van het apparaat (Home Assistant of een MQTT-statustopic).
            d["stateKey"] = key
        } else if t.toggle == true {
            d["toggle"] = true
        } else if let key = ActionRunner.stateKey(for: t.action?.type) {
            d["stateKey"] = key
        }
        return d
    }

    private static func integrationStateKey(_ t: Tile) -> String? {
        guard t.isButton || t.kind == "slider" else { return nil }
        if let topic = t.config?.topic { return "mqtt:" + topic }
        if let a = t.action, ["ha.toggle", "ha.level"].contains(a.type), let e = a.entity { return "ha:" + e }
        return nil
    }

    /// Alles wat de tablet aan status nodig heeft: knoppen, volume, vergadering en agenda.
    func fullState() -> [String: Any] {
        var s = actions.state()
        s["meeting"] = meeting?.current?.json() ?? NSNull()
        s["agenda"] = agenda?.json() ?? NSNull()
        s["widgets"] = widgets?.state() ?? [:]
        if let i = integrations?.state() { s.merge(i) { $1 } }
        return s
    }

    /// Bediening van een widget-tegel (timer, muziek, terminal…). De tegel bepaalt wat mag.
    func handleWidget(id: String, action: String, value: Double?) -> (ok: Bool, error: String?) {
        guard let tile = layouts.layout.tile(id: id), tile.isWidget, let widgets else { return (false, "Onbekende widget: \(id)") }
        do { try widgets.handle(tile, action: action, value: value); return (true, nil) } catch { return (false, error.localizedDescription) }
    }

    /// Knop in het vergaderpaneel. Alleen vaste acties; welke toetsen dat zijn bepaalt de catalogus op de Mac.
    func handleMeeting(action: String) -> (ok: Bool, error: String?) {
        guard MeetingMonitor.actionOrder.contains(action), let meeting else { return (false, "Onbekende vergaderactie") }
        do { try meeting.perform(action); return (true, nil) } catch { return (false, error.localizedDescription) }
    }

    // MARK: Berichten van de tablet (WebSocket én XHR gebruiken dezelfde route)

    /// Voert een druk of schuifbeweging uit. De tablet geeft alleen een tegel-id (en gebaar); de actie komt uit de layout.
    func handleInput(type: String, id: String, gesture: String?, value: Double?) -> (ok: Bool, error: String?) {
        guard let tile = layouts.layout.tile(id: id) else {
            return (false, "Onbekende knop: \(id)")
        }
        do {
            switch type {
            case "press":
                if tile.kind == "agenda" { try agenda?.joinNext(); return (true, nil) }
                guard tile.isButton else { return (false, "Dit is geen knop") }
                let g = ["long", "double"].contains(gesture ?? "") ? gesture! : "tap"
                try actions.press(tile, gesture: g)
            case "slider":
                guard tile.kind == "slider", let action = tile.action, let v = value, v.isFinite else {
                    return (false, "Ongeldige schuifwaarde")
                }
                try actions.setSlider(action, value: min(max(v, 0), 1))
            default:
                return (false, "Onbekend bericht")
            }
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: HTTP-routes

    fileprivate func handle(_ req: HTTPRequest, on c: Connection) {
        if req.method == "GET", req.path == "/ws",
           req.headers["upgrade"]?.lowercased() == "websocket", let key = req.headers["sec-websocket-key"] {
            c.upgrade(acceptKey: WebSocket.acceptKey(for: key))
            return
        }

        switch (req.method, req.path) {
        case ("GET", "/api/ping"):
            c.respond(200, json: ["ok": true, "app": "Cyberpad"])

        case ("POST", "/api/pair"):
            let body = req.json() ?? [:]
            let code = body["code"] as? String ?? ""
            let name = body["name"] as? String ?? "Tablet"
            switch pairing.pair(code: code, name: name, ip: c.remoteIP) {
            case .ok(let token, let device):
                c.respond(200, json: ["token": token, "deviceId": device.id])
                onClientsChanged?()
            case .wrong(let left):
                c.respond(401, json: ["error": "wrong", "attemptsLeft": left])
            case .blocked(let s):
                c.respond(429, json: ["error": "blocked", "seconds": s])
            }

        case ("GET", "/api/layout"), ("GET", "/api/state"), ("POST", "/api/press"), ("POST", "/api/slider"),
             ("POST", "/api/meeting"), ("POST", "/api/widget"), ("GET", "/api/photo"):
            guard let device = pairing.authenticate(token: req.headers["x-cyberpad-token"]) else {
                c.respond(401, json: ["error": "unauthorized"])
                return
            }
            c.deviceID = device.id
            lastActivity = Date()
            switch req.path {
            case "/api/photo":
                guard let tile = layouts.layout.tile(id: req.query["tile"] ?? ""), tile.kind == "photos", let widgets else {
                    c.respond(404, text: "Not found"); return
                }
                widgets.photos.image(for: tile.config, index: Int(req.query["i"] ?? "0") ?? 0) { data in
                    if let data { c.respond(200, body: data, contentType: "image/jpeg") } else { c.respond(404, text: "Geen foto") }
                }
            case "/api/widget":
                let body = req.json() ?? [:]
                let r = handleWidget(id: body["id"] as? String ?? "", action: body["action"] as? String ?? "",
                                     value: (body["value"] as? NSNumber)?.doubleValue)
                var out: [String: Any] = ["ok": r.ok]
                if let e = r.error { out["error"] = e }
                c.respond(200, json: out)
                scheduleStateBroadcast()
            case "/api/layout":
                c.respond(200, json: ["layout": layoutJSON(), "state": fullState()])
            case "/api/state":
                c.respond(200, json: ["state": fullState()])
            case "/api/meeting":
                let r = handleMeeting(action: (req.json() ?? [:])["action"] as? String ?? "")
                var out: [String: Any] = ["ok": r.ok]
                if let e = r.error { out["error"] = e }
                c.respond(200, json: out)
                scheduleStateBroadcast()
            default:
                let body = req.json() ?? [:]
                let r = handleInput(type: req.path == "/api/press" ? "press" : "slider",
                                    id: body["id"] as? String ?? "",
                                    gesture: body["gesture"] as? String,
                                    value: (body["value"] as? NSNumber)?.doubleValue)
                var out: [String: Any] = ["ok": r.ok]
                if let e = r.error { out["error"] = e }
                c.respond(200, json: out)
                scheduleStateBroadcast()
            }

        case ("GET", _):
            serveStatic(req.path, on: c)

        default:
            c.respond(405, text: "Method not allowed")
        }
    }

    private var stateBroadcastPending = false
    func scheduleStateBroadcast() {
        guard !stateBroadcastPending else { return }
        stateBroadcastPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.stateBroadcastPending = false
            self.broadcast(["type": "state", "state": self.fullState()])
        }
    }

    private func serveStatic(_ rawPath: String, on c: Connection) {
        var path = rawPath.removingPercentEncoding ?? rawPath
        if path == "/" { path = "/index.html" }
        let parts = path.split(separator: "/").map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0.hasPrefix(".") }) else {
            c.respond(404, text: "Not found"); return
        }
        let file = parts.reduce(padDir) { $0.appendingPathComponent($1) }
        guard file.standardizedFileURL.path.hasPrefix(padDir.standardizedFileURL.path),
              let data = try? Data(contentsOf: file) else {
            c.respond(404, text: "Not found"); return
        }
        let types = ["html": "text/html; charset=utf-8", "js": "application/javascript; charset=utf-8",
                     "css": "text/css; charset=utf-8", "json": "application/json", "png": "image/png",
                     "svg": "image/svg+xml", "ttf": "font/ttf", "woff2": "font/woff2"]
        c.respond(200, body: data, contentType: types[file.pathExtension.lowercased()] ?? "application/octet-stream")
    }
}

// MARK: - Eén TCP-verbinding: eerst HTTP, eventueel daarna WebSocket

private final class Connection {
    let nw: NWConnection
    unowned let server: Server
    let remoteIP: String
    var deviceID: String?
    private(set) var isWebSocket = false
    private var buffer = Data()
    private var closed = false
    private var fragments = Data()
    private var helloTimer: DispatchWorkItem?

    init(_ nw: NWConnection, server: Server) {
        self.nw = nw
        self.server = server
        self.remoteIP = NetUtil.describe(nw.endpoint)
    }

    func start() {
        nw.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        nw.start(queue: .main)
        receive()
    }

    private func receive() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.process()
            }
            if complete || error != nil { self.close(); return }
            if !self.closed { self.receive() }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        helloTimer?.cancel()
        nw.cancel()
        server.remove(self)
    }

    // MARK: HTTP

    private func process() {
        if isWebSocket { processFrames(); return }

        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            if buffer.count > Server.maxHeader { respond(431, text: "Header too large") }
            return
        }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else {
            respond(400, text: "Bad request"); return
        }
        var lines = head.components(separatedBy: "\r\n")
        let reqLine = lines.removeFirst().split(separator: " ")
        guard reqLine.count >= 2 else { respond(400, text: "Bad request"); return }

        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].trimmingCharacters(in: .whitespaces).lowercased()] =
                l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= Server.maxBody else { respond(413, text: "Too large"); return }
        let bodyStart = end.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= length else { return } // wacht op rest van body

        let body = buffer[bodyStart..<(bodyStart + length)]
        let target = String(reqLine[1])
        let pieces = target.split(separator: "?", maxSplits: 1).map(String.init)
        let path = pieces.first ?? "/"
        var query: [String: String] = [:]
        if pieces.count > 1 {
            for pair in pieces[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
                if let k = kv.first { query[k] = kv.count > 1 ? kv[1] : "" }
            }
        }
        buffer.removeAll()
        server.handle(HTTPRequest(method: String(reqLine[0]), path: path, query: query, headers: headers, body: Data(body)), on: self)
    }

    func respond(_ status: Int, json: Any) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        respond(status, body: data, contentType: "application/json")
    }

    func respond(_ status: Int, text: String) {
        respond(status, body: Data(text.utf8), contentType: "text/plain; charset=utf-8")
    }

    func respond(_ status: Int, body: Data, contentType: String) {
        let reasons = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed",
                       413: "Payload Too Large", 429: "Too Many Requests", 431: "Request Header Fields Too Large"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "OK")\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "X-Content-Type-Options: nosniff\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        nw.send(content: out, completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    // MARK: WebSocket

    func upgrade(acceptKey: String) {
        let head = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
                   "Sec-WebSocket-Accept: \(acceptKey)\r\n\r\n"
        isWebSocket = true
        nw.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        // Binnen 10 seconden moet er een geldig "hello" met token komen.
        let t = DispatchWorkItem { [weak self] in
            guard let self, self.deviceID == nil else { return }
            self.rejectAndClose()
        }
        helloTimer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: t)
        if !buffer.isEmpty { processFrames() }
    }

    private func processFrames() {
        do {
            while let f = try WebSocket.parse(&buffer) {
                switch f.opcode {
                case .ping: send(.pong, f.payload)
                case .pong: break
                case .close: send(.close, Data()); close(); return
                case .text, .continuation:
                    fragments.append(f.payload)
                    guard fragments.count <= WebSocket.maxPayload else { close(); return }
                    if f.fin {
                        let msg = fragments
                        fragments = Data()
                        handleMessage(msg)
                    }
                case .binary: break
                }
            }
        } catch {
            close()
        }
    }

    private func handleMessage(_ data: Data) {
        guard let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = msg["type"] as? String else { return }

        if type == "hello" {
            guard let device = server.pairing.authenticate(token: msg["token"] as? String) else {
                rejectAndClose()
                return
            }
            helloTimer?.cancel()
            deviceID = device.id
            sendJSON(["type": "welcome", "device": device.name])
            sendJSON(["type": "layout", "layout": server.layoutJSON()])
            sendJSON(["type": "state", "state": server.fullState()])
            server.onClientsChanged?()
            return
        }

        guard deviceID != nil else { close(); return }
        server.touch()
        switch type {
        case "ping":
            sendJSON(["type": "pong"])
        case "widget":
            let id = msg["id"] as? String ?? ""
            let r = server.handleWidget(id: id, action: msg["action"] as? String ?? "",
                                        value: (msg["value"] as? NSNumber)?.doubleValue)
            if !r.ok {
                var ack: [String: Any] = ["type": "ack", "id": id, "ok": false]
                if let e = r.error { ack["error"] = e }
                sendJSON(ack)
            }
            server.scheduleStateBroadcast()
        case "meeting":
            let r = server.handleMeeting(action: msg["action"] as? String ?? "")
            var ack: [String: Any] = ["type": "ack", "id": "meeting", "ok": r.ok]
            if let e = r.error { ack["error"] = e }
            sendJSON(ack)
            server.scheduleStateBroadcast()
        case "press", "slider":
            let id = msg["id"] as? String ?? ""
            let r = server.handleInput(type: type, id: id, gesture: msg["gesture"] as? String,
                                       value: (msg["value"] as? NSNumber)?.doubleValue)
            if type == "press" || !r.ok {
                var ack: [String: Any] = ["type": "ack", "id": id, "ok": r.ok]
                if let e = r.error { ack["error"] = e }
                sendJSON(ack)
            }
            server.scheduleStateBroadcast()
        default:
            break
        }
    }

    func sendJSON(_ obj: Any) {
        guard isWebSocket, let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        send(.text, data)
    }

    /// Meldt "unauthorized" aan de tablet en sluit pas als dat bericht echt verstuurd is.
    func rejectAndClose() {
        guard !closed, isWebSocket, let data = try? JSONSerialization.data(withJSONObject: ["type": "unauthorized"]) else {
            close(); return
        }
        var out = WebSocket.encode(.text, data)
        out.append(WebSocket.encode(.close, Data([0x03, 0xE8]))) // 1000 normaal gesloten
        nw.send(content: out, completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    private func send(_ op: WebSocket.Opcode, _ payload: Data) {
        guard !closed else { return }
        nw.send(content: WebSocket.encode(op, payload), completion: .contentProcessed { _ in })
    }
}
