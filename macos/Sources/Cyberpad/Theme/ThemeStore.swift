import Foundation
import CryptoKit

/// Een thema (shared/themes/<id>.json). Zelfde formaat op macOS en Windows; zie docs/THEMES.md.
struct Theme: Codable, Equatable {
    var id: String
    var name: String
    var description: String?
    var colors: [String: String]
    var font: String
    var radius: Double
    var effects: [String: Bool]

    static let colorKeys = ["bg", "bg2", "text", "accent", "accent2", "accent2Text", "danger", "dangerText", "ok", "okText",
                            "panel", "panelBorder", "button", "buttonText", "buttonBorder", "buttonActive", "buttonActiveText"]

    /// Kleuren die een thema mag weglaten: dan zijn ze afgeleid van de andere (het oude uiterlijk).
    static func derived(_ c: [String: String]) -> [String: String] {
        func rgba(_ key: String, _ a: Double) -> String {
            guard let hex = c[key], hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return "transparent" }
            return "rgba(\(v >> 16 & 0xff),\(v >> 8 & 0xff),\(v & 0xff),\(a))"
        }
        var d = c
        if d["panel"] == nil { d["panel"] = rgba("accent", 0.04) }
        if d["panelBorder"] == nil { d["panelBorder"] = rgba("accent", 0.45) }
        if d["button"] == nil { d["button"] = d["panel"] }
        if d["buttonBorder"] == nil { d["buttonBorder"] = d["panelBorder"] }
        if d["buttonText"] == nil { d["buttonText"] = rgba("text", 0.75) }
        if d["buttonActive"] == nil { d["buttonActive"] = rgba("accent2", 0.12) }
        if d["buttonActiveText"] == nil { d["buttonActiveText"] = c["accent2Text"] ?? "inherit" }
        return d
    }
    static let effectKeys = ["scanlines", "glow", "grid", "corner", "glitch", "upper", "bold"]
}

/// Eigen aanpassingen bovenop een thema (thema-bouwer in de editor). Leeg = het thema zoals het is.
struct ThemeOverrides: Codable, Equatable {
    var colors: [String: String]?
    var font: String?
    var radius: Double?
    var effects: [String: Bool]?

    static func validColor(_ s: String) -> Bool { s.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }
    /// Alleen letters, cijfers, spaties, komma's, aanhalingstekens en streepjes: geen CSS-injectie.
    static func validFont(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 200 && s.range(of: "^[A-Za-z0-9 ,\"'\\-]+$", options: .regularExpression) != nil
    }

    func problems() -> [String] {
        var out: [String] = []
        for (k, v) in colors ?? [:] {
            if !Theme.colorKeys.contains(k) { out.append("Onbekende themakleur “\(k)”") }
            if !Self.validColor(v) { out.append("Kleur \(k) moet als #rrggbb") }
        }
        if let f = font, !Self.validFont(f) { out.append("Lettertype mag alleen letters, cijfers, spaties, komma's en aanhalingstekens bevatten") }
        if let r = radius, !(0...30).contains(r) { out.append("Afronding moet tussen 0 en 30 liggen") }
        for k in (effects ?? [:]).keys where !Theme.effectKeys.contains(k) { out.append("Onbekend effect “\(k)”") }
        return out
    }
}

/// Leest de thema's en maakt de tablet-CSS: het sjabloon shared/pad/pad.css met de kleuren ingevuld.
final class ThemeStore {
    let dir: URL
    private let template: URL
    private(set) var themes: [Theme] = []
    private var cache: (key: String, css: Data)?
    private var templateDate: Date?

    init(dir: URL, padDir: URL) {
        self.dir = dir
        template = padDir.appendingPathComponent("pad.css")
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        themes = files.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Theme.self, from: Data(contentsOf: $0)) }
            .sorted { a, b in a.id == "cyberdeck" || (b.id != "cyberdeck" && a.name < b.name) }
    }

    func base(_ id: String) -> Theme? { themes.first { $0.id == id } ?? themes.first { $0.id == "cyberdeck" } ?? themes.first }

    /// Thema uit de layout plus eigen aanpassingen.
    func resolve(_ l: Layout) -> Theme? {
        guard var t = base(l.theme) else { return nil }
        if let o = l.themeOverrides {
            for (k, v) in o.colors ?? [:] where Theme.colorKeys.contains(k) && ThemeOverrides.validColor(v) { t.colors[k] = v }
            if let f = o.font, ThemeOverrides.validFont(f) { t.font = f }
            if let r = o.radius, (0...30).contains(r) { t.radius = r }
            for (k, v) in o.effects ?? [:] where Theme.effectKeys.contains(k) { t.effects[k] = v }
        }
        return t
    }

    /// Klassen voor <html>: effecten die uit staan (fx-noscan…) of extra aan (fx-glitch, fx-upper).
    static func classes(_ t: Theme) -> String {
        var c: [String] = []
        if t.effects["scanlines"] != true { c.append("fx-noscan") }
        if t.effects["glow"] != true { c.append("fx-noglow") }
        if t.effects["grid"] != true { c.append("fx-nogrid") }
        if t.effects["corner"] != true { c.append("fx-nocorner") }
        if t.effects["glitch"] == true { c.append("fx-glitch") }
        if t.effects["upper"] == true { c.append("fx-upper") }
        if t.effects["bold"] == true { c.append("fx-bold") }
        return c.joined(separator: " ")
    }

    /// Korte sleutel die verandert als het uiterlijk verandert (de tablet laadt dan de CSS opnieuw).
    static func key(_ t: Theme) -> String {
        guard let d = try? JSONEncoder().encode(t) else { return "0" }
        return SHA256.hash(data: d).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    func css(for l: Layout) -> Data? {
        guard let t = resolve(l) else { return try? Data(contentsOf: template) }
        let mdate = (try? FileManager.default.attributesOfItem(atPath: template.path))?[.modificationDate] as? Date
        let key = Self.key(t) + "\(mdate?.timeIntervalSince1970 ?? 0)"
        if let c = cache, c.key == key { return c.css }
        guard let src = try? String(contentsOf: template, encoding: .utf8) else { return nil }
        let out = Self.render(src, t)
        let data = Data(out.utf8)
        cache = (key, data)
        return data
    }

    /// {{naam}} → waarde, {{kleur 0.4}} → rgba(r,g,b,0.4).
    static func render(_ src: String, _ theme: Theme) -> String {
        var t = theme
        t.colors = Theme.derived(theme.colors)
        guard let re = try? NSRegularExpression(pattern: "\\{\\{(\\w+)(?:\\s+([0-9.]+))?\\}\\}") else { return src }
        let ns = src as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: src, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let name = ns.substring(with: m.range(at: 1))
            let alpha = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : nil
            out += value(name, alpha, t)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    private static func value(_ name: String, _ alpha: String?, _ t: Theme) -> String {
        switch name {
        case "font": return t.font
        case "radius": return String(format: "%g", t.radius)
        default:
            guard let value = t.colors[name] else { return "transparent" }
            // Afgeleide kleuren zijn al rgba(…); die worden zonder extra doorzichtigheid gebruikt.
            guard value.count == 7, value.hasPrefix("#"), let v = UInt32(value.dropFirst(), radix: 16) else { return value }
            guard let a = alpha else { return value }
            return "rgba(\(v >> 16 & 0xff),\(v >> 8 & 0xff),\(v & 0xff),\(a))"
        }
    }
}
