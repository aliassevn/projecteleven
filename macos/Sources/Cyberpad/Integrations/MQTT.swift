import Foundation
import Network

/// Kleine MQTT 3.1.1-client (QoS 0) over Network.framework: publiceren en abonneren op vaste topics.
/// Alleen topics uit de layout worden gevolgd; wildcards (+ en #) worden niet gebruikt.
final class MQTTClient {
    struct Settings: Equatable {
        var host: String
        var port: Int
        var tls: Bool
        var username: String?
        var password: String?
        var clientId: String
    }

    private(set) var status: LinkStatus = .off { didSet { if status != oldValue { onChange?() } } }
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    /// Laatste bericht per gevolgd topic.
    private(set) var values: [String: String] = [:]

    private var settings: Settings?
    private var conn: NWConnection?
    private var generation = 0
    private var buffer = Data()
    private var tracked: Set<String> = []
    private var subscribed: Set<String> = []
    private var packetID: UInt16 = 0
    private var retryDelay: TimeInterval = 2
    private var retryItem: DispatchWorkItem?
    private var pingTimer: Timer?
    private var awaitingPing = false

    static let keepAlive: UInt16 = 30
    static let maxPacket = 1 << 20

    func configure(_ s: Settings?) {
        guard s != settings || (s != nil && status == .off) else { return }
        settings = s
        values = [:]
        retryDelay = 2
        connect()
    }

    func track(_ topics: Set<String>) {
        tracked = topics.filter(Self.validTopic)
        values = values.filter { tracked.contains($0.key) }
        if status == .connected { subscribeMissing() }
    }

    static func validTopic(_ t: String) -> Bool {
        !t.isEmpty && t.utf8.count < 1024 && !t.contains("+") && !t.contains("#") && !t.contains("\u{0}")
    }

    // MARK: Verbinding

