import Foundation
import AppKit
import IOKit

struct SensorReading: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var celsius: Double
}

struct ThermalSnapshot {
    /// Apple's official thermal state — always available, no password.
    var thermalState: ProcessInfo.ThermalState = .nominal

    /// Per-sensor temperature readings (may be empty depending on model/macOS).
    var sensors: [SensorReading] = []

    /// Best estimate of the CPU/SoC temperature.
    var cpuTemperature: Double?

    var gpuTemperature: Double?

    /// Battery temperature (a reliable fallback on laptops).
    var batteryTemperature: Double?

    /// Fan RPM, when available.
    var fans: [Int] = []

    /// Where the data came from, to show in the interface.
    var source: String = "—"

    var thermalStateLabel: String {
        switch thermalState {
        case .nominal: return L("Normal")
        case .fair: return L("Warming up")
        case .serious: return L("Hot")
        case .critical: return L("Critical")
        @unknown default: return L("Unknown")
        }
    }

    /// Best available temperature to show on the main card.
    var displayTemperature: Double? {
        cpuTemperature ?? sensors.map(\.celsius).max() ?? batteryTemperature
    }
}

enum ThermalMonitor {

    // MARK: - Main read (no password)

    static func read() -> ThermalSnapshot {
        var snap = ThermalSnapshot()
        snap.thermalState = ProcessInfo.processInfo.thermalState

        // 1) Sensors through IOHID (works on Apple Silicon with no password, when available)
        let hidSensors = HIDSensors.readTemperatureSensors()
        if !hidSensors.isEmpty {
            snap.sensors = hidSensors.sorted { $0.celsius > $1.celsius }
            snap.cpuTemperature = bestCPU(from: hidSensors)
            snap.gpuTemperature = bestGPU(from: hidSensors)
            snap.fans = HIDSensors.readFanSpeeds()
            snap.source = L("IOHID sensors")
        }

        // 2) Battery — almost always available on laptops
        let battery = BatteryMonitor.read()
        snap.batteryTemperature = battery.temperature

        if snap.cpuTemperature == nil {
            if snap.batteryTemperature != nil {
                snap.source = L("Battery sensor (CPU unavailable without privileges)")
            } else {
                snap.source = L("System thermal state only")
            }
        }

        return snap
    }

    // MARK: - Elevated read (asks for a password once)

    /// Runs `powermetrics` with administrator privileges. Returns nil if the
    /// user cancels, or if the command exposes no temperatures on this Mac.
    static func readElevated() -> ThermalSnapshot? {
        let command = "/usr/bin/powermetrics --samplers smc,thermal -n 1 -i 800 2>/dev/null"
        guard let output = runWithAdminPrivileges(command), !output.isEmpty else { return nil }

        var snap = read()
        var found = false

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.contains(":") else { continue }
            let parts = line.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]

            if key.contains("cpu die temperature"), let v = firstDouble(in: value) {
                snap.cpuTemperature = v
                found = true
            } else if key.contains("gpu die temperature"), let v = firstDouble(in: value) {
                snap.gpuTemperature = v
                found = true
            } else if key.hasPrefix("fan"), let v = firstDouble(in: value) {
                snap.fans.append(Int(v))
                found = true
            } else if key.contains("temperature"), let v = firstDouble(in: value), v > 5, v < 130 {
                snap.sensors.append(SensorReading(name: parts[0], celsius: v))
                found = true
            }
        }

        guard found else { return nil }
        snap.sensors.sort { $0.celsius > $1.celsius }
        snap.source = L("powermetrics (administrator)")
        return snap
    }

    // MARK: - Helpers

    /// Extracts the first number from a string like "45.12 C" or "1998 rpm".
    ///
    /// Accepts a comma as the decimal separator: on a Portuguese Mac,
    /// powermetrics prints "45,12 C", and stopping at the first non-numeric
    /// character would return 45 instead of 45.12.
    private static func firstDouble(in text: String) -> Double? {
        var buffer = ""
        for char in text {
            if char.isNumber || char == "." || char == "," || (char == "-" && buffer.isEmpty) {
                buffer.append(char == "," ? "." : char)
            } else if !buffer.isEmpty {
                break
            }
        }
        return Double(buffer)
    }

    private static func bestCPU(from sensors: [SensorReading]) -> Double? {
        let keywords = ["tdie", "tcal", "pacc", "eacc", "cpu", "soc", "die"]
        let matches = sensors.filter { sensor in
            let lower = sensor.name.lowercased()
            return keywords.contains { lower.contains($0) }
        }
        guard !matches.isEmpty else { return sensors.map(\.celsius).max() }
        return matches.map(\.celsius).max()
    }

    private static func bestGPU(from sensors: [SensorReading]) -> Double? {
        let matches = sensors.filter { $0.name.lowercased().contains("gpu") }
        return matches.map(\.celsius).max()
    }

    /// Runs a shell command with administrator privileges.
    /// Uses `osascript` in a separate process (NSAppleScript is not thread-safe),
    /// so macOS shows the native password dialog without hanging the app.
    static func runWithAdminPrivileges(_ command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        // We do NOT force the locale here: the password dialog belongs to the
        // system and should stay in the user's language. powermetrics output is
        // handled by `firstDouble`, which accepts a comma.
        return ProcessMonitor.shell("/usr/bin/osascript", ["-e", source])
    }
}

// MARK: - IOHID sensors (private API, with safe degradation)

/// Reaches the temperature/fan sensors through IOHIDEventSystemClient.
/// Every symbol is resolved at runtime with `dlsym`, so if Apple changes or
/// removes the API the app simply shows no temperatures instead of failing.
enum HIDSensors {

