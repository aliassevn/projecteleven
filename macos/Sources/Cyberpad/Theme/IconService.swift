import AppKit
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Iconen als afbeelding: `app:<bundle-id>` (het icoon van een app op deze Mac) of `img:<naam>.png`
/// (eigen afbeelding, geüpload via de editor en bewaard in Application Support/Cyberpad/Icons).
final class IconService {
    let dir: URL
    private var appCache: [String: Data] = [:]   // sleutel: bundle-id@formaat
    static let maxUpload = 700 * 1024
    static let size = 256

    init(supportDir: URL) {
        dir = supportDir.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    static func validImageName(_ s: String) -> Bool { s.range(of: "^[0-9a-f]{16}\\.png$", options: .regularExpression) != nil }
    static func validBundleID(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9.\\-]{1,200}$", options: .regularExpression) != nil }

    /// Zoekt een icoon op voor `src` ("app:…" of "img:…").
    func png(_ src: String, size: Int = IconService.size) -> Data? {
        if src.hasPrefix("app:") { return appIcon(String(src.dropFirst(4)), px: min(max(size, 16), Self.size)) }
        if src.hasPrefix("img:") {
            let name = String(src.dropFirst(4))
            guard Self.validImageName(name) else { return nil }
            return try? Data(contentsOf: dir.appendingPathComponent(name))
        }
        return nil
    }

    private func appIcon(_ bundle: String, px: Int) -> Data? {
        guard Self.validBundleID(bundle) else { return nil }
        let key = "\(bundle)@\(px)"
        if let d = appCache[key] { return d }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let s = CGFloat(px)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        NSGraphicsContext.restoreGraphicsState()
        let d = rep.representation(using: .png, properties: [:])
        if let d { appCache[key] = d }
        return d
    }

    /// Eigen afbeelding opslaan: verkleind tot max. 256 px, altijd als PNG. Geeft "img:<naam>" terug.
    func store(_ raw: Data) throws -> String {
        guard raw.count <= Self.maxUpload else { throw ActionRunner.ActionError.failed(L("Afbeelding te groot (max. 700 KB)")) }
        guard let src = CGImageSourceCreateWithData(raw as CFData, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.size,
              ] as CFDictionary) else {
            throw ActionRunner.ActionError.failed(L("Dit is geen afbeelding die Cyberpad kan lezen"))
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw ActionRunner.ActionError.failed(L("Kon de afbeelding niet omzetten"))
        }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw ActionRunner.ActionError.failed(L("Kon de afbeelding niet omzetten")) }
        let png = out as Data
        let name = SHA256.hash(data: png).prefix(8).map { String(format: "%02x", $0) }.joined() + ".png"
        try png.write(to: dir.appendingPathComponent(name), options: .atomic)
        return "img:" + name
    }
}