    private func connect() {
        teardown()
        guard let s = settings else { status = .off; return }
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: s.port)), s.port > 0 else {
            status = .error("Ongeldige MQTT-poort")
            return
        }
        let c = NWConnection(host: NWEndpoint.Host(s.host), port: port, using: s.tls ? .tls : .tcp)
        generation += 1
        let gen = generation
        conn = c
        buffer = Data()
        status = .connecting
        c.stateUpdateHandler = { [weak self] st in
            guard let self, gen == self.generation else { return }
            switch st {
            case .ready: self.sendConnect()
            case .failed(let e): self.failed("Geen verbinding met MQTT-broker: \(e.localizedDescription)")
            case .waiting(let e): self.failed("MQTT-broker niet bereikbaar: \(e.localizedDescription)")
            default: break
            }
        }
        c.start(queue: .main)
        receive(gen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, gen == self.generation, self.status == .connecting else { return }
            self.failed("MQTT-broker antwoordt niet")
        }
    }

    private func teardown() {
        generation += 1
        retryItem?.cancel(); retryItem = nil
        pingTimer?.invalidate(); pingTimer = nil
        awaitingPing = false
        if let c = conn {
            if status == .connected { c.send(content: Self.packet(0xE0, Data()), completion: .idempotent) } // DISCONNECT
            c.cancel()
        }
        conn = nil
        subscribed = []
    }

    private func failed(_ msg: String, retry: Bool = true) {
        teardown()
        status = .error(msg)
        guard retry, settings != nil else { return }
        let item = DispatchWorkItem { [weak self] in self?.connect() }
        retryItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay, execute: item)
        retryDelay = min(retryDelay * 2, 60)
    }

    private func write(_ d: Data) {
        guard let c = conn else { return }
        let gen = generation
        c.send(content: d, completion: .contentProcessed { [weak self] err in
            guard let self, let err, gen == self.generation else { return }
            self.failed("Versturen naar MQTT mislukt: \(err.localizedDescription)")
        })
    }

    private func receive(_ gen: Int) {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self, gen == self.generation else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.parse(gen)
                guard gen == self.generation else { return }
            }
            if let err { self.failed("MQTT-verbinding verbroken: \(err.localizedDescription)"); return }
            if done { self.failed("MQTT-broker sloot de verbinding"); return }
            self.receive(gen)
        }
    }

    // MARK: Pakketten

    static func be16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xff)]) }

    static func str(_ s: String) -> Data {
        let b = Data(s.utf8.prefix(65535))
        return be16(UInt16(b.count)) + b
    }

    static func remainingLength(_ n: Int) -> Data {
        var x = n
        var out = Data()
        repeat {
            var byte = UInt8(x % 128)
            x /= 128
            if x > 0 { byte |= 0x80 }
            out.append(byte)
        } while x > 0
        return out
    }

    static func packet(_ header: UInt8, _ body: Data) -> Data {
        var d = Data([header])
        d.append(remainingLength(body.count))
        d.append(body)
        return d
    }

    private func sendConnect() {
        guard let s = settings else { return }
        var body = Self.str("MQTT")
        body.append(4) // protocolniveau 3.1.1
        var flags: UInt8 = 0x02 // clean session
        if s.username != nil { flags |= 0x80 }
        if s.username != nil, s.password != nil { flags |= 0x40 }
        body.append(flags)
        body.append(Self.be16(Self.keepAlive))
        body.append(Self.str(s.clientId))
        if let u = s.username {
            body.append(Self.str(u))
            if let p = s.password { body.append(Self.str(p)) }
        }
        write(Self.packet(0x10, body))
    }

    private func parse(_ gen: Int) {
        while gen == generation {
            guard buffer.count >= 2 else { return }
            var mult = 1, len = 0, i = 1, complete = false
            while i < buffer.count && i <= 4 {
                let b = buffer[buffer.startIndex + i]
                len += Int(b & 0x7f) * mult
                mult *= 128
                i += 1
                if b & 0x80 == 0 { complete = true; break }
            }
            guard complete else {
                if i > 4 { failed("Ongeldig MQTT-pakket") }
                return
            }
            guard len <= Self.maxPacket else { failed("MQTT-pakket te groot"); return }
            guard buffer.count >= i + len else { return }
            let header = buffer[buffer.startIndex]
            let body = Data(buffer[(buffer.startIndex + i)..<(buffer.startIndex + i + len)])
            buffer = Data(buffer[(buffer.startIndex + i + len)...])
            handle(header, body)
        }
    }

    private func handle(_ header: UInt8, _ body: Data) {
        switch header >> 4 {
        case 2: // CONNACK
            guard body.count >= 2 else { failed("Ongeldig antwoord van de broker"); return }
            let rc = body[1]
            if rc == 0 {
                status = .connected
                retryDelay = 2
                subscribed = []
                subscribeMissing()
                startPing()
            } else {
                let reasons: [UInt8: String] = [1: "protocolversie niet ondersteund", 2: "client-id geweigerd",
                                                3: "broker niet beschikbaar", 4: "onjuiste gebruikersnaam of wachtwoord",
                                                5: "geen toestemming"]
                // Bij een fout wachtwoord niet blijven proberen.
                failed("Broker weigert: \(reasons[rc] ?? "code \(rc)")", retry: rc != 4 && rc != 5)
            }
        case 3: // PUBLISH
            let qos = (header >> 1) & 0x3
            guard body.count >= 2 else { return }
            let tl = Int(body[0]) << 8 | Int(body[1])
            guard body.count >= 2 + tl else { return }
            let topic = String(decoding: body[2..<(2 + tl)], as: UTF8.self)
            var off = 2 + tl
            if qos > 0 {
                guard body.count >= off + 2 else { return }
                if qos == 1 { write(Self.packet(0x40, Data(body[off..<(off + 2)]))) } // PUBACK
                off += 2
            }
            guard tracked.contains(topic) else { return }
            let payload = String(data: body[off...], encoding: .utf8) ?? "(binair bericht)"
            let v = String(payload.prefix(1024))
            if values[topic] != v { values[topic] = v; onChange?() }
        case 9: // SUBACK
            if body.count >= 3, body[2] == 0x80 { onError?("MQTT-broker weigert een abonnement") }
        case 13: // PINGRESP
            awaitingPing = false
        default:
            break
        }
    }

    private func nextPacketID() -> UInt16 {
        packetID = packetID == UInt16.max ? 1 : packetID + 1
        return packetID
    }

    private func subscribeMissing() {
        for topic in tracked.subtracting(subscribed).sorted() {
            var body = Self.be16(nextPacketID())
            body.append(Self.str(topic))
            body.append(0) // QoS 0
            write(Self.packet(0x82, body))
            subscribed.insert(topic)
        }
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(Self.keepAlive - 5), repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.awaitingPing { self.failed("MQTT-broker antwoordt niet meer"); return }
            self.awaitingPing = true
            self.write(Self.packet(0xC0, Data()))
        }
    }

    // MARK: Publiceren

    func publish(topic: String, payload: String, retain: Bool) throws {
        guard Self.validTopic(topic) else { throw ActionRunner.ActionError.failed("Ongeldig MQTT-topic: \(topic)") }
        guard status == .connected else {
            throw ActionRunner.ActionError.failed(status == .off ? "MQTT is niet gekoppeld (menubalk › Koppelingen…)" : status.text)
        }
        var body = Self.str(topic)
        body.append(Data(payload.utf8))
        write(Self.packet(0x30 | (retain ? 0x01 : 0x00), body))
    }
}
