import Foundation
import Darwin

struct MemorySnapshot {
    var total: UInt64 = 0
    var app: UInt64 = 0          // L("App memory") no Monitor de Atividade
    var wired: UInt64 = 0        // memória travada pelo kernel
    var compressed: UInt64 = 0   // memória comprimida
    var cached: UInt64 = 0       // arquivos em cache (liberável)
    var free: UInt64 = 0

    var used: UInt64 { app &+ wired &+ compressed }
    var available: UInt64 { total > used ? total - used : 0 }

    /// 0.0 ... 1.0
    var usedFraction: Double {
        total == 0 ? 0 : Double(used) / Double(total)
    }

    /// An approximation of Activity Monitor's "memory pressure".
    var pressureFraction: Double {
        total == 0 ? 0 : Double(wired &+ compressed) / Double(total)
    }

    var pressureLabel: String {
        switch pressureFraction {
        case ..<0.35: return L("Normal")
        case ..<0.60: return L("Moderate")
        default: return L("High")
        }
    }
}

struct SwapSnapshot {
    var total: UInt64 = 0
    var used: UInt64 = 0
    var free: UInt64 = 0
    var encrypted: Bool = false
}

enum MemoryMonitor {

    static func read() -> MemorySnapshot {
        var snap = MemorySnapshot()
        snap.total = ProcessInfo.processInfo.physicalMemory

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return snap }

        let pageSize = UInt64(vm_page_size)

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0

        snap.app = appPages * pageSize
        snap.wired = UInt64(stats.wire_count) * pageSize
        snap.compressed = UInt64(stats.compressor_page_count) * pageSize
        snap.cached = UInt64(stats.external_page_count) * pageSize
        snap.free = UInt64(stats.free_count) * pageSize

        return snap
    }

    static func readSwap() -> SwapSnapshot {
        var snap = SwapSnapshot()
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            snap.total = usage.xsu_total
            snap.used = usage.xsu_used
            snap.free = usage.xsu_avail
            snap.encrypted = usage.xsu_encrypted != 0
        }
        return snap
    }
}
