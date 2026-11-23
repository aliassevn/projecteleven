import Foundation
import Network

/// Hulpfuncties voor netwerkadressen: eigen IP's vinden en controleren of een verbinding uit het lokale netwerk komt.
enum NetUtil {
    struct Interface {
        let name: String
        let ipv4: String?
        let ipv6Prefix: Data? // eerste 8 bytes (/64)
    }

    /// Alle actieve, niet-loopback interfaces met hun adressen.
    static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            defer { ptr = p.pointee.ifa_next }
            let flags = Int32(p.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, let sa = p.pointee.ifa_addr else { continue }
            let name = String(cString: p.pointee.ifa_name)
            // Alleen echte netwerkinterfaces (Wi-Fi / ethernet), geen VPN-tunnels of AWDL.
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            if sa.pointee.sa_family == UInt8(AF_INET) {
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
                let ip = String(cString: buf)
                if !ip.hasPrefix("169.254.") {
                    result.append(Interface(name: name, ipv4: ip, ipv6Prefix: nil))
                }
            } else if sa.pointee.sa_family == UInt8(AF_INET6) {
                let bytes = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p -> Data in
                    var a = p.pointee.sin6_addr
                    return Data(bytes: &a, count: 16)
                }
                if bytes[0] != 0xfe { // geen link-local
                    result.append(Interface(name: name, ipv4: nil, ipv6Prefix: bytes.prefix(8)))
                }
            }
        }
        return result
    }

    /// IPv4-adressen van deze Mac, en0 (meestal Wi-Fi) eerst.
    static func localIPv4s() -> [String] {
        let all = interfaces().compactMap { i -> (String, String)? in
            guard let ip = i.ipv4 else { return nil }
            return (i.name, ip)
        }
        let sorted = all.sorted { a, b in
            if a.0 == "en0" { return true }
            if b.0 == "en0" { return false }
            return a.0 < b.0
        }
        var seen = Set<String>()
        return sorted.map { $0.1 }.filter { seen.insert($0).inserted }
    }

    /// True als het adres loopback, privé (RFC 1918), link-local of in hetzelfde IPv6-/64-net valt.
    static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a):
            return isLocalIPv4(a)
        case .ipv6(let a):
            if let v4 = a.asIPv4 { return isLocalIPv4(v4) }
            if a.isLoopback || a.isLinkLocal { return true }
            let raw = a.rawValue
            if (raw[0] & 0xfe) == 0xfc { return true } // unique local fc00::/7
            let prefix = raw.prefix(8)
            return interfaces().contains { $0.ipv6Prefix == prefix }
        default:
            return false
        }
    }

    private static func isLocalIPv4(_ a: IPv4Address) -> Bool {
        if a.isLoopback || a.isLinkLocal { return true }
        let b = [UInt8](a.rawValue)
        switch b[0] {
        case 10: return true
        case 172: return (16...31).contains(b[1])
        case 192: return b[1] == 168
        default: return false
        }
    }

    /// Alleen deze Mac zelf (127.0.0.1 / ::1).
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let a): return a.isLoopback
        case .ipv6(let a): return a.isLoopback || (a.asIPv4?.isLoopback ?? false)
        default: return false
        }
    }

    static func describe(_ endpoint: NWEndpoint) -> String {
        if case let .hostPort(host, _) = endpoint {
            switch host {
            case .ipv4(let a): return "\(a)"
            case .ipv6(let a): return a.asIPv4.map { "\($0)" } ?? "\(a)"
            case .name(let n, _): return n
            @unknown default: return "?"
            }
        }
        return "?"
    }
}
