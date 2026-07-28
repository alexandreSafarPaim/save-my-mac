import Foundation

/// Rastro de execução em arquivo, para diagnosticar o travamento.
///
/// Por que não `NSLog`/`os_log`: quando o app trava e é morto à força, o
/// subsistema de log unificado pode simplesmente não ter escrito nada — foi
/// exatamente o que aconteceu (`log show` voltou zero linhas). Aqui a escrita é
/// um `write(2)` cru, sem buffer de biblioteca, direto no descritor. O que foi
/// marcado está no disco no instante seguinte, mesmo que o processo morra em
/// seguida.
///
/// A ideia é simples e não depende de `sample` nem de palpite: cada ponto
/// suspeito marca a entrada e a saída. Quando o app congela, **a última linha
/// do arquivo é o lugar onde ele parou**.
///
/// Arquivo: ~/Library/Logs/SaveMyMac-trace.log
enum Trace {

    static let path = NSHomeDirectory() + "/Library/Logs/SaveMyMac-trace.log"

    private static let lock = NSLock()
    private static let start = Date()

    /// `O_TRUNC`: cada execução começa do zero. Um rastro que acumula sessões
    /// obriga a adivinhar onde uma termina e a outra começa.
    private static let fd: Int32 = {
        let dir = NSHomeDirectory() + "/Library/Logs"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    }()

    static func mark(_ text: @autoclosure () -> String) {
        guard fd >= 0 else { return }
        let elapsed = Date().timeIntervalSince(start)
        let where_ = Thread.isMainThread ? "MAIN" : "bg  "
        let line = String(format: "%8.3f [%@] %@\n", elapsed, where_, text())
        lock.lock()
        _ = line.withCString { write(fd, $0, strlen($0)) }
        lock.unlock()
    }

    /// Marca entrada e saída de um trecho, com a duração.
    /// Se a saída não aparecer no arquivo, foi ali que travou.
    @discardableResult
    static func span<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        mark("→ \(name)")
        let t0 = Date()
        defer { mark(String(format: "← %@ (%.0f ms)", name, Date().timeIntervalSince(t0) * 1000)) }
        return try work()
    }

    /// Conta algo que acontece muito e só registra de tempos em tempos.
    /// Serve para medir frequência sem inundar o arquivo.
    private static var counters: [String: Int] = [:]

    static func count(_ name: String, every: Int = 100) {
        lock.lock()
        let n = (counters[name] ?? 0) + 1
        counters[name] = n
        lock.unlock()
        // Fora do cadeado: `mark` também o usa e o NSLock não é reentrante.
        if n % every == 0 { mark("\(name): \(n)×") }
    }

    // MARK: - Cabeçalho

    /// Identifica **qual binário** está rodando. Já perdemos tempo depurando uma
    /// versão antiga instalada por engano; a data de modificação do executável
    /// resolve isso em uma linha.
    static func begin() {
        let exe = Bundle.main.executablePath ?? "?"
        let stamp = (try? FileManager.default.attributesOfItem(atPath: exe)[.modificationDate])
            .flatMap { $0 as? Date }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        mark("SaveMyMac iniciando — pid \(getpid())")
        mark("executável: \(exe)")
        mark("compilado em: \(stamp.map(fmt.string(from:)) ?? "desconhecido")")
        mark("modo seguro: \(SafeMode.isOn) · barra de menus: \(MenuBarFeature.isEnabled)")
    }

    // MARK: - Vigia da thread principal

    private static var lastPing = Date()
    private static var stalled = false

    /// Detecta quando a thread principal para de responder.
    ///
    /// A principal bate um ponto a cada 0,25 s pelo run loop. Uma thread comum,
    /// que não depende do run loop, confere. Se o ponto envelhece, a interface
    /// está congelada — e o rastro registra o instante exato, que cruzado com a
    /// última marca diz o que estava em curso.
    static func startWatchdog() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            lock.lock(); lastPing = Date(); lock.unlock()
        }

        Thread.detachNewThread {
            Thread.current.name = "savemymac.watchdog"
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                lock.lock()
                let age = Date().timeIntervalSince(lastPing)
                lock.unlock()

                if age > 3, !stalled {
                    stalled = true
                    mark(String(format: "⚠️  THREAD PRINCIPAL TRAVADA há %.1f s", age))
                } else if age < 1, stalled {
                    stalled = false
                    mark("✅ thread principal respondeu de novo")
                }
            }
        }
    }
}
