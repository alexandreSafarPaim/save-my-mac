import Foundation
import IOKit

struct BatterySnapshot {
    var present: Bool = false
    var charge: Double = 0            // 0...1
    var isCharging: Bool = false
    var isPluggedIn: Bool = false
    var cycleCount: Int = 0
    var designCycleCount: Int = 0
    var health: Double = 0             // 0...1 (capacidade máxima / de projeto)
    var temperature: Double?           // °C
    var voltage: Double?               // V
    var amperage: Double?              // A (negativo = descarregando)
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?

    var healthLabel: String {
        switch health {
        case 0: return "—"
        case ..<0.80: return "Substituir em breve"
        case ..<0.90: return "Boa"
        default: return "Normal"
        }
    }

    var powerLabel: String {
        if !present { return "Sem bateria (desktop)" }
        if isCharging { return "Carregando" }
        if isPluggedIn { return "Na tomada" }
        return "Na bateria"
    }
}

enum BatteryMonitor {

    static func read() -> BatterySnapshot {
        var snap = BatterySnapshot()

        guard let props = registryProperties(serviceName: "AppleSmartBattery") else {
            // Desktop: verifica se está na tomada
            snap.isPluggedIn = true
            return snap
        }

        snap.present = (props["BatteryInstalled"] as? Bool) ?? true
        snap.isCharging = (props["IsCharging"] as? Bool) ?? false
        snap.isPluggedIn = (props["ExternalConnected"] as? Bool) ?? false

        let current = intValue(props["CurrentCapacity"]) ?? 0
        let maxCap = intValue(props["MaxCapacity"]) ?? 0
        let design = intValue(props["DesignCapacity"]) ?? 0

        // Em Apple Silicon "CurrentCapacity" já é percentual (0-100).
        if maxCap == 100 || maxCap == 0 {
            snap.charge = Double(current) / 100.0
        } else {
            snap.charge = Double(current) / Double(max(1, maxCap))
        }

        // Capacidade real para saúde
        let rawMax = intValue(props["AppleRawMaxCapacity"])
            ?? intValue(props["NominalChargeCapacity"])
            ?? maxCap
        if design > 0 && rawMax > 0 && rawMax != 100 {
            snap.health = min(1.0, Double(rawMax) / Double(design))
        }

        snap.cycleCount = intValue(props["CycleCount"]) ?? 0
        snap.designCycleCount = intValue(props["DesignCycleCount9C"]) ?? 0

        // Temperatura da bateria vem em centésimos de grau Celsius.
        if let raw = intValue(props["Temperature"]), raw > 0 {
            snap.temperature = Double(raw) / 100.0
        }
        if let mv = intValue(props["Voltage"]), mv > 0 {
            snap.voltage = Double(mv) / 1000.0
        }
        if let ma = intValue(props["Amperage"]) {
            snap.amperage = Double(ma) / 1000.0
        }
        if let t = intValue(props["TimeRemaining"]), t > 0, t < 60_000 {
            if snap.isCharging { snap.timeToFullMinutes = t } else { snap.timeToEmptyMinutes = t }
        }
        if let t = intValue(props["AvgTimeToEmpty"]), t > 0, t < 60_000, !snap.isCharging {
            snap.timeToEmptyMinutes = t
        }
        if let t = intValue(props["AvgTimeToFull"]), t > 0, t < 60_000, snap.isCharging {
            snap.timeToFullMinutes = t
        }

        return snap
    }

    // MARK: - Helpers

    static func registryProperties(serviceName: String) -> [String: Any]? {
        guard let matching = IOServiceMatching(serviceName) else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        let kr = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard kr == KERN_SUCCESS, let dict = unmanaged?.takeRetainedValue() else { return nil }
        return dict as? [String: Any]
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? Int { return n }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}
