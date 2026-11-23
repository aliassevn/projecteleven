// Tekent de iconen voor "Zet op beginscherm" (shared/pad/icons). Gebruik: swift macos/scripts/make-pad-icons.swift
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "shared/pad/icons")
let cyan = NSColor(red: 0, green: 1, blue: 0.878, alpha: 1)
let magenta = NSColor(red: 1, green: 0.169, blue: 0.839, alpha: 1)

func icon(_ size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(red: 0.02, green: 0.024, blue: 0.04, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: s, height: s).fill()
    // 3×3 raster van tegels, één magenta (het "ingedrukte" knopje)
    let margin = s * 0.17, gap = s * 0.05
    let cell = (s - 2 * margin - 2 * gap) / 3
    for r in 0..<3 {
        for c in 0..<3 {
            let rect = NSRect(x: margin + CGFloat(c) * (cell + gap), y: margin + CGFloat(r) * (cell + gap), width: cell, height: cell)
            let on = (r == 2 && c == 2)
            let color = on ? magenta : cyan
            color.withAlphaComponent(on ? 0.35 : 0.08).setFill()
            rect.fill()
            color.setStroke()
            let p = NSBezierPath(rect: rect.insetBy(dx: s * 0.006, dy: s * 0.006))
            p.lineWidth = max(1, s * 0.012)
            p.stroke()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [180, 192, 512] {
    if let d = icon(size) {
        try! d.write(to: out.appendingPathComponent("icon-\(size).png"))
        print("icon-\(size).png")
    }
}
