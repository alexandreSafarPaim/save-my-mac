import Foundation
import ServiceManagement

/// Abrir no login.
///
/// Duas mecânicas, e a razão de existirem as duas importa:
///
/// - `SMAppService.mainApp` é a API correta no macOS 13+. Aparece em Ajustes do
///   Sistema › Geral › Itens de Início e o usuário pode desativar por lá. Mas
///   ela **exige assinatura de código válida** e o app estar em `/Applications`.
///   Este projeto assina ad-hoc, então o registro pode falhar.
///
/// - `LaunchAgent` (um plist em `~/Library/LaunchAgents`) é o mecanismo antigo,
///   funciona sem assinatura e é o que salva o caso ad-hoc.
///
/// A ordem é: tenta a moderna, cai para a antiga, e a interface **diz qual está
/// em uso** em vez de fingir que é tudo igual.
enum LaunchAtLogin {

    enum Mechanism: String {
        case serviceManagement
        case launchAgent
        case none

        var label: String {
            switch self {
            case .serviceManagement: return "Itens de Início do sistema"
            case .launchAgent: return "LaunchAgent do usuário"
            case .none: return "desativado"
            }
        }
    }

    private static let agentLabel = "br.com.pentagrama.savemymac.launcher"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    // MARK: - Estado
    //
    // ┌─────────────────────────────────────────────────────────────────────┐
    // │ NADA AQUI PODE SER LIDO DE DENTRO DE UM `init` DE VIEW.             │
    // └─────────────────────────────────────────────────────────────────────┘
    //
    // `SMAppService.status` parece um getter de propriedade e não é: cada
    // leitura faz uma ida e volta **síncrona** por XPC até o `smd`, o daemon de
    // Service Management. Numa thread principal isso é I/O bloqueante disfarçado
    // de acesso a campo.
    //
    // Foi exatamente assim que o app travou. O `SettingsView` inicializava
    // `@State` com `LaunchAtLogin.isEnabled` e `.statusDescription`. Como o
    // SwiftUI constrói o conteúdo da cena `Settings` a cada avaliação do corpo
    // do App — mesmo com a janela de Ajustes fechada, mesmo sem ela nunca ter
    // sido aberta —, e como o corpo do App é invalidado a cada `@Published` do
    // `AppState`, o app disparava duas chamadas XPC síncronas por atualização,
    // dezenas por segundo. O `smd` entupiu, parou de responder, e a thread
    // principal ficou presa em `mach_msg`. O spindump mostrou o caminho inteiro:
    //
    //     SaveMyMacApp.body.getter → Settings.init(content:) → SettingsView.init()
    //       → LaunchAtLogin.isEnabled → SMAppService.status → mach_msg
    //       (blocked by turnstile waiting for smd)
    //
    // A correção é a leitura virar **cache mais atualização assíncrona**: a
    // interface lê um valor em memória, de graça, e o XPC acontece fora da
    // thread principal, só quando alguém pede.

    struct Snapshot {
        var enabled = false
        var mechanism = Mechanism.none
        var description = "Verificando…"
        /// Falso até a primeira consulta terminar, para a interface poder
        /// mostrar que ainda não sabe em vez de mentir "desativado".
        var isKnown = false
    }

    private static let cacheLock = NSLock()
    private static var cache = Snapshot()

    /// Leitura instantânea, sem XPC. É o que a interface deve usar.
    static var snapshot: Snapshot {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache
    }

