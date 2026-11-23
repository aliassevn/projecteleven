import Foundation
import CryptoKit
import Security

struct Device: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// SHA-256 van het token; het token zelf wordt nergens op de Mac bewaard.
    var tokenHash: String
    var created: Date
    var lastSeen: Date?
    /// Vast profiel voor deze tablet; nil = automatisch (tijd, Focus, menu).
    var profile: String?
}

/// Koppelcodes, tokens per tablet en bescherming tegen raden.
final class PairingManager: ObservableObject {
    static let codeLifetime: TimeInterval = 120
    static let maxFailuresPerIP = 5
    static let blockSeconds: TimeInterval = 60
    static let maxFailuresPerCode = 20

    @Published private(set) var code = ""
    @Published private(set) var codeExpires = Date.distantPast
    @Published private(set) var devices: [Device] = []

    var onRevoke: ((String) -> Void)?
    var onProfileChange: ((String) -> Void)?

    private var failures: [String: (count: Int, blockedUntil: Date?)] = [:]
    private var failuresThisCode = 0
    private let storeURL: URL
    private var lastSaved = Date.distantPast

    init(dir: URL) {
        storeURL = dir.appendingPathComponent("devices.json")
        load()
        rotate()
    }

    // MARK: Code

    func rotate() {
        code = String(format: "%06u", Self.randomUInt32() % 1_000_000)
        codeExpires = Date().addingTimeInterval(Self.codeLifetime)
        failuresThisCode = 0
    }

    func rotateIfExpired() {
        if Date() >= codeExpires { rotate() }
    }

    enum PairResult {
        case ok(token: String, device: Device)
        case wrong(attemptsLeft: Int)
        case blocked(seconds: Int)
    }

    func pair(code input: String, name: String, ip: String) -> PairResult {
        rotateIfExpired()
        let now = Date()
        if let f = failures[ip], let until = f.blockedUntil, until > now {
            return .blocked(seconds: Int(until.timeIntervalSince(now).rounded(.up)))
        }

        let digits = input.filter(\.isNumber)
        guard Self.constantTimeEqual(digits, code) else {
            var f = failures[ip] ?? (0, nil)
            f.count += 1
            if f.count >= Self.maxFailuresPerIP {
                f = (0, now.addingTimeInterval(Self.blockSeconds))
                failures[ip] = f
                return .blocked(seconds: Int(Self.blockSeconds))
            }
            failures[ip] = f
            failuresThisCode += 1
            if failuresThisCode >= Self.maxFailuresPerCode { rotate() } // tegen raden vanaf veel adressen
            return .wrong(attemptsLeft: Self.maxFailuresPerIP - f.count)
        }

        failures[ip] = nil
        let token = Self.randomHex(bytes: 32)
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "Tablet" }
        let device = Device(id: UUID().uuidString, name: String(clean.prefix(40)),
                            tokenHash: Self.sha256(token), created: now, lastSeen: now)
        devices.append(device)
        save()
        rotate() // een code werkt maar één keer
        return .ok(token: token, device: device)
    }

    // MARK: Tokens

    func authenticate(token: String?) -> Device? {
        guard let token, token.count == 64 else { return nil }
        let h = Self.sha256(token)
        guard let i = devices.firstIndex(where: { Self.constantTimeEqual($0.tokenHash, h) }) else { return nil }
        devices[i].lastSeen = Date()
        if Date().timeIntervalSince(lastSaved) > 60 { save() }
        return devices[i]
    }

    func setProfile(id: String, profile: String?) {
        guard let i = devices.firstIndex(where: { $0.id == id }), devices[i].profile != profile else { return }
        devices[i].profile = profile
        save()
        onProfileChange?(id)
    }

    func revoke(id: String) {
        devices.removeAll { $0.id == id }
        save()
        onRevoke?(id)
    }

    // MARK: Opslag

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        devices = (try? dec.decode([Device].self, from: data)) ?? []
    }

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted]
        guard let data = try? enc.encode(devices) else { return }
        try? data.write(to: storeURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        lastSaved = Date()
    }

    // MARK: Crypto-hulpjes

    static func randomUInt32() -> UInt32 {
        var v: UInt32 = 0
        _ = SecRandomCopyBytes(kSecRandomDefault, 4, &v)
        return v
    }

    static func randomHex(bytes n: Int) -> String {
        var b = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
        return b.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }
}
