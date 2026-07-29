import Foundation
import AppKit

struct ProcessInfoRow: Identifiable, Hashable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var memoryBytes: Int64
    /// Dono do processo. `nil` quando o `ps` não devolveu a coluna.
    var uid: Int32?
    /// Caminho do bundle, quando o processo é um app com interface — permite
    /// mostrar o ícone real e o nome que o usuário reconhece.
    var bundlePath: String?

    var isApp: Bool { bundlePath != nil }
}

enum ProcessMonitor {

    /// Por que a última leitura falhou. Existe para a interface poder dizer o
    /// motivo em vez de renderizar um card vazio.
    private static let failureLock = NSLock()
    private static var storedFailure: String?

    static var lastFailure: String? {
        failureLock.lock()
        defer { failureLock.unlock() }
        return storedFailure
    }

    private static func setFailure(_ reason: String?) {
        failureLock.lock()
        storedFailure = reason
        failureLock.unlock()
    }

    /// Top processos por CPU e por memória, via `ps`.
    static func top(limit: Int = 8) -> (byCPU: [ProcessInfoRow], byMemory: [ProcessInfoRow]) {
        let rows = allProcesses()
        let byCPU = Array(rows.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
        let byMemory = Array(rows.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
        return (byCPU, byMemory)
    }

    static func allProcesses() -> [ProcessInfoRow] {
        // Três formas de chamar o `ps`. A primeira usa `=` para suprimir o
        // cabeçalho; as outras servem de rede de segurança, porque o parse
        // ignora qualquer linha cujo primeiro campo não seja um número — o
        // cabeçalho cai fora sozinho.
        let attempts: [[String]] = [
            ["-axo", "pid=,pcpu=,rss=,uid=,comm="],
            ["-axo", "pid,pcpu,rss,uid,comm"],
            ["-axo", "pid=,pcpu=,rss=,comm="],
            ["-Ao", "pid,pcpu,rss,comm"]
        ]

        var lastError = ""
        for arguments in attempts {
            let outcome = run("/bin/ps", arguments, forceCLocale: true)
            if outcome.status != 0 {
                lastError = outcome.error.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            let rows = parse(outcome.output)
            if !rows.isEmpty {
                setFailure(nil)
                return rows
            }
        }

        setFailure(
            lastError.isEmpty
                ? L("/bin/ps answered, but no line could be parsed.")
                : L("Failed to run /bin/ps: %@", lastError)
        )
        return []
    }

    /// Resolve nome localizado e bundle das linhas exibidas.
    ///
    /// Precisa rodar na thread principal: mexe com AppKit. São ~12 consultas,
    /// não as centenas que uma resolução no parse faria.
    @MainActor
    static func enrich(_ rows: [ProcessInfoRow]) -> [ProcessInfoRow] {
        rows.map { row in
            guard let info = ProcessController.appInfo(for: row.pid) else { return row }
            var copy = row
            copy.name = info.name
            copy.bundlePath = info.bundlePath
            return copy
        }
    }

    /// Converte número aceitando ponto **ou** vírgula como separador decimal.
    /// Segunda camada de defesa: o LC_ALL=C já deveria garantir o ponto, mas
    /// custa três linhas não depender disso.
    static func decimal(_ text: Substring) -> Double? {
        if let value = Double(text) { return value }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Interpreta a saída do `ps`, pulando cabeçalho e linhas malformadas.
    ///
    /// Aceita os dois formatos: com a coluna `uid` (5 campos) e sem ela (4).
    /// Distingue os dois pelo 4º campo — se for um inteiro puro é o uid, porque
    /// nenhum caminho de comando é só dígitos.
    static func parse(_ output: String) -> [ProcessInfoRow] {
        var rows: [ProcessInfoRow] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = ProcessMonitor.decimal(parts[1]),
                  let rss = Int64(parts[2]) else { continue }

            var uid: Int32?
            var commandStart = 3
            if parts.count >= 5, let parsed = Int32(parts[3]) {
                uid = parsed
                commandStart = 4
            }

            let commandPath = parts[commandStart...].joined(separator: " ")
            let fallbackName = (commandPath as NSString).lastPathComponent

            // O nome bonito e o ícone NÃO são resolvidos aqui de propósito:
            // `NSRunningApplication` é AppKit, esta função roda em thread de
            // fundo, e resolver para centenas de processos a cada 2 s seria
            // caro e de segurança de thread duvidosa. Quem enriquece é
            // `enrich(_:)`, chamado só para as linhas que vão à tela.
            rows.append(ProcessInfoRow(
                pid: pid,
                name: fallbackName.isEmpty ? "pid \(pid)" : fallbackName,
                cpuPercent: cpu,
                memoryBytes: rss * 1024,
                uid: uid,
                bundlePath: nil
            ))
        }

        return rows
    }

    /// Executa um comando e devolve status, stdout e stderr.
    /// Necessário quando o código de saída importa — `shell` sozinho não
    /// distingue "rodou e não imprimiu nada" de "falhou".
    ///
    /// `forceCLocale` existe por um motivo concreto: utilitários BSD formatam
    /// números com o separador decimal do sistema. Num Mac em português o `ps`
    /// imprime `%CPU` como "0,0", e `Double("0,0")` devolve nil — o que fazia
    /// TODA linha ser descartada e o card de processos ficar vazio. Com LC_ALL=C
    /// a saída é sempre "0.0". Também estabiliza o formato de data do `mdls`.
    static func run(
        _ launchPath: String,
        _ arguments: [String],
        forceCLocale: Bool = false
    ) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        if forceCLocale {
            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C"
            env["LANG"] = "C"
            process.environment = env
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        Trace.mark("exec \(launchPath) \(arguments.joined(separator: " "))")
        do {
            try process.run()
        } catch {
            Trace.mark("exec falhou: \(error.localizedDescription)")
            return (-1, "", error.localizedDescription)
        }
        defer { Trace.mark("exec \(launchPath) terminou") }

        // Os dois canos são esvaziados **em paralelo**.
        //
        // Ler stdout até o fim e só depois stderr parece inofensivo e não é: o
        // buffer de um pipe tem 64 KB. Se o filho encher o de stderr enquanto o
        // pai ainda espera o fim do stdout, o filho bloqueia na escrita, nunca
        // fecha o stdout, e o pai espera para sempre. É um impasse silencioso —
        // nada trava, nada falha, a thread simplesmente some.
        //
        // Com uma tarefa por cano nenhum dos dois pode segurar o outro.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let sink = DispatchQueue(label: "savemymac.pipe-drain")

        for (handle, isOut) in [(outPipe.fileHandleForReading, true),
                                (errPipe.fileHandleForReading, false)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                sink.async {
                    if isOut { outData = data } else { errData = data }
                    group.leave()
                }
            }
        }

        group.wait()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    static func shell(_ launchPath: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
