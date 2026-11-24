import Foundation
import Combine

/// Instellingen in `integrations.json` (zonder geheimen). Geheimen staan in de sleutelhanger.
struct IntegrationConfig: Codable, Equatable {
    struct HomeAssistant: Codable, Equatable {
        var url: String
    }
    struct MQTT: Codable, Equatable {
        var host: String
        var port: Int?
        var tls: Bool?
        var username: String?
        var clientId: String?
    }
    struct Webhook: Codable, Equatable {
        var url: String
        var method: String?
        var headers: [String: String]?
        var body: String?
        /// Naam van een header (bijv. "Authorization") waarvan de waarde in de sleutelhanger staat.
        var secretHeader: String?
        var timeout: Int?
    }
    var homeAssistant: HomeAssistant?
    var mqtt: MQTT?
    var webhooks: [String: Webhook]?
}

/// Smart home en koppelingen: Home Assistant, MQTT en webhooks.
final class Integrations: ObservableObject {
    static let haTokenAccount = "homeassistant.token"
    static let mqttPasswordAccount = "mqtt.password"
    static func webhookAccount(_ name: String) -> String { "webhook.\(name)" }

    let url: URL
    let ha = HomeAssistantClient()
    let mqtt = MQTTClient()
    let webhooks = WebhookRunner()

    @Published private(set) var config = IntegrationConfig()
    @Published private(set) var configError: String?
    private var mtime: Date?
    private let clientID = "cyberpad-" + String(UUID().uuidString.prefix(6)).lowercased()

    /// Nieuwe status of waarden binnen → server stuurt de status uit.
    var onChange: (() -> Void)?
    /// Fouten die pas later binnenkomen (dienst geweigerd, webhook 500…).
    var onError: ((String) -> Void)? {
        didSet { ha.onError = onError; mqtt.onError = onError; webhooks.onError = onError }
    }

    init(dir: URL) {
        let env = ProcessInfo.processInfo.environment
        if env["CYBERPAD_DEBUG"] != nil, let p = env["CYBERPAD_INTEGRATIONS"] {
            url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        } else {
            url = dir.appendingPathComponent("integrations.json")
        }
        let changed: () -> Void = { [weak self] in
            self?.objectWillChange.send()
            self?.onChange?()
        }
        ha.onChange = changed
        mqtt.onChange = changed
        webhooks.secret = { Keychain.get($0) }
    }

    func start() {
        reload()
    }

    // MARK: Wat de layout gebruikt

    /// Alleen entiteiten en topics uit de layout worden gevolgd en naar de tablet gestuurd.
    func update(_ layout: Layout) {
        var entities = Set<String>(), topics = Set<String>()
        func scan(_ a: ActionSpec?) {
            guard let a else { return }
            if a.type.hasPrefix("ha."), let e = a.entity, e != "all" { entities.insert(e) }
            a.steps?.forEach(scan)
        }
        for t in layout.pages.flatMap(\.tiles) {
            [t.action, t.longPress, t.doubleTap, t.offAction].forEach(scan)
            if let e = t.config?.entity { entities.insert(e) }
            if let tp = t.config?.topic { topics.insert(tp) }
        }
        ha.track(entities)
        mqtt.track(topics)
    }

    // MARK: Instellingen

    func reloadIfChanged() {
        if modDate() != mtime { reload() }
    }

