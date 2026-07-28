import Foundation
import AppKit
import Darwin

/// Encerra processos, com as travas que faltam num `kill` cru.
///
/// A ordem importa: primeiro pede ao app para sair — o que dá a ele a chance de
/// salvar o que estava aberto —, e só força se o usuário confirmar depois. Um
/// "liberar memória" que mata processos à força perde trabalho do usuário para
/// melhorar um número que, no macOS, nem deveria ser otimizado.
enum ProcessController {

    enum Outcome {
        case askedToQuit(String)
        case terminated(String)
        case refused(String)
        case failed(String)

        var message: String {
            switch self {
            case .askedToQuit(let name):
                return "Pedido de encerramento enviado para \(name). Se houver algo não salvo, ele vai perguntar."
            case .terminated(let name):
                return "\(name) foi encerrado."
            case .refused(let reason):
                return reason
            case .failed(let reason):
                return reason
            }
        }

        var isError: Bool {
            switch self {
            case .askedToQuit, .terminated: return false
            case .refused, .failed: return true
            }
        }
    }

    /// Processos que o app nunca encerra.
    ///
    /// Não é lista de "pode dar problema": é lista de "vai quebrar a sessão".
    /// Matar o WindowServer derruba a interface inteira; matar o launchd
    /// reinicia a máquina.
    private static let critical: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logind",
        "opendirectoryd", "securityd", "secinitd", "trustd", "configd",
        "distnoted", "notifyd", "syslogd", "powerd", "watchdogd", "hidd",
        "coreaudiod", "diskarbitrationd", "fseventsd", "mds", "mds_stores",
        "cfprefsd", "UserEventAgent", "amfid", "kextd", "nsurlsessiond",
        "backupd", "installd", "runningboardd", "SystemUIServer"
    ]

    /// Processos que voltam sozinhos e cujo encerramento é apenas irritante.
    /// Permitidos, mas com aviso.
    static let relaunches: Set<String> = ["Finder", "Dock", "ControlCenter", "NotificationCenter"]

    // MARK: - Verificação

    /// Motivo para não encerrar, ou `nil` se pode.
    static func rejectionReason(for row: ProcessInfoRow) -> String? {
        if row.pid <= 1 {
            return "Processo do núcleo do sistema."
        }
        if row.pid == ProcessInfo.processInfo.processIdentifier {
            return "Este é o próprio SaveMyMac."
        }
        if critical.contains(row.name) {
            return "\(row.name) é essencial para a sessão — encerrar derrubaria a interface."
        }
        // Sem privilégio de root não há como encerrar processo de outro dono, e
        // pedir senha para isso seria trocar estabilidade por um número.
        // `bitPattern` em vez de `Int32(getuid())`: a conversão de UInt32 daria
        // trap se o uid passasse de Int32.max.
        if let uid = row.uid, uid != Int32(bitPattern: getuid()) {
            return "\(row.name) não é seu (roda como uid \(uid)). O app não escala privilégio para isso."
        }
        return nil
    }

    /// Aviso extra para processos que o macOS relança sozinho — encerrar não
    /// quebra nada, só pisca a interface.
    static func warning(for row: ProcessInfoRow) -> String? {
        guard relaunches.contains(row.name) else { return nil }
        return "O macOS relança \(row.name) automaticamente."
    }

    static func canQuit(_ row: ProcessInfoRow) -> Bool {
        rejectionReason(for: row) == nil
    }

    // MARK: - Encerrar

    /// Pedido gentil: o app decide quando sair e pode pedir para salvar.
    @discardableResult
    static func requestQuit(_ row: ProcessInfoRow) -> Outcome {
        if let reason = rejectionReason(for: row) {
            return .refused(reason)
        }

        // App com interface: `terminate()` manda um Apple Event de quit, que é
        // o mesmo que ⌘Q. `kill` puro não daria essa chance.
        if let app = NSRunningApplication(processIdentifier: row.pid) {
            let name = app.localizedName ?? row.name
            return app.terminate()
                ? .askedToQuit(name)
                : .failed("\(name) não aceitou o pedido de encerramento. Use forçar se precisar.")
        }

        // Daemon ou helper sem interface: SIGTERM é o equivalente educado.
        if kill(row.pid, SIGTERM) == 0 {
            return .askedToQuit(row.name)
        }
        return .failed("Não foi possível encerrar \(row.name): \(String(cString: strerror(errno))).")
    }

    /// Força. Só deve ser chamado depois de confirmação explícita, porque
    /// trabalho não salvo é perdido.
    @discardableResult
    static func forceQuit(_ row: ProcessInfoRow) -> Outcome {
        if let reason = rejectionReason(for: row) {
            return .refused(reason)
        }

        if let app = NSRunningApplication(processIdentifier: row.pid) {
            let name = app.localizedName ?? row.name
            return app.forceTerminate()
                ? .terminated(name)
                : .failed("Não foi possível forçar o encerramento de \(name).")
        }

        if kill(row.pid, SIGKILL) == 0 {
            return .terminated(row.name)
        }
        return .failed("Não foi possível forçar \(row.name): \(String(cString: strerror(errno))).")
    }

    // MARK: - Informação extra

    /// Nome e ícone de verdade quando o processo é um app com interface.
    static func appInfo(for pid: Int32) -> (name: String, bundlePath: String)? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let url = app.bundleURL else { return nil }
        return (app.localizedName ?? url.deletingPathExtension().lastPathComponent, url.path)
    }
}
