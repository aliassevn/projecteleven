import Foundation
import CryptoKit

/// Minimale WebSocket-implementatie (RFC 6455) voor de server-kant. Werkt ook met Safari op iOS 9.
enum WebSocket {
    static let maxPayload = 64 * 1024

    enum Opcode: UInt8 {
        case continuation = 0x0, text = 0x1, binary = 0x2, close = 0x8, ping = 0x9, pong = 0xA
    }

    struct Frame {
        var fin: Bool
        var opcode: Opcode
        var payload: Data
    }

    enum ParseError: Error { case protocolError, tooLarge }

    static func acceptKey(for key: String) -> String {
        let magic = key.trimmingCharacters(in: .whitespaces) + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        return Data(Insecure.SHA1.hash(data: Data(magic.utf8))).base64EncodedString()
    }

    /// Leest één frame uit de buffer. Geeft nil als er nog niet genoeg data is.
    static func parse(_ buf: inout Data) throws -> Frame? {
        let b = [UInt8](buf.prefix(14))
        guard b.count >= 2 else { return nil }
        let fin = (b[0] & 0x80) != 0
        guard (b[0] & 0x70) == 0, let op = Opcode(rawValue: b[0] & 0x0F) else { throw ParseError.protocolError }
        let masked = (b[1] & 0x80) != 0
        guard masked else { throw ParseError.protocolError } // clients moeten maskeren

        var len = Int(b[1] & 0x7F)
        var offset = 2
        if len == 126 {
            guard b.count >= 4 else { return nil }
            len = Int(b[2]) << 8 | Int(b[3])
            offset = 4
        } else if len == 127 {
            guard b.count >= 10 else { return nil }
            var l: UInt64 = 0
            for i in 2..<10 { l = l << 8 | UInt64(b[i]) }
            guard l <= UInt64(maxPayload) else { throw ParseError.tooLarge }
            len = Int(l)
            offset = 10
        }
        guard len <= maxPayload else { throw ParseError.tooLarge }
        guard buf.count >= offset + 4 + len else { return nil }

        let start = buf.startIndex
        let mask = [UInt8](buf[(start + offset)..<(start + offset + 4)])
        var payload = [UInt8](buf[(start + offset + 4)..<(start + offset + 4 + len)])
        for i in 0..<payload.count { payload[i] ^= mask[i % 4] }
        buf.removeFirst(offset + 4 + len)
        return Frame(fin: fin, opcode: op, payload: Data(payload))
    }

    /// Bouwt een (ongemaskeerd) server-frame.
    static func encode(_ op: Opcode, _ payload: Data) -> Data {
        var out = Data([0x80 | op.rawValue])
        let n = payload.count
        if n < 126 {
            out.append(UInt8(n))
        } else if n <= 0xFFFF {
            out.append(126)
            out.append(UInt8(n >> 8)); out.append(UInt8(n & 0xFF))
        } else {
            out.append(127)
            for i in (0..<8).reversed() { out.append(UInt8((UInt64(n) >> (UInt64(i) * 8)) & 0xFF)) }
        }
        out.append(payload)
        return out
    }
}
