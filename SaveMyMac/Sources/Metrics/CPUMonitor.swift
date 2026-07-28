import Foundation
import Darwin

struct CPUSnapshot {
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 0
    var nice: Double = 0

    var busy: Double { (user + system + nice).clamped(0, 1) }

    var loadAverage: [Double] = [0, 0, 0]
    var processCount: Int = 0
    var threadCount: Int = 0
}

/// Lê o uso agregado de CPU comparando os "ticks" entre duas amostras.
final class CPUMonitor {

    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    init() {
        // Amostra inicial para que a primeira leitura já tenha uma base de comparação.
        _ = read()
    }

    func read() -> CPUSnapshot {
        var snap = CPUSnapshot()

        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, intPtr, &count)
            }
        }

        if kr == KERN_SUCCESS {
            let current = (
                user: info.cpu_ticks.0,
                system: info.cpu_ticks.1,
                idle: info.cpu_ticks.2,
                nice: info.cpu_ticks.3
            )

            if let prev = previousTicks {
                let dUser = Double(current.user &- prev.user)
                let dSystem = Double(current.system &- prev.system)
                let dIdle = Double(current.idle &- prev.idle)
                let dNice = Double(current.nice &- prev.nice)
                let total = dUser + dSystem + dIdle + dNice

                if total > 0 {
                    snap.user = dUser / total
                    snap.system = dSystem / total
                    snap.idle = dIdle / total
                    snap.nice = dNice / total
                }
            }

            previousTicks = current
        }

        snap.loadAverage = CPUMonitor.loadAverage()
        let counts = CPUMonitor.taskCounts()
        snap.processCount = counts.processes
        snap.threadCount = counts.threads

        return snap
    }

    static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 { return loads }
        return [0, 0, 0]
    }

    static func taskCounts() -> (processes: Int, threads: Int) {
        // Contagem de processos via sysctl KERN_PROC_ALL
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return (0, 0) }

        let entrySize = MemoryLayout<kinfo_proc>.stride
        let capacity = size / entrySize + 16
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        var actual = capacity * entrySize

        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return sysctl(&mib, 4, base, &actual, nil, 0) == 0
        }
        guard ok else { return (0, 0) }

        return (actual / entrySize, 0)
    }
}
