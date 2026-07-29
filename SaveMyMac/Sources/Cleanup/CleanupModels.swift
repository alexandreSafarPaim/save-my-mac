import Foundation

/// How risky it is to remove an item.
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

/// A file or folder that is a candidate for removal.
struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var displayName: String
    var size: Int64
    var modified: Date?
    var isDirectory: Bool
    var note: String?

    /// Additional paths when one item stands for several files
    /// (e.g. "1,243 .DS_Store files").
    var extraPaths: [String] = []

    var url: URL { URL(fileURLWithPath: path) }

    var allPaths: [String] { [path] + extraPaths }
}

/// A grouping of items (e.g. "User caches").
struct CleanupCategory: Identifiable {
    let id = UUID()
    var name: String
    var subtitle: String
    var symbol: String
    var risk: RiskLevel
    /// A 1-to-10 score shown as "RISK n/10" — finer-grained than the level,
    /// because "caution" spans everything from an npm cache to an iOS simulator.
    var riskScore: Int
    var items: [CleanupItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { items.isEmpty }
}

/// The result of a removal.
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
