import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fotoslideshow uit een map op de Mac. Foto's worden verkleind (max. 1280 px) zodat oude iPads ze vlot tonen.
final class PhotoService {
    static let defaultFolder = "~/Pictures/Cyberpad"
    static let extensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "webp"]
    static let maxPixels = 1280

    private var listings: [String: (at: Date, files: [URL], error: String?)] = [:]
    private var cache: [String: Data] = [:]
    private var cacheOrder: [String] = []
    private let queue = DispatchQueue(label: "cyberpad.photos")

    static func folderURL(_ cfg: WidgetConfig?) -> URL {
        let raw = cfg?.folder ?? defaultFolder
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
    }

    /// Bestandenlijst, hoogstens eens per minuut opnieuw gelezen.
    private func files(_ cfg: WidgetConfig?) -> (files: [URL], error: String?) {
        let dir = Self.folderURL(cfg)
        if let l = listings[dir.path], Date().timeIntervalSince(l.at) < 60 { return (l.files, l.error) }
        var problem: String?
        var files: [URL] = []
        do {
            files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles])
                .filter { Self.extensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            if files.isEmpty { problem = "Zet foto's in \(Self.display(dir))" }
        } catch {
            problem = "Map \(Self.display(dir)) bestaat niet"
        }
        listings[dir.path] = (Date(), files, problem)
        return (files, problem)
    }

    static func display(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    func json(for cfg: WidgetConfig?) -> [String: Any] {
        let l = files(cfg)
        var d: [String: Any] = ["count": l.files.count, "interval": min(max(cfg?.seconds ?? 10, 3), 3600)]
        if let e = l.error { d["error"] = e }
        return d
    }

    /// JPEG van foto nummer `index` (rondgaand). Alleen bestanden uit de lijst, dus geen vrije paden.
    func image(for cfg: WidgetConfig?, index: Int, done: @escaping (Data?) -> Void) {
        let l = files(cfg)
        guard !l.files.isEmpty else { done(nil); return }
        let url = l.files[((index % l.files.count) + l.files.count) % l.files.count]
        if let d = cache[url.path] { done(d); return }
        queue.async {
            let data = Self.thumbnail(url)
            DispatchQueue.main.async {
                if let data { self.remember(url.path, data) }
                done(data)
            }
        }
    }

    private func remember(_ key: String, _ data: Data) {
        cache[key] = data
        cacheOrder.append(key)
        if cacheOrder.count > 12 { cache[cacheOrder.removeFirst()] = nil }
    }

    private static func thumbnail(_ url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // EXIF-draaiing toepassen
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
