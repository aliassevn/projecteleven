import Foundation

/// Taal van Cyberpad: Engels (standaard), Nederlands of Spaans.
///
/// De Nederlandse tekst in de code is de sleutel. `shared/i18n/en.json` en `es.json` geven per sleutel de
/// vertaling; ontbreekt er een, dan blijft de Nederlandse tekst staan. De tablet en de editor krijgen hetzelfde
/// woordenboek via `GET /i18n.js`, zodat macOS en (later) Windows precies dezelfde vertalingen gebruiken.
final class Localizer: ObservableObject {
    static let shared = Localizer()

    /// Volgorde zoals in de menu's.
    static let languages: [(code: String, name: String)] = [("en", "English"), ("nl", "Nederlands"), ("es", "Español")]
    static let defaultLanguage = "en"
    private static let defaultsKey = "language"

    @Published private(set) var lang: String
    private var dicts: [String: [String: String]] = [:]
    /// Na een taalwissel: tablets en editor opnieuw laten laden.
    var onChange: ((String) -> Void)?

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? Self.defaultLanguage
        lang = Self.languages.contains { $0.code == saved } ? saved : Self.defaultLanguage
        let dir = Core.findResource("i18n", env: "CYBERPAD_I18N_DIR")
        for (code, _) in Self.languages where code != "nl" {
            let url = dir.appendingPathComponent("\(code).json")
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                dicts[code] = obj.compactMapValues { $0 as? String }.filter { !$0.key.hasPrefix("_") }
            }
        }
    }

    static func isValid(_ code: String) -> Bool { languages.contains { $0.code == code } }

    func set(_ code: String) {
        guard Self.isValid(code), code != lang else { return }
        lang = code
        UserDefaults.standard.set(code, forKey: Self.defaultsKey)
        onChange?(code)
    }

    private var forceDutch = false
    func translate(_ s: String) -> String { forceDutch ? s : (dicts[lang]?[s] ?? s) }

    /// Namen uit de standaard-layout (Nederlands). Staat zo'n naam ongewijzigd in je eigen layout, dan toont de
    /// tablet hem in de gekozen taal; zelf bedachte namen blijven zoals je ze typte.
    private(set) lazy var builtInNames: Set<String> = {
        forceDutch = true
        defer { forceDutch = false }
        let l = Layout.default
        var names = Set(l.pages.map(\.name))
        for p in l.pages { for t in p.tiles { names.insert(t.label) } }
        for p in l.profiles ?? [] { names.insert(p.name) }
        return names
    }()

    /// Naam van een pagina, tegel of profiel voor de tablet.
    func displayName(_ s: String) -> String { builtInNames.contains(s) ? translate(s) : s }

    /// Het woordenboek voor de tablet en de editor (leeg voor Nederlands).
    var dictionary: [String: String] { dicts[lang] ?? [:] }

    var locale: Locale {
        switch lang {
        case "nl": return Locale(identifier: "nl_NL")
        case "es": return Locale(identifier: "es_ES")
        default: return Locale(identifier: "en_GB")
        }
    }

    /// Script voor `GET /i18n.js`: zet `CP_LANG` en `CP_I18N` voordat pad.js of editor.js start.
    func script() -> String {
        let data = (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])) ?? Data("{}".utf8)
        var json = String(decoding: data, as: UTF8.self)
        // Niet uit een <script> kunnen breken, ook al komen de teksten uit eigen bestanden.
        json = json.replacingOccurrences(of: "</", with: "<\\/")
        return "window.CP_LANG=\"\(lang)\";window.CP_I18N=\(json);\n"
    }
}

/// Vertaal een Nederlandse tekst. `{0}`, `{1}`… worden vervangen door de extra waarden.
func L(_ s: String, _ args: Any...) -> String {
    var out = Localizer.shared.translate(s)
    for (i, a) in args.enumerated() { out = out.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
    return out
}
