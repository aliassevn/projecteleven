import Foundation
import IOKit
import IOKit.ps

/// CPU, geheugen, netwerk en batterijen (ook van toetsenbord/muis/trackpad).
final class SystemStats {
    private var lastTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastNet: (rx: UInt64, tx: UInt64, at: Date)?
    private(set) var current: [String: Any] = [:]
    private var lastAccessories: (at: Date, list: [[String: Any]]) = (.distantPast, [])

    func sample() {
        var out: [String: Any] = [:]
        if let c = cpu() { out["cpu"] = c }
        if let m = memory() { out["ram"] = m }
        if let n = network() { out["net"] = n }
        if let b = battery() { out["battery"] = b }
        // Accessoires veranderen langzaam; eens per minuut is genoeg.
        if Date().timeIntervalSince(lastAccessories.at) > 60 { lastAccessories = (Date(), accessories()) }
        if !lastAccessories.list.isEmpty { out["accessories"] = lastAccessories.list }
        current = out
    }

    // MARK: CPU

    private func cpu() -> Int? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = (user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                 idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
        defer { lastTicks = t }
        guard let l = lastTicks else { return nil }
        let busy = Double((t.user &- l.user) + (t.system &- l.system) + (t.nice &- l.nice))
        let total = busy + Double(t.idle &- l.idle)
        return total > 0 ? Int((busy / total * 100).rounded()) : nil
    }

    // MARK: Geheugen

    private func memory() -> [String: Any]? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        // Zoals Activiteitenweergave "gebruikt geheugen": app-geheugen + vast + gecomprimeerd.
        let app = UInt64(stats.internal_page_count) > UInt64(stats.purgeable_count)
            ? UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count) : 0
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        let total = ProcessInfo.processInfo.physicalMemory
        return ["used": used, "total": total, "percent": Int((Double(used) / Double(total) * 100).rounded())]
    }

    // MARK: Netwerk

    private func network() -> [String: Any]? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var rx: UInt64 = 0, tx: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let sa = i.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), let d = i.pointee.ifa_data else { continue }
            let name = String(cString: i.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let data = d.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(data.ifi_ibytes)
            tx += UInt64(data.ifi_obytes)
        }
        let now = Date()
        defer { lastNet = (rx, tx, now) }
        guard let l = lastNet, rx >= l.rx, tx >= l.tx else { return nil } // eerste meting of teller rondgelopen
        let dt = now.timeIntervalSince(l.at)
        guard dt > 0.2 else { return nil }
        return ["down": Int(Double(rx - l.rx) / dt), "up": Int(Double(tx - l.tx) / dt)]
    }

    // MARK: Batterij

    private func battery() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return ["percent": Int((Double(cur) / Double(max) * 100).rounded()),
                    "charging": d[kIOPSIsChargingKey] as? Bool ?? false,
                    "plugged": d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue]
        }
        return nil
    }

    /// Magic Keyboard, Mouse en Trackpad melden hun batterij via IOKit.
    private func accessories() -> [[String: Any]] {
        var out: [[String: Any]] = []
        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iter) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iter) }
        var seen = Set<String>()
        while case let s = IOIteratorNext(iter), s != 0 {
            defer { IOObjectRelease(s) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(s, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let d = props?.takeRetainedValue() as? [String: Any],
                  let pct = d["BatteryPercent"] as? Int, let name = d["Product"] as? String,
                  seen.insert(name).inserted else { continue }
            out.append(["name": name, "percent": pct])
        }
        return out
    }
}
