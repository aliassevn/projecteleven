import Foundation
import dnssd

/// Publiceert `cyberpad.local` via multicast DNS, zodat de tablet geen IP-adres hoeft te kennen.
final class HostAlias {
    let hostname: String
    private var conn: DNSServiceRef?
    private var published: [String] = []

    init(hostname: String = "cyberpad.local.") {
        self.hostname = hostname
    }

    /// Opnieuw publiceren als de IP-adressen veranderd zijn (bijv. ander wifi-netwerk).
    func update(ipv4s: [String]) {
        guard ipv4s != published else { return }
        stop()
        published = ipv4s
        guard !ipv4s.isEmpty else { return }

        var ref: DNSServiceRef?
        guard DNSServiceCreateConnection(&ref) == kDNSServiceErr_NoError, let ref else {
            NSLog("Cyberpad: mDNS-verbinding mislukt")
            return
        }
        conn = ref
        DNSServiceSetDispatchQueue(ref, .main)

        for ip in ipv4s {
            var addr = in_addr()
            guard inet_pton(AF_INET, ip, &addr) == 1 else { continue }
            var record: DNSRecordRef?
            let err = DNSServiceRegisterRecord(
                ref, &record, DNSServiceFlags(kDNSServiceFlagsShared), 0, hostname,
                UInt16(kDNSServiceType_A), UInt16(kDNSServiceClass_IN), 4, &addr, 120,
                { _, _, _, error, _ in
                    if error != kDNSServiceErr_NoError { NSLog("Cyberpad: mDNS-record fout %d", error) }
                }, nil)
            if err != kDNSServiceErr_NoError { NSLog("Cyberpad: kon %@ niet publiceren (%d)", ip, err) }
        }
    }

    func stop() {
        if let conn { DNSServiceRefDeallocate(conn) }
        conn = nil
        published = []
    }
}