    private func modDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func reload() {
        mtime = modDate()
        var cfg = IntegrationConfig()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                cfg = try JSONDecoder().decode(IntegrationConfig.self, from: Data(contentsOf: url))
                configError = nil
            } catch {
                configError = L("integrations.json kon niet worden gelezen: {0}", error.localizedDescription)
                NSLog("Cyberpad: %@", configError!)
                return
            }
        } else {
            configError = nil
        }
        if cfg != config { config = cfg }
        apply()
    }

    /// Zet de instellingen door naar de clients (verbindt opnieuw als er iets veranderde).
    private func apply() {
        if let h = config.homeAssistant, !h.url.trimmingCharacters(in: .whitespaces).isEmpty {
            ha.configure(url: h.url, token: Keychain.get(Self.haTokenAccount))
        } else {
            ha.configure(url: nil, token: nil)
        }
        if let m = config.mqtt, !m.host.trimmingCharacters(in: .whitespaces).isEmpty {
            let tls = m.tls ?? false
            mqtt.configure(.init(host: m.host.trimmingCharacters(in: .whitespaces), port: m.port ?? (tls ? 8883 : 1883), tls: tls,
                                 username: m.username?.isEmpty == false ? m.username : nil,
                                 password: Keychain.get(Self.mqttPasswordAccount),
                                 clientId: m.clientId ?? clientID))
        } else {
            mqtt.configure(nil)
        }
        webhooks.hooks = config.webhooks ?? [:]
    }

    /// Vanuit het venster Koppelingen. `secrets`: account → nieuwe waarde (leeg = ongewijzigd laten).
    func save(_ cfg: IntegrationConfig, secrets: [String: String], clear: Set<String>) -> String? {
        for account in clear { Keychain.set(account, nil) }
        for (account, value) in secrets where !value.isEmpty {
            guard Keychain.set(account, value) else { return L("Kon {0} niet in de sleutelhanger bewaren", account) }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try enc.encode(cfg).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            return L("Kon integrations.json niet opslaan: {0}", error.localizedDescription)
        }
        // Geheimen kunnen veranderd zijn terwijl het bestand gelijk bleef: altijd opnieuw verbinden.
        ha.configure(url: nil, token: nil)
        mqtt.configure(nil)
        reload()
        return nil
    }

    func hasSecret(_ account: String) -> Bool { Keychain.get(account) != nil }

    // MARK: Status voor de tablet

    func state() -> [String: Any] {
        [
            "ha": ha.stateMap(),
            "mqtt": mqtt.values,
            "integrations": ["ha": ha.status.code, "mqtt": mqtt.status.code],
        ]
    }

    /// Waarde voor een mqtt-widget, eventueel één veld uit een JSON-bericht.
    func mqttJSON(_ cfg: WidgetConfig?) -> [String: Any] {
        guard let topic = cfg?.topic else { return ["status": "error", "error": L("Geen topic ingesteld")] }
        var d: [String: Any] = ["topic": topic]
        if let u = cfg?.unit { d["unit"] = u }
        guard mqtt.status == .connected || mqtt.values[topic] != nil else {
            d["status"] = mqtt.status.code
            d["error"] = mqtt.status.text
            return d
        }
        guard let raw = mqtt.values[topic] else { d["status"] = "waiting"; return d }
        var value = raw
        if let field = cfg?.field {
            guard let v = Self.extract(field, from: raw) else { d["status"] = "error"; d["error"] = L("Veld {0} niet gevonden", field); return d }
            value = v
        }
        d["status"] = mqtt.status == .connected ? "ok" : "stale"
        d["value"] = String(value.prefix(120))
        return d
    }

    static func extract(_ path: String, from raw: String) -> String? {
        guard var cur = try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed]) else { return nil }
        for key in path.split(separator: ".") {
            guard let obj = cur as? [String: Any], let next = obj[String(key)] else { return nil }
            cur = next
        }
        switch cur {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default:
            guard let d = try? JSONSerialization.data(withJSONObject: cur), let s = String(data: d, encoding: .utf8) else { return nil }
            return s
        }
    }

    static func truthy(_ s: String?) -> Bool {
        guard let s else { return false }
        return ["on", "true", "1", "yes", "aan", "open", "online"].contains(s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

/// Gedeelde verbindingsstatus van Home Assistant en MQTT.
enum LinkStatus: Equatable {
    case off, connecting, connected, error(String)

    var code: String {
        switch self {
        case .off: return "off"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .error: return "error"
        }
    }

    var text: String {
        switch self {
        case .off: return L("Niet ingesteld (menubalk › Koppelingen…)")
        case .connecting: return L("Verbinden…")
        case .connected: return L("Verbonden")
        case .error(let m): return m
        }
    }
}
