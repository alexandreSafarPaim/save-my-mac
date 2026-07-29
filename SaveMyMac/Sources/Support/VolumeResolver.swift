import Foundation

/// Works out which volume a path really lives on.
///
/// This exists for a concrete reason: if `~/.gradle` is a symlink to an external
/// SSD, deleting that content **frees no bytes on the Mac at all**. Worse: it
/// would destroy data on the external disk while the app reports space recovered
/// on the internal one. Every path goes through here before entering the cleanup
/// list.
enum VolumeResolver {

    /// The identity of the volume the user's home folder is on.
    /// That one — and not literally "/" — is the volume whose space matters,
    /// because on modern macOS home lives on the Data volume, linked to the root
    /// by a firmlink (which is not a symlink and does not show up in path
    /// resolution).
    private static let homeVolumeIdentifier: NSObject? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier as? NSObject
    }()

    // MARK: - Identidade de volume

    static func volumeIdentifier(of url: URL) -> NSObject? {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier as? NSObject
    }

    /// `true` if the real content is on the same volume as home.
    ///
    /// Paths that don't exist return `true` on purpose: a broken link should not
    /// be treated as "external content".
    static func isOnHomeVolume(_ url: URL) -> Bool {
        guard let home = homeVolumeIdentifier else { return true }
        guard let target = volumeIdentifier(of: url) else { return true }
        return home.isEqual(target)
    }

    /// A path only yields space on the Mac if it isn't a link and is on the home volume.
    static func freesSpaceOnMac(_ url: URL) -> Bool {
        if isSymbolicLink(url) { return false }
        return isOnHomeVolume(url)
    }

    // MARK: - Volume information

    static func volumeName(of url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName
    }

    static func mountPoint(of url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        let values = try? resolved.resourceValues(forKeys: [.volumeURLKey])
        return values?.volume?.path
    }

    struct VolumeCapacity {
        var total: Int64
        var available: Int64
    }

    static func capacity(ofMountPoint path: String) -> VolumeCapacity? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]) else { return nil }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeCapacity(total: total, available: max(0, available))
    }

    // MARK: - Symlinks

    static func isSymbolicLink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink ?? false
    }

    /// A symlink's absolute target, resolving relative targets.
    static func symlinkTarget(of url: URL) -> URL? {
        guard let raw = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw).standardizedFileURL
        }
        return url.deletingLastPathComponent()
            .appendingPathComponent(raw)
            .standardizedFileURL
    }
}
