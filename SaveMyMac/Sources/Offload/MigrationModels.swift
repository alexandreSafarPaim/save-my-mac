import Foundation

/// Etapas da migração, na ordem em que acontecem.
///
/// A ordem existe para que uma falha em qualquer ponto seja reversível: o
/// original só sai do lugar depois da cópia ter sido verificada, e só é
/// liberado de vez depois do link ter sido testado.
enum MigrationPhase: String, Codable {
    case preflight        // checagens antes de tocar em nada
    case copying          // ditto para a área de staging no destino
    case verifying        // contagem de arquivos e bytes batem?
    case quarantining     // original vai para a quarentena (rename, instantâneo)
    case publishing       // staging passa a ser o alvo definitivo
    case linking          // cria o link simbólico no lugar do original
    case validating       // lê e escreve através do link
    case done
    case failed
    case rolledBack

    var label: String {
        switch self {
        case .preflight: return "Verificando"
        case .copying: return "Copiando"
        case .verifying: return "Conferindo a cópia"
        case .quarantining: return "Movendo o original para a quarentena"
        case .publishing: return "Publicando no destino"
        case .linking: return "Criando o link"
        case .validating: return "Testando o link"
        case .done: return "Concluído"
        case .failed: return "Falhou"
        case .rolledBack: return "Revertido"
        }
    }
}

/// Registro persistido de uma migração. É isto que permite retomar ou reverter
/// se o cabo do SSD cair no meio da operação.
struct MigrationJournalEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var sourcePath: String
    var stagingPath: String
    var targetPath: String
    var quarantinePath: String
    var phase: MigrationPhase
    var startedAt: Date
    var finishedAt: Date?
    var bytes: Int64
    var fileCount: Int
    var errorMessage: String?

    var name: String { (sourcePath as NSString).lastPathComponent }

    /// Uma entrada em quarentena ainda ocupa espaço e pode ser desfeita.
    var isReversible: Bool {
        phase == .done && FileManager.default.fileExists(atPath: quarantinePath)
    }
}

struct MigrationJournal: Codable {
    var entries: [MigrationJournalEntry] = []

    /// Operações que ficaram no meio do caminho — precisam de atenção.
    var unfinished: [MigrationJournalEntry] {
        entries.filter { $0.phase != .done && $0.phase != .rolledBack && $0.phase != .failed }
    }

    var quarantined: [MigrationJournalEntry] {
        entries.filter(\.isReversible)
    }

    var quarantineBytes: Int64 {
        quarantined.reduce(0) { $0 + $1.bytes }
    }
}

/// Resultado devolvido à interface.
struct MigrationOutcome {
    var entry: MigrationJournalEntry
    var succeeded: Bool
    var message: String
}

/// Um candidato a offload, com o motivo e o veredito.
struct OffloadCandidate: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var displayName: String
    var size: Int64
    var reason: String
    /// Nem tudo que é grande deve ser linkado.
    var recommendation: OffloadRecommendation
    var nativeSettingHint: String?

    var name: String { (path as NSString).lastPathComponent }
}

enum OffloadRecommendation: String, Codable {
    /// Grande, frio, sem ajuste nativo — bom candidato.
    case move
    /// Regenerável e barato: apagar é melhor que mover.
    case deleteInstead
    /// O app tem ajuste próprio de localização, melhor que um link.
    case useNativeSetting
    /// Nunca linkar: daemon do sistema mexe nisso.
    case never

    var label: String {
        switch self {
        case .move: return "Bom candidato"
        case .deleteInstead: return "Melhor apagar"
        case .useNativeSetting: return "Use o ajuste do app"
        case .never: return "Não linkar"
        }
    }

    var explanation: String {
        switch self {
        case .move:
            return "Volume grande, acesso raro e sem alternativa nativa. É o caso clássico de offload."
        case .deleteInstead:
            return "É cache regenerável e barato de refazer. Mover dá trabalho sem ganho real."
        case .useNativeSetting:
            return "O próprio app permite mudar a pasta nas preferências, o que é mais robusto que um link."
        case .never:
            return "Um serviço do sistema gerencia esta pasta e não lida bem com links simbólicos."
        }
    }
}
