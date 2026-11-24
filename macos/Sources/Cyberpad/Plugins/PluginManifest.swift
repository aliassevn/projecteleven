import Foundation
import CryptoKit

/// `plugin.json`: beschrijft een plugin. Hetzelfde formaat voor macOS en Windows (zie docs/PLUGINS.md).
struct PluginManifest: Codable, Equatable {
    struct Param: Codable, Equatable {
        var id: String
        var name: String?
        var type: String?          // string, number, bool
        var `default`: JSONValue?
    }
    struct ActionDef: Codable, Equatable {
        var id: String
        var name: String
        var description: String?
        var params: [Param]?
    }
    struct WidgetDef: Codable, Equatable {
        var id: String
        var name: String
        var description: String?
        var params: [Param]?
        /// Hoe vaak Cyberpad om nieuwe gegevens vraagt (seconden, standaard 10).
        var interval: Int?
    }

    var id: String
    var name: String
    var version: String?
    var description: String?
    var author: String?
    var icon: String?
    /// Opdracht per platform: "macos", "windows" of "default". Bijv. ["/usr/bin/python3", "plugin.py"].
    var run: [String: [String]]
    var actions: [ActionDef]?
    var widgets: [WidgetDef]?

    static let platform = "macos"

    var command: [String]? {
        let c = run[Self.platform] ?? run["default"]
        return (c?.isEmpty == false) ? c : nil
    }

    static func validID(_ s: String) -> Bool {
        s.range(of: "^[a-z0-9][a-z0-9-]{0,39}$", options: .regularExpression) != nil
    }

    func validate() throws {
        guard Self.validID(id) else { throw PluginError.invalid(L("id “{0}” mag alleen a-z, 0-9 en - bevatten", id)) }
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw PluginError.invalid(L("naam ontbreekt")) }
        guard command != nil else { throw PluginError.invalid(L("geen opdracht in `run` voor macOS")) }
        for a in actions ?? [] where !Self.validID(a.id) { throw PluginError.invalid(L("ongeldige actie-id “{0}”", a.id)) }
        for w in widgets ?? [] where !Self.validID(w.id) { throw PluginError.invalid("ongeldige widget-id “\(w.id)”") }
    }
}

enum PluginError: LocalizedError {
    case invalid(String), failed(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let s): return "plugin.json: \(s)"
        case .failed(let s): return s
        }
    }
}

enum PluginHash {
    static let maxFiles = 500
    static let maxBytes = 20 << 20

    /// Vingerafdruk van alle bestanden in de pluginmap. Verandert er iets, dan moet je de plugin opnieuw toestaan.
    static func of(_ dir: URL) throws -> String {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                     options: [.skipsHiddenFiles]) else { throw PluginError.failed(L("Map niet leesbaar")) }
        var files: [(String, URL)] = []
        let base = dir.standardizedFileURL.path
        for case let url as URL in en {
            let name = url.lastPathComponent
            if name == "__pycache__" { en.skipDescendants(); continue }
            if name.hasSuffix(".pyc") { continue }
            let v = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if v.isSymbolicLink == true { files.append((String(url.standardizedFileURL.path.dropFirst(base.count)), url)); continue }
            guard v.isRegularFile == true else { continue }
            files.append((String(url.standardizedFileURL.path.dropFirst(base.count)), url))
            if files.count > maxFiles { throw PluginError.failed(L("Te veel bestanden in de plugin (max. {0})", maxFiles)) }
        }
        var h = SHA256()
        var total = 0
        for (rel, url) in files.sorted(by: { $0.0 < $1.0 }) {
            h.update(data: Data(rel.utf8)); h.update(data: Data([0]))
            if let dest = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                h.update(data: Data("link:\(dest)".utf8))
            } else {
                let d = try Data(contentsOf: url)
                total += d.count
                if total > maxBytes { throw PluginError.failed(L("Plugin is te groot (max. 20 MB)")) }
                h.update(data: d)
            }
            h.update(data: Data([0]))
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
