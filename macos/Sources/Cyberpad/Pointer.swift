import AppKit
import CoreGraphics

/// Muis en scrollen vanaf een aanraakpad-tegel. Werkt alleen als er zo'n tegel in de layout staat
/// (de server controleert dat), en vereist Toegankelijkheid.
final class PointerController {
    private var dragging = false
    private var lastClick = (time: Date.distantPast, count: 0)

    /// Scherm-rechthoek waarin de muis mag (alle schermen samen), in CG-coördinaten (oorsprong linksboven).
    private static func bounds() -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &n) == .success, n > 0 else { return CGDisplayBounds(CGMainDisplayID()) }
        return ids.prefix(Int(n)).map { CGDisplayBounds($0) }.reduce(CGRect.null) { $0.union($1) }
    }

    private static func location() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// Beweging met lichte versnelling: langzaam = precies, snel = ver.
    func move(dx: Double, dy: Double, speed: Double) {
        guard dx.isFinite, dy.isFinite else { return }
        let v = (dx * dx + dy * dy).squareRoot()
        let accel = 1 + min(v / 12, 2.5)
        let f = min(max(speed, 0.2), 5) * accel
        let b = Self.bounds()
        var p = Self.location()
        p.x = min(max(p.x + CGFloat(dx * f), b.minX), b.maxX - 1)
        p.y = min(max(p.y + CGFloat(dy * f), b.minY), b.maxY - 1)
        let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    func click(right: Bool) {
        let p = Self.location()
        // Dubbelklik herkennen zoals een echte muis (binnen de systeeminstelling).
        let now = Date()
        let count = right ? 1 : (now.timeIntervalSince(lastClick.time) < NSEvent.doubleClickInterval ? min(lastClick.count + 1, 3) : 1)
        if !right { lastClick = (now, count) }
        let (down, up, button): (CGEventType, CGEventType, CGMouseButton) =
            right ? (.rightMouseDown, .rightMouseUp, .right) : (.leftMouseDown, .leftMouseUp, .left)
        for t in [down, up] {
            let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: button)
            e?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Slepen: knop ingedrukt houden tot `up`.
    func button(down: Bool) {
        guard down != dragging else { return }
        dragging = down
        let p = Self.location()
        CGEvent(mouseEventSource: nil, mouseType: down ? .leftMouseDown : .leftMouseUp,
                mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Scrollen in pixels; `natural` = inhoud volgt je vingers (zoals een trackpad).
    func scroll(dx: Double, dy: Double, natural: Bool) {
        guard dx.isFinite, dy.isFinite else { return }
        let s: Double = natural ? 1 : -1
        let y = Int32(max(min(dy * s, 2000), -2000)), x = Int32(max(min(dx * s, 2000), -2000))
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    /// Losgelaten zonder `up` (verbinding weg): knop niet ingedrukt laten hangen.
    func release() { if dragging { button(down: false) } }
}