    /// O cadeado fica confinado nesta função **síncrona** de propósito.
    ///
    /// Chamar `lock()` direto dentro de uma função `async` é erro no Swift 6 e
    /// o motivo é real: entre o `lock` e o `unlock` pode haver uma suspensão, e
    /// a retomada pode acontecer em outra thread — que então tenta destravar um
    /// cadeado que ela nunca travou. Uma função síncrona não tem como suspender,
    /// então o par `lock`/`unlock` roda inteiro na mesma thread.
    private static func store(_ fresh: Snapshot) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        cache = fresh
    }

    /// Consulta o estado real fora da thread principal e devolve o resultado
    /// nela. Chame de `.task`/`.onAppear`, nunca de um inicializador.
    @MainActor
    static func refresh() async -> Snapshot {
        let fresh = await Task.detached(priority: .userInitiated) {
            read()
        }.value
        store(fresh)
        return fresh
    }

    /// A consulta cara de verdade. Privada de propósito: se ninguém de fora
    /// consegue chamar, ninguém de fora consegue bloquear a interface com ela.
    private static func read() -> Snapshot {
        Trace.mark("→ SMAppService.status (XPC para o smd)")
        let status = SMAppService.mainApp.status
        Trace.mark("← SMAppService.status")

        let hasAgent = FileManager.default.fileExists(atPath: agentURL.path)

        switch status {
        case .enabled:
            return Snapshot(
                enabled: true,
                mechanism: .serviceManagement,
                description: "Ativo pelos Itens de Início do sistema.",
                isKnown: true
            )
        case .requiresApproval:
            return Snapshot(
                enabled: true,
                mechanism: .serviceManagement,
                description: "Registrado, mas aguardando sua aprovação em Ajustes do Sistema › Geral › Itens de Início.",
                isKnown: true
            )
        default:
            if hasAgent {
                return Snapshot(
                    enabled: true,
                    mechanism: .launchAgent,
                    description: "Ativo por LaunchAgent — o caminho alternativo, usado porque o app é assinado ad-hoc.",
                    isKnown: true
                )
            }
            return Snapshot(
                enabled: false,
                mechanism: .none,
                description: "Desativado.",
                isKnown: true
            )
        }
    }

    // MARK: - Ligar e desligar

    struct Result {
        var enabled: Bool
        var mechanism: Mechanism
        var message: String
        var isError: Bool
    }

    /// Registrar e cancelar registro também são XPC síncrono para o `smd`, e
    /// `launchctl` é um subprocesso. Fora da thread principal, os dois.
    @MainActor
    static func setEnabled(_ enabled: Bool) async -> Result {
        let result = await Task.detached(priority: .userInitiated) {
            enabled ? self.enable() : self.disable()
        }.value
        _ = await refresh()
        return result
    }

    private static func enable() -> Result {
        // 1) Caminho moderno.
        do {
            try SMAppService.mainApp.register()
            let status = SMAppService.mainApp.status
            if status == .requiresApproval {
                return Result(
                    enabled: true,
                    mechanism: .serviceManagement,
                    message: "Registrado. Aprove em Ajustes do Sistema › Geral › Itens de Início para valer.",
                    isError: false
                )
            }
            return Result(
                enabled: true,
                mechanism: .serviceManagement,
                message: "O SaveMyMac vai abrir junto com o Mac.",
                isError: false
            )
        } catch {
            // 2) Fallback: LaunchAgent. É o caso esperado com assinatura ad-hoc.
            if let failure = writeLaunchAgent() {
                return Result(
                    enabled: false,
                    mechanism: .none,
                    message: "Não foi possível ativar: \(failure)",
                    isError: true
                )
            }
            return Result(
                enabled: true,
                mechanism: .launchAgent,
                message: "Ativado por LaunchAgent. O registro moderno falhou (\(error.localizedDescription)) — esperado num app assinado ad-hoc.",
                isError: false
            )
        }
    }

    private static func disable() -> Result {
        var problems: [String] = []

        if SMAppService.mainApp.status != .notRegistered {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                problems.append(error.localizedDescription)
            }
        }

        if FileManager.default.fileExists(atPath: agentURL.path) {
            // Descarrega antes de apagar, senão o agente segue ativo até o
            // próximo login.
            _ = ProcessMonitor.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
            do {
                try FileManager.default.removeItem(at: agentURL)
            } catch {
                problems.append(error.localizedDescription)
            }
        }

        if problems.isEmpty {
            return Result(
                enabled: false,
                mechanism: .none,
                message: "O SaveMyMac não vai mais abrir junto com o Mac.",
                isError: false
            )
        }
        let after = read()
        return Result(
            enabled: after.enabled,
            mechanism: after.mechanism,
            message: "Falha ao desativar: \(problems.joined(separator: "; "))",
            isError: true
        )
    }

    // MARK: - LaunchAgent

    /// Escreve o plist e carrega. Devolve a mensagem de erro, ou `nil` se deu certo.
    private static func writeLaunchAgent() -> String? {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            return "o app precisa estar num bundle .app (rode ./build.sh --install)"
        }

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
            // Sem isto o launchd relançaria o `open` em loop.
            "KeepAlive": false
        ]

        do {
            let directory = agentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: agentURL, options: .atomic)
        } catch {
            return error.localizedDescription
        }

        let load = ProcessMonitor.run(
            "/bin/launchctl",
            ["bootstrap", "gui/\(getuid())", agentURL.path]
        )
        // `bootstrap` devolve erro se já estiver carregado; isso não é falha real.
        if load.status != 0 && !load.error.contains("already") {
            return "launchctl falhou (\(load.status)): \(load.error.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return nil
    }
}
