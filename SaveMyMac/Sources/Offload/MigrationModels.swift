import Foundation

/// The migration phases, in the order they happen.
///
/// The order exists so a failure at any point is reversible: the original only
/// leaves its place after the copy has been verified, and is only released for
/// good after the link has been tested.
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
        case .verifying: return L("Verifying the copy")
        case .quarantining: return L("Moving the original to quarantine")
        case .publishing: return L("Publishing to the destination")
        case .linking: return L("Creating the link")
        case .validating: return L("Testing the link")
        case .done: return L("Done")
        case .failed: return "Falhou"
        case .rolledBack: return "Revertido"
        }
    }
}

/// The persisted record of a migration. This is what makes it possible to resume
/// or roll back if the SSD cable comes loose mid-operation.
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

    /// A quarantined entry still takes up space and can be undone.
    var isReversible: Bool {
        phase == .done && FileManager.default.fileExists(atPath: quarantinePath)
    }
}

struct MigrationJournal: Codable {
    var entries: [MigrationJournalEntry] = []

    /// Operations left half-finished — they need attention.
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

/// The result handed back to the interface.
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
    /// Not everything large should be linked.
    var recommendation: OffloadRecommendation
    var nativeSettingHint: String?

    var name: String { (path as NSString).lastPathComponent }
}

enum OffloadRecommendation: String, Codable {
    /// Grande, frio, sem ajuste nativo — bom candidato.
    case move
    /// Regenerable and cheap: deleting beats moving.
    case deleteInstead
    /// The app has its own location setting, better than a link.
    case useNativeSetting
    /// Nunca linkar: daemon do sistema mexe nisso.
    case never

    var label: String {
        switch self {
        case .move: return L("Good candidate")
        case .deleteInstead: return L("Better to delete")
        case .useNativeSetting: return L("Use the app's own setting")
        case .never: return L("Do not link")
        }
    }

    var explanation: String {
        switch self {
        case .move:
            return L("Large volume, rarely accessed, no native alternative. The classic offload case.")
        case .deleteInstead:
            return L("It's regenerable cache and cheap to rebuild. Moving it is work with no real gain.")
        case .useNativeSetting:
            return L("The app itself lets you change the folder in its preferences, which is more robust than a link.")
        case .never:
            return L("A system service manages this folder and does not handle symlinks well.")
        }
    }
}
