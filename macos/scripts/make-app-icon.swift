// Tekent het app-icoon van Cyberpad: lichtgrijs vlak met een oranje eendenkop van opzij.
// Gebruik: swift macos/scripts/make-app-icon.swift macos/Resources
//         iconutil -c icns macos/Resources/AppIcon.iconset -o macos/Resources/AppIcon.icns
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "macos/Resources")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Tekent op een canvas van 1024×1024 (macOS-raster: vlak van 824 px met afgeronde hoeken).
func draw() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    // Zachte schaduw onder het vlak
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowColor = NSColor(white: 0, alpha: 0.28)
    sh.shadowOffset = NSSize(width: 0, height: -12)
    sh.shadowBlurRadius = 24
    sh.set()
    rgb(0xDCDCE0).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Lichtgrijs verloop
    NSGradient(starting: rgb(0xF4F4F6), ending: rgb(0xD3D3D8))!.draw(in: shape, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()

    // Snavel eerst: de kop komt eroverheen, zodat de snavel netjes uit de kop lijkt te groeien.
    // Eendensnavel: plat en breed, overal ongeveer even hoog, met een ronde punt.
    let bill = NSBezierPath()
    bill.move(to: NSPoint(x: 590, y: 722))
    bill.curve(to: NSPoint(x: 830, y: 694), controlPoint1: NSPoint(x: 680, y: 714), controlPoint2: NSPoint(x: 765, y: 700))
    bill.curve(to: NSPoint(x: 838, y: 578), controlPoint1: NSPoint(x: 884, y: 688), controlPoint2: NSPoint(x: 890, y: 588))
    bill.curve(to: NSPoint(x: 590, y: 572), controlPoint1: NSPoint(x: 760, y: 562), controlPoint2: NSPoint(x: 670, y: 558))
    bill.close()
    NSGradient(starting: rgb(0xEC6A0C), ending: rgb(0xC84E04))!.draw(in: bill, angle: -90)

    // Hals met borst: kort en breed, loopt van de onderrand omhoog naar de kop.
    let neck = NSBezierPath()
    neck.move(to: NSPoint(x: 230, y: 40))
    neck.curve(to: NSPoint(x: 380, y: 580), controlPoint1: NSPoint(x: 250, y: 260), controlPoint2: NSPoint(x: 320, y: 460))
    neck.line(to: NSPoint(x: 610, y: 560))
    neck.curve(to: NSPoint(x: 700, y: 250), controlPoint1: NSPoint(x: 590, y: 450), controlPoint2: NSPoint(x: 700, y: 360))
    neck.curve(to: NSPoint(x: 660, y: 40), controlPoint1: NSPoint(x: 700, y: 160), controlPoint2: NSPoint(x: 680, y: 90))
    neck.close()

    // Kop: rond, iets breder dan hoog
    let head = NSBezierPath(ovalIn: NSRect(x: 320, y: 470, width: 380, height: 340))

    // Hals en kop elk apart vullen met hetzelfde verloop (geen naad of gat waar ze overlappen).
    let duckBounds = NSRect(x: 220, y: 40, width: 490, height: 780)
    let orange = NSGradient(colors: [rgb(0xFFB347), rgb(0xF7931E), rgb(0xE8780C)], atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
    for part in [neck, head] {
        NSGraphicsContext.saveGraphicsState()
        part.addClip()
        orange.draw(in: duckBounds, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Bekje (lijn tussen boven- en ondersnavel)
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: 700, y: 626))
    mouth.curve(to: NSPoint(x: 862, y: 628), controlPoint1: NSPoint(x: 760, y: 620), controlPoint2: NSPoint(x: 820, y: 618))
    mouth.lineWidth = 9
    mouth.lineCapStyle = .round
    rgb(0x9E3A02, 0.65).setStroke()
    mouth.stroke()
    // Neusgaatje
    rgb(0x9E3A02, 0.6).setFill()
    NSBezierPath(ovalIn: NSRect(x: 748, y: 672, width: 26, height: 14)).fill()

    // Glans op de kop
    rgb(0xFFFFFF, 0.22).setFill()
    NSBezierPath(ovalIn: NSRect(x: 390, y: 690, width: 180, height: 90)).fill()

    // Oog
    rgb(0x2A1A0C).setFill()
    NSBezierPath(ovalIn: NSRect(x: 540, y: 668, width: 62, height: 68)).fill()
    rgb(0xFFFFFF).setFill()
    NSBezierPath(ovalIn: NSRect(x: 564, y: 704, width: 19, height: 19)).fill()

    NSGraphicsContext.restoreGraphicsState()

    // Fijne rand rond het vlak
    rgb(0x000000, 0.08).setStroke()
    shape.lineWidth = 3
    shape.stroke()
}

func png(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    ctx.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let set = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for s in scales {
        let name = s == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        try! png(pt * s)!.write(to: set.appendingPathComponent(name))
    }
}
print("iconset klaar: \(set.path)")
