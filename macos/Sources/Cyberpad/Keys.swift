import Foundation
import CoreGraphics

/// Toetscombinaties ("cmd+shift+a") omzetten en versturen, en tekst typen. Vereist Toegankelijkheid.
enum Keys {
    struct Combo: Equatable {
        var code: CGKeyCode
        var flags: CGEventFlags
    }

    enum KeyError: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let s) = self { return L("Onbekende toetscombinatie: {0}", s) }
            return nil
        }
    }

    /// Virtuele toetscodes (fysieke positie, Amerikaanse indeling — gelijk aan US-International).
    static let codes: [String: CGKeyCode] = {
        var m: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
            "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
            "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
            "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
            "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
            "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
            "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
            "plus": 24, "minus": 27,
        ]
        let fkeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        for (i, c) in fkeys.enumerated() { m["f\(i + 1)"] = c }
        return m
    }()

    static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand,
        "shift": .maskShift, "⇧": .maskShift,
        "alt": .maskAlternate, "option": .maskAlternate, "opt": .maskAlternate, "⌥": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    static func parse(_ s: String) throws -> Combo {
        let parts = s.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        // "cmd++" → laatste deel is een plus-teken
        let tokens = s.hasSuffix("++") ? parts.filter { !$0.isEmpty } + ["plus"] : parts
        guard let keyName = tokens.last, !keyName.isEmpty else { throw KeyError.invalid(s) }
        var flags: CGEventFlags = []
        for m in tokens.dropLast() {
            guard let f = modifiers[m] else { throw KeyError.invalid(s) }
            flags.insert(f)
        }
        guard let code = codes[keyName] else { throw KeyError.invalid(s) }
        // Pijltjes en F-toetsen horen de fn/numpad-vlag te hebben, anders negeren sommige apps ze.
        if (123...126).contains(Int(code)) { flags.insert([.maskSecondaryFn, .maskNumericPad]) }
        return Combo(code: code, flags: flags)
    }

    static func press(_ combo: Combo) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: combo.code, keyDown: down)
            e?.flags = combo.flags
            e?.post(tap: .cghidEventTap)
        }
    }

    static let maxTextLength = 2000

    /// Typt tekst als Unicode, onafhankelijk van de toetsenbordindeling.
    static func type(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.prefix(maxTextLength).utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + 20, units.count)])
            for down in [true, false] {
                let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
                e?.flags = [] // geen ingedrukte modifiers meesturen
                chunk.withUnsafeBufferPointer { buf in
                    e?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
                }
                e?.post(tap: .cghidEventTap)
            }
            i += 20
        }
    }
}
