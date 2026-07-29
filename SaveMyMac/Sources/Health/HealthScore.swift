import Foundation

/// A factor making up the score, with its weight and a text explanation.
struct HealthFactor: Identifiable {
    var id: String { name }
    var name: String
    var detail: String
    /// 0...1, where 1 is ideal.
    var quality: Double
    var weight: Double

    var points: Double { quality * weight }
}

/// A 0–100 health score.
///
/// There is no "health score" in macOS — this is the app's own index. That is why
/// it is fully explainable: every factor appears in the interface with its weight
/// and the reason for its rating, so the number never looks like magic.
struct HealthReport {
    var score: Int
    var factors: [HealthFactor]

    var headline: String {
        switch score {
        case ..<50: return L("Your Mac is asking for help.")
        case ..<70: return L("There's a lot of room to improve.")
        case ..<85: return L("Your Mac is fine — and could be better.")
        default: return L("Your Mac is in great shape.")
        }
    }

    /// The worst factor, to suggest the next action.
    var weakest: HealthFactor? {
        factors.min { $0.quality < $1.quality }
    }
}

enum HealthScore {

    static func evaluate(
        bootVolume: VolumeInfo?,
        memory: MemorySnapshot,
        swap: SwapSnapshot,
        thermal: ThermalSnapshot,
        reclaimable: Int64,
        duplicateBytes: Int64,
        brokenLinks: Int
    ) -> HealthReport {

        var factors: [HealthFactor] = []

        // 1. Free space on the startup disk — the most important factor.
        //    Below 10% free, macOS genuinely starts to suffer.
        if let volume = bootVolume, volume.total > 0 {
            let freeFraction = Double(volume.available) / Double(volume.total)
            let quality = normalize(freeFraction, poor: 0.05, good: 0.25)
            factors.append(HealthFactor(
                name: L("Free space"),
                detail: L("%@ free of %@ (%@)", Fmt.bytes(volume.available), Fmt.bytes(volume.total), Fmt.percent(freeFraction)),
                quality: quality,
                weight: 34
            ))
        }

        // 2. Memory pressure. Wired + compressed is what really signals strain.
        let pressure = memory.pressureFraction
        factors.append(HealthFactor(
            name: L("Memory pressure"),
            detail: L("%@ · %@ in use of %@", memory.pressureLabel, Fmt.bytes(memory.used), Fmt.bytes(memory.total)),
            quality: normalize(1 - pressure, poor: 0.35, good: 0.7),
            weight: 18
        ))

        // 3. Swap in use: a sign the RAM isn't keeping up.
        let swapFraction = memory.total > 0 ? Double(swap.used) / Double(memory.total) : 0
        factors.append(HealthFactor(
            name: L("Swap usage"),
            detail: swap.used == 0
                ? L("No swap in use")
                : L("%@ in swap", Fmt.bytes(swap.used)),
            quality: normalize(1 - swapFraction * 4, poor: 0.4, good: 0.95),
            weight: 10
        ))

        // 4. Thermal state — Apple's official figure, always available.
        let thermalQuality: Double
        switch thermal.thermalState {
        case .nominal: thermalQuality = 1.0
        case .fair: thermalQuality = 0.72
        case .serious: thermalQuality = 0.35
        case .critical: thermalQuality = 0.0
        @unknown default: thermalQuality = 0.8
        }
        factors.append(HealthFactor(
            name: L("Temperature"),
            detail: thermal.displayTemperature.map { "\(thermal.thermalStateLabel) · \(Fmt.celsius($0))" }
                ?? thermal.thermalStateLabel,
            quality: thermalQuality,
            weight: 14
        ))

        // 5. How much junk has piled up, relative to the disk size.
        if let volume = bootVolume, volume.total > 0 {
            let junkFraction = Double(reclaimable) / Double(volume.total)
            factors.append(HealthFactor(
                name: L("Accumulated junk"),
                detail: reclaimable == 0
                    ? L("Nothing identified yet — run a scan")
                    : L("%@ reclaimable", Fmt.bytes(reclaimable)),
                quality: normalize(1 - junkFraction * 6, poor: 0.4, good: 0.95),
                weight: 14
            ))
        }

        // 6. Duplicates.
        factors.append(HealthFactor(
            name: L("Duplicates"),
            detail: duplicateBytes == 0 ? L("None found") : L("%@ in identical copies", Fmt.bytes(duplicateBytes)),
            quality: duplicateBytes == 0 ? 1.0 : normalize(1 - Double(duplicateBytes) / (20 * 1_073_741_824), poor: 0.3, good: 0.95),
            weight: 6
        ))

        // 7. Broken offload links: each one is an app that may fail.
        factors.append(HealthFactor(
            name: L("Offload links"),
            detail: brokenLinks == 0
                ? L("All healthy")
                : L("%d with problems", brokenLinks),
            quality: brokenLinks == 0 ? 1.0 : max(0, 1 - Double(brokenLinks) * 0.34),
            weight: 4
        ))

        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        let earned = factors.reduce(0) { $0 + $1.points }
        let score = totalWeight > 0 ? Int((earned / totalWeight * 100).rounded()) : 0

        return HealthReport(score: max(0, min(100, score)), factors: factors)
    }

    /// Mapeia um valor bruto para 0...1 com corte inferior e superior.
    private static func normalize(_ value: Double, poor: Double, good: Double) -> Double {
        guard good > poor else { return 0.5 }
        return ((value - poor) / (good - poor)).clamped(0, 1)
    }
}
