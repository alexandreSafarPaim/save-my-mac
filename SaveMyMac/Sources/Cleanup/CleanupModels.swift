import Foundation

/// Nível de risco de remover um item.
enum RiskLevel: Int, Comparable, CaseIterable {
    case safe = 0        // regenerável, nenhum impacto
    case caution = 1     // regenerável mas custa tempo/rede
    case review = 2      // pode ser conteúdo seu — revise antes

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .safe: return "Seguro"
        case .caution: return L("Caution")
        case .review: return "Revisar"
        }
    }

    var explanation: String {
        switch self {
        case .safe:
            return L("Temporary files the system recreates automatically.")
        case .caution:
            return L("Can be removed, but it will be downloaded or rebuilt the next time you use the app.")
        case .review:
            return L("May contain your own files. Check item by item before selecting.")
        }
    }
}

/// Um arquivo ou pasta candidato à remoção.
struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var displayName: String
    var size: Int64
    var modified: Date?
    var isDirectory: Bool
    var note: String?

    /// Caminhos adicionais quando um item representa vários arquivos
    /// (ex.: "1.243 arquivos .DS_Store").
    var extraPaths: [String] = []

    var url: URL { URL(fileURLWithPath: path) }

    var allPaths: [String] { [path] + extraPaths }
}

/// Agrupamento de itens (ex.: "Caches de usuário").
struct CleanupCategory: Identifiable {
    let id = UUID()
    var name: String
    var subtitle: String
    var symbol: String
    var risk: RiskLevel
    /// Nota de 1 a 10 exibida como "RISCO n/10" — mais granular que o nível,
    /// porque "atenção" abrange desde cache de npm até simulador de iOS.
    var riskScore: Int
    var items: [CleanupItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { items.isEmpty }
}

/// Resultado de uma remoção.
struct CleanupResult {
    var removedCount: Int = 0
    var freedBytes: Int64 = 0
    var failures: [(path: String, reason: String)] = []
}

enum CleanupMode: String, CaseIterable, Identifiable {
    case trash
    case permanent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .trash: return L("Move to Trash")
        case .permanent: return L("Delete permanently")
        }
    }

    var description: String {
        switch self {
        case .trash:
            return L("Safer: you can restore. The space only comes back when the Trash is emptied — which you can do right here, in the card at the top.")
        case .permanent:
            return L("Frees the space immediately, with no chance of recovery.")
        }
    }
}
