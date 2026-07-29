import Foundation
import AppKit
import IOKit

struct SensorReading: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var celsius: Double
}

struct ThermalSnapshot {
    /// Estado térmico oficial da Apple — sempre disponível, sem senha.
    var thermalState: ProcessInfo.ThermalState = .nominal

    /// Temperaturas lidas por sensor (pode vir vazio dependendo do modelo/macOS).
    var sensors: [SensorReading] = []

    /// Melhor estimativa da temperatura da CPU/SoC.
    var cpuTemperature: Double?

    var gpuTemperature: Double?

    /// Temperatura da bateria (fallback confiável em notebooks).
    var batteryTemperature: Double?

    /// RPM das ventoinhas, se disponível.
    var fans: [Int] = []

    /// Origem dos dados, para mostrar na interface.
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

    /// Melhor temperatura disponível para exibir no card principal.
    var displayTemperature: Double? {
        cpuTemperature ?? sensors.map(\.celsius).max() ?? batteryTemperature
    }
}

enum ThermalMonitor {

    // MARK: - Leitura principal (sem senha)

    static func read() -> ThermalSnapshot {
        var snap = ThermalSnapshot()
        snap.thermalState = ProcessInfo.processInfo.thermalState

        // 1) Sensores via IOHID (funciona em Apple Silicon sem senha, quando disponível)
        let hidSensors = HIDSensors.readTemperatureSensors()
        if !hidSensors.isEmpty {
            snap.sensors = hidSensors.sorted { $0.celsius > $1.celsius }
            snap.cpuTemperature = bestCPU(from: hidSensors)
            snap.gpuTemperature = bestGPU(from: hidSensors)
            snap.fans = HIDSensors.readFanSpeeds()
            snap.source = L("IOHID sensors")
        }

        // 2) Bateria — quase sempre disponível em notebooks
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

    // MARK: - Leitura elevada (pede senha uma vez)

    /// Roda `powermetrics` com privilégios de administrador. Retorna nil se o
    /// usuário cancelar ou se o comando não expuser temperaturas neste Mac.
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

    /// Extrai o primeiro número de uma string como "45.12 C" ou "1998 rpm".
    ///
    /// Aceita vírgula como separador decimal: num Mac em português o
    /// powermetrics imprime "45,12 C", e parar no primeiro caractere não
    /// numérico devolveria 45 em vez de 45,12.
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

    /// Executa um comando shell com privilégios de administrador.
    /// Usa `osascript` num processo separado (NSAppleScript não é thread-safe),
    /// então o macOS mostra o diálogo nativo de senha sem travar o app.
    static func runWithAdminPrivileges(_ command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        // Aqui NÃO forçamos locale: o diálogo de senha é do sistema e deve
        // continuar no idioma do usuário. A saída do powermetrics é tratada
        // pelo `firstDouble`, que aceita vírgula.
        return ProcessMonitor.shell("/usr/bin/osascript", ["-e", source])
    }
}

// MARK: - Sensores IOHID (API privada, com degradação segura)

/// Acessa os sensores de temperatura/ventoinha via IOHIDEventSystemClient.
/// Todos os símbolos são resolvidos em tempo de execução com `dlsym`, então se
/// a Apple mudar/remover a API o app simplesmente não mostra temperaturas
/// em vez de falhar.
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

    // MARK: - Sessão persistente
    //
    // A versão anterior chamava `IOHIDEventSystemClientCreate` **a cada
    // leitura**. Como `ThermalMonitor.read()` lê temperatura e ventoinha, e
    // rodava no ciclo de 2 segundos, o app abria dois clientes HID novos a cada
    // 2 s — mais de três mil por hora.
    //
    // Isso não é um vazamento comum de memória. Um IOHIDEventSystemClient não é
    // um objeto local: criá-lo registra um cliente no `hidd`, o daemon que
    // entrega teclado e mouse para o sistema inteiro, com portas mach e
    // notificação de correspondência. Criar e destruir milhares deles
    // sobrecarrega o `hidd` — e quando o `hidd` engasga, **o Mac inteiro
    // congela**, não só este app. Era esse o "trava tudo".
    //
    // Agora o cliente é criado uma vez por tipo de sensor e vive enquanto o app
    // viver, que é como essa API foi feita para ser usada.

    private final class Session {
        let client: AnyObject
        let services: NSArray
        init(client: AnyObject, services: NSArray) {
            self.client = client
            self.services = services
        }
    }

    /// Serializa também as *leituras*: um único cliente compartilhado não deve
    /// receber chamadas concorrentes, e o custo é irrelevante porque só existe
    /// um leitor a cada poucos segundos.
    private static let lock = NSLock()
    private static var sessions: [Int: Session?] = [:]

    private static func session(for usage: Int, _ s: Symbols) -> Session? {
        // `sessions[usage]` é `Session??`: o valor externo diz "já tentei",
        // o interno diz "consegui". Sem essa distinção, um Mac sem sensores
        // tentaria criar o cliente de novo a cada leitura — exatamente o
        // comportamento que estamos eliminando.
        if let attempted = sessions[usage] { return attempted }

        Trace.mark("HID usage \(usage): CRIANDO cliente (deve acontecer uma única vez)")
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
        NSLog("[SaveMyMac] Sensores HID (usage \(usage)): \(made?.services.count ?? -1) serviço(s).")
        return made
    }

    private static func readSensors(usage: Int, eventType: Int64) -> [(name: String, value: Double)] {
        guard let s = symbols else { return [] }

        Trace.mark("HID usage \(usage): aguardando cadeado")
        lock.lock()
        defer { lock.unlock() }

        guard let session = session(for: usage, s) else { return [] }
        Trace.mark("HID usage \(usage): \(session.services.count) serviço(s), lendo eventos")

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
