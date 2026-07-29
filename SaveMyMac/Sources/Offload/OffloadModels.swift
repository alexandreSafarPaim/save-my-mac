import Foundation

/// The state of a symlink found in the home folder.
enum LinkStatus: Equatable {
    /// Points to another volume, mounted, target exists. The desired case.
    case offloaded
    /// Points at a volume that isn't mounted right now.
    case volumeMissing
    /// The target does not exist (dangling link).
    case broken
    /// Points somewhere else on the Mac's own disk — saves nothing.
    case sameDisk

    var label: String {
        switch self {
        case .offloaded: return "OK"
        case .volumeMissing: return L("Volume missing")
        case .broken: return "Quebrado"
        case .sameDisk: return L("Same disk")
        }
    }

    var explanation: String {
        switch self {
        case .offloaded:
            return L("The content is on the external volume and the link is working.")
        case .volumeMissing:
            return L("The destination volume is not mounted. Apps using this path will fail — and some may recreate the folder over the link, creating two diverging sets of data.")
        case .broken:
            return L("The target no longer exists. The link has to be recreated or removed.")
        case .sameDisk:
            return L("The destination is on the Mac's own disk, so this link saves no space.")
        }
    }
}

struct SymlinkEntry: Identifiable, Hashable {
    let id = UUID()
    var linkPath: String
    var targetPath: String
    var targetVolumeName: String?
    var targetMountPoint: String?
    var size: Int64
    var created: Date?
    var statusRaw: Int

    var status: LinkStatus {
        switch statusRaw {
        case 0: return .offloaded
        case 1: return .volumeMissing
        case 2: return .broken
        default: return .sameDisk
        }
    }

    /// Only counts as real space savings on the Mac.
    var savesSpace: Bool { status == .offloaded }

    var linkName: String { (linkPath as NSString).lastPathComponent }
}

/// A folder on the destination volume that isn't the target of any link — orphan data.
struct OrphanEntry: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var size: Int64
    var modified: Date?
    var volumeName: String
}

/// Agrupamento por volume de destino.
struct OffloadVolumeGroup: Identifiable {
    var id: String { mountPoint }
    var name: String
    var mountPoint: String
    var isMounted: Bool
    var capacityTotal: Int64
    var capacityAvailable: Int64
    var links: [SymlinkEntry]

    var offloadedSize: Int64 {
        links.filter { $0.savesSpace }.reduce(0) { $0 + $1.size }
    }

    var usedFraction: Double {
        capacityTotal <= 0 ? 0 : Double(capacityTotal - capacityAvailable) / Double(capacityTotal)
    }
}

struct OffloadInventory {
    var links: [SymlinkEntry] = []
    var orphans: [OrphanEntry] = []
    var groups: [OffloadVolumeGroup] = []
    var scannedDirectories: Int = 0
    var reachedLimit: Bool = false

    /// Space that today isn't taking up the Mac's disk, thanks to the links.
    var savedBytes: Int64 {
        links.filter { $0.savesSpace }.reduce(0) { $0 + $1.size }
    }

    var brokenCount: Int {
        links.filter { $0.status == .broken || $0.status == .volumeMissing }.count
    }

    var orphanBytes: Int64 {
        orphans.reduce(0) { $0 + $1.size }
    }

    var isEmpty: Bool { links.isEmpty && orphans.isEmpty }
}
