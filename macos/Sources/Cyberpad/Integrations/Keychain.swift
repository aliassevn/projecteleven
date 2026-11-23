import Foundation
import Security

/// Geheimen (Home Assistant-token, MQTT-wachtwoord, webhook-sleutels) staan alleen in de sleutelhanger, nooit in een bestand.
enum Keychain {
    static let service = "com.projecteleven.cyberpad"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String? {
        // Alleen tijdens ontwikkelen: geheim uit een omgevingsvariabele, zodat tests de sleutelhanger niet aanraken.
        let env = ProcessInfo.processInfo.environment
        if env["CYBERPAD_DEBUG"] != nil, let v = env[envName(account)] { return v }
        var q = base(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Lege waarde of nil = verwijderen.
    @discardableResult
    static func set(_ account: String, _ value: String?) -> Bool {
        let q = base(account)
        guard let value, !value.isEmpty else {
            let st = SecItemDelete(q as CFDictionary)
            return st == errSecSuccess || st == errSecItemNotFound
        }
        let data = Data(value.utf8)
        let st = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if st == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Cyberpad: \(account)"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return st == errSecSuccess
    }

    /// "homeassistant.token" → CYBERPAD_SECRET_HOMEASSISTANT_TOKEN
    static func envName(_ account: String) -> String {
        "CYBERPAD_SECRET_" + String(account.uppercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}