    private static let kHIDPageAppleVendor: Int = 0xff00
    private static let kHIDUsageTemperatureSensor: Int = 0x0005
    private static let kHIDUsageFan: Int = 0x000a
    private static let kIOHIDEventTypeTemperature: Int64 = 15
    private static let kIOHIDEventTypeFan: Int64 = 16

    private typealias CreateClientFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchingFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<AnyObject>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatValueFn = @convention(c) (AnyObject, Int32) -> Double

    private struct Symbols {
        var createClient: CreateClientFn
        var setMatching: SetMatchingFn
        var copyServices: CopyServicesFn
        var copyProperty: CopyPropertyFn
        var copyEvent: CopyEventFn
        var getFloatValue: GetFloatValueFn
    }

    private static let symbols: Symbols? = loadSymbols()

    private static func loadSymbols() -> Symbols? {
        let path = "/System/Library/Frameworks/IOKit.framework/IOKit"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }

        func sym(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(handle, name)
        }

        guard
            let create = sym("IOHIDEventSystemClientCreate"),
            let match = sym("IOHIDEventSystemClientSetMatching"),
            let services = sym("IOHIDEventSystemClientCopyServices"),
            let property = sym("IOHIDServiceClientCopyProperty"),
            let event = sym("IOHIDServiceClientCopyEvent"),
            let floatValue = sym("IOHIDEventGetFloatValue")
        else { return nil }

        return Symbols(
            createClient: unsafeBitCast(create, to: CreateClientFn.self),
            setMatching: unsafeBitCast(match, to: SetMatchingFn.self),
            copyServices: unsafeBitCast(services, to: CopyServicesFn.self),
            copyProperty: unsafeBitCast(property, to: CopyPropertyFn.self),
            copyEvent: unsafeBitCast(event, to: CopyEventFn.self),
            getFloatValue: unsafeBitCast(floatValue, to: GetFloatValueFn.self)
        )
    }

    static func readTemperatureSensors() -> [SensorReading] {
        readSensors(
            usage: kHIDUsageTemperatureSensor,
            eventType: kIOHIDEventTypeTemperature
        ).compactMap { entry in
            guard entry.value > 5, entry.value < 150 else { return nil }
            return SensorReading(name: entry.name, celsius: entry.value)
        }
    }

    static func readFanSpeeds() -> [Int] {
        readSensors(usage: kHIDUsageFan, eventType: kIOHIDEventTypeFan)
            .map { Int($0.value) }
            .filter { $0 > 0 }
    }

    // MARK: - Persistent session
    //
    // The previous version called `IOHIDEventSystemClientCreate` **on every
    // read**. Since `ThermalMonitor.read()` reads temperature and fans, and ran
    // on the 2-second cycle, the app opened two new HID clients every 2 s — over
    // three thousand per hour.
    //
    // That is not an ordinary memory leak. An IOHIDEventSystemClient is not a
    // local object: creating one registers a client with `hidd`, the daemon that
    // delivers keyboard and mouse to the entire system, with mach ports and a
    // matching notification. Creating and tearing down thousands of them
    // overloads `hidd` — and when `hidd` chokes, **the whole Mac freezes**, not
    // just this app. That was the "everything hangs".
    //
    // The client is now created once per sensor type and lives as long as the app
    // does, which is how this API was meant to be used.

    private final class Session {
        let client: AnyObject
        let services: NSArray
        init(client: AnyObject, services: NSArray) {
            self.client = client
            self.services = services
        }
    }

    /// Serialises the *reads* as well: a single shared client should not receive
    /// concurrent calls, and the cost is irrelevant because there is only one
    /// reader every few seconds.
    private static let lock = NSLock()
    private static var sessions: [Int: Session?] = [:]

    private static func session(for usage: Int, _ s: Symbols) -> Session? {
        // `sessions[usage]` is `Session??`: the outer value says "already
        // tried", the inner one says "succeeded". Without that distinction, a Mac
        // with no sensors would try to create the client again on every read —
        // exactly the behaviour we are eliminating.
        if let attempted = sessions[usage] { return attempted }

        Trace.mark("HID usage \(usage): CREATING client (should happen exactly once)")
        let made: Session? = {
            guard let clientRef = s.createClient(kCFAllocatorDefault) else { return nil }
            let client = clientRef.takeRetainedValue()
            let matching: [String: Int] = [
                "PrimaryUsagePage": kHIDPageAppleVendor,
                "PrimaryUsage": usage
            ]
            s.setMatching(client, matching as CFDictionary)
            guard let servicesRef = s.copyServices(client) else { return nil }
            let services = unsafeBitCast(servicesRef.takeRetainedValue(), to: NSArray.self)
            return Session(client: client, services: services)
        }()

        sessions[usage] = made
        NSLog("[SaveMyMac] HID sensors (usage \(usage)): \(made?.services.count ?? -1) service(s).")
        return made
    }

    private static func readSensors(usage: Int, eventType: Int64) -> [(name: String, value: Double)] {
        guard let s = symbols else { return [] }

        Trace.mark("HID usage \(usage): waiting for lock")
        lock.lock()
        defer { lock.unlock() }

        guard let session = session(for: usage, s) else { return [] }
        Trace.mark("HID usage \(usage): \(session.services.count) service(s), reading events")

        let field = Int32(truncatingIfNeeded: eventType << 16)
        var results: [(name: String, value: Double)] = []

        for element in session.services {
            let service = element as AnyObject

            var name = "Sensor"
            if let nameRef = s.copyProperty(service, "Product" as CFString) {
                if let str = nameRef.takeRetainedValue() as? String {
                    name = str
                }
            }

            guard let eventRef = s.copyEvent(service, eventType, 0, 0) else { continue }
            let event = eventRef.takeRetainedValue()
            let value = s.getFloatValue(event, field)
            results.append((name: name, value: value))
        }

        return results
    }
}
