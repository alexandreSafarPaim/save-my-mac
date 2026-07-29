import Foundation

/// A snapshot of the memory state at one instant.
struct MemorySample: Identifiable {
    let id = UUID()
    var at: Date
    /// 0...1 — wired + compressed over the total. This is the curve that matters.
    var pressure: Double
    /// 0...1 — memory in use over the total.
    var used: Double
    var swapBytes: Int64
}

/// Keeps the last few minutes of memory pressure.
///
/// It exists because an instantaneous number doesn't answer the question the user
/// actually has. "Pressure: moderate" right now says nothing; "green for the last
/// half hour" says more RAM wouldn't help today, and "red for ten minutes" says
/// something is out of control.
struct MemoryHistory {

    /// 2 s por amostra × 450 = 15 minutos.
    static let capacity = 450

    private(set) var samples: [MemorySample] = []

    mutating func record(memory: MemorySnapshot, swap: SwapSnapshot) {
        samples.append(MemorySample(
            at: Date(),
            pressure: memory.pressureFraction,
            used: memory.usedFraction,
            swapBytes: Int64(clamping: swap.used)
        ))
        if samples.count > MemoryHistory.capacity {
            samples.removeFirst(samples.count - MemoryHistory.capacity)
        }
    }

    var pressureCurve: [Double] { samples.map(\.pressure) }

    var span: TimeInterval {
        guard let first = samples.first?.at, let last = samples.last?.at else { return 0 }
        return last.timeIntervalSince(first)
    }

    var peakPressure: Double { samples.map(\.pressure).max() ?? 0 }

    /// A text summary of the observed period.
    var verdict: String? {
        guard samples.count >= 10 else { return nil }
        let minutes = Int(span / 60)
        let window = minutes >= 1 ? "\(minutes) min" : "\(Int(span)) s"

        if peakPressure < 0.35 {
            return L("Low pressure over the last %@ — more RAM would change nothing today.", window)
        }
        if peakPressure < 0.60 {
            return L("Pressure reached %@ over the last %@.", Fmt.percent(peakPressure), window)
        }
        return L("High pressure (peak of %@) over the last %@ — something is squeezing the RAM.", Fmt.percent(peakPressure), window)
    }
}

// MARK: - Crescimento por processo

/// Tracks each process's usage across the session to point out which one keeps
/// growing — the leak symptom an instantaneous number hides.
struct GrowthTracker {

    private struct Record {
        var firstSeen: Date
        var firstBytes: Int64
        var lastBytes: Int64
    }

    private var records: [Int32: Record] = [:]

    /// Needs a minimum observation window so it doesn't accuse an app that just
    /// launched and naturally grew while loading.
    private let minimumObservation: TimeInterval = 150
    private let minimumGrowth: Int64 = 250 * 1024 * 1024
    private let minimumRatio: Double = 1.5

    mutating func update(with rows: [ProcessInfoRow]) {
        let now = Date()
        var seen = Set<Int32>()

        for row in rows {
            seen.insert(row.pid)
            if var record = records[row.pid] {
                record.lastBytes = row.memoryBytes
                records[row.pid] = record
            } else {
                records[row.pid] = Record(
                    firstSeen: now,
                    firstBytes: row.memoryBytes,
                    lastBytes: row.memoryBytes
                )
            }
        }

        // A dead process leaves the map, otherwise the dictionary grows forever
        // and a recycled pid would inherit another's history.
        records = records.filter { seen.contains($0.key) }
    }

    /// How much the process has grown since it was first seen, if the growth is
    /// significant.
    func growth(for pid: Int32) -> Int64? {
        guard let record = records[pid] else { return nil }
        guard Date().timeIntervalSince(record.firstSeen) >= minimumObservation else { return nil }

        let delta = record.lastBytes - record.firstBytes
        guard delta >= minimumGrowth else { return nil }
        guard record.firstBytes > 0,
              Double(record.lastBytes) / Double(record.firstBytes) >= minimumRatio else { return nil }

        return delta
    }

    func isGrowing(_ pid: Int32) -> Bool {
        growth(for: pid) != nil
    }
}
