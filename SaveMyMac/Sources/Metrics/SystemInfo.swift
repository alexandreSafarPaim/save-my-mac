import Foundation
import Darwin
import IOKit

struct SystemInfoSnapshot {
    var modelName: String = "Mac"
    var modelIdentifier: String = "—"
    var chip: String = "—"
    var architecture: String = "—"
    var physicalCores: Int = 0
    var logicalCores: Int = 0
    var performanceCores: Int = 0
    var efficiencyCores: Int = 0
    var totalMemory: UInt64 = 0
    var osVersion: String = "—"
    var osBuild: String = "—"
    var hostName: String = "—"
    var uptime: TimeInterval = 0
    var serialNumber: String = "—"
}

enum SystemInfo {

    static func read() -> SystemInfoSnapshot {
        var info = SystemInfoSnapshot()

        info.modelIdentifier = sysctlString("hw.model") ?? "—"
        info.chip = sysctlString("machdep.cpu.brand_string") ?? "—"
        info.architecture = machineArchitecture()
        info.physicalCores = sysctlInt("hw.physicalcpu") ?? 0
        info.logicalCores = sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
        info.performanceCores = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        info.efficiencyCores = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        info.totalMemory = ProcessInfo.processInfo.physicalMemory
        info.hostName = ProcessInfo.processInfo.hostName
        info.uptime = uptimeSeconds()

        let os = ProcessInfo.processInfo.operatingSystemVersion
        info.osVersion = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        info.osBuild = sysctlString("kern.osversion") ?? "—"

        info.modelName = marketingName() ?? info.modelIdentifier
        info.serialNumber = serial() ?? "—"

        return info
    }

    // MARK: - sysctl helpers

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }
        guard let text = String(data: Data(bytes), encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lê um inteiro respeitando o tamanho real do sysctl (4 ou 8 bytes).
    static func sysctlInt(_ name: String) -> Int? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        if size == 4 {
            var value: Int32 = 0
            var length = 4
            guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
            return Int(value)
        }

        var value: Int64 = 0
        var length = 8
        guard sysctlbyname(name, &value, &length, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static func uptimeSeconds() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &boot, &size, nil, 0) == 0, boot.tv_sec != 0 else {
            return ProcessInfo.processInfo.systemUptime
        }
        let bootDate = Date(timeIntervalSince1970: Double(boot.tv_sec))
        return Date().timeIntervalSince(bootDate)
    }

    static func machineArchitecture() -> String {
        #if arch(arm64)
        return "arm64 (Apple Silicon)"
        #elseif arch(x86_64)
        return "x86_64 (Intel)"
        #else
        return "desconhecida"
        #endif
    }

    // MARK: - IORegistry

    /// Nome comercial ("MacBook Pro (14-inch, 2023)"), quando o firmware o expõe.
    static func marketingName() -> String? {
        guard let matching = IOServiceMatching("IOPlatformExpertDevice") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        // A chave varia entre modelos/idiomas.
        for key in ["product-name", "model", "target-type"] {
            if let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0),
               let data = ref.takeRetainedValue() as? Data {
                let text = SystemInfo.decodeCString(data)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    static func serial() -> String? {
        guard let matching = IOServiceMatching("IOPlatformExpertDevice") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let ref = IORegistryEntryCreateCFProperty(
            service, kIOPlatformSerialNumberKey as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return ref.takeRetainedValue() as? String
    }

    /// Converte Data terminada em NUL (formato do IORegistry) para String.
    static func decodeCString(_ data: Data) -> String {
        let bytes = data.prefix { $0 != 0 }
        return String(data: Data(bytes), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
