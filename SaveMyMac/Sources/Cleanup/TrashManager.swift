import Foundation

/// A top-level item inside the Trash.
struct TrashItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    var path: String
    var name: String
    var size: Int64
    var discardedAt: Date?
    /// `false` when `addedToDirectoryDate` was unavailable and we fell back to
    /// the original mtime — in that case the date does not say when the item was
    /// discarded.
    var discardedDateIsExact: Bool = true
    var isDirectory: Bool
}

struct TrashInfo: Sendable {
    var items: [TrashItem] = []
    var totalBytes: Int64 = 0
    /// Tells "Trash is empty" apart from "not measured yet".
    var isMeasured = false

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    /// The oldest item, to give a sense of how long that has been sitting there.
    var oldest: Date? {
        items.compactMap(\.discardedAt).min()
    }

    /// Only returns text when the date is trustworthy: the sentence appears in
    /// the dialog for the app's only irreversible action and serves as an argument
    /// for confirming.
    var oldestLabel: String? {
        let exact = items.filter(\.discardedDateIsExact).compactMap(\.discardedAt)
        guard let oldest = exact.min() else { return nil }
        return Fmt.relativeDate(oldest)
    }
}

struct TrashEmptyResult: Sendable {
    var removedCount: Int = 0
    var freedBytes: Int64 = 0
    var failures: [(path: String, reason: String)] = []
}

/// Reads and empties the user's Trash.
///
/// Deliberate scope: **`~/.Trash` only**. Every external volume has its own Trash
/// at `/Volumes/<name>/.Trashes/<uid>/`, and touching those is a different
/// decision — it frees space on a disk that may not be the one you meant to
/// clean. Here the accounting is the Mac's alone.
///
/// Emptying is permanent by definition: there is no "move to the Trash" for what
/// is already in it. That makes this the app's only operation with no way back,
/// and it always goes through a confirmation showing the total and the count.
enum TrashManager {

    static var trashURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
    }

    // MARK: - Leitura

    static func inspect(isCancelled: () -> Bool = { false }) -> TrashInfo {
        var info = TrashInfo()
        let fm = FileManager.default
        let root = trashURL

        guard fm.fileExists(atPath: root.path) else {
            info.isMeasured = true
            return info
        }

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .addedToDirectoryDateKey,
            .contentModificationDateKey
        ]

        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            info.isMeasured = true
            return info
        }

        for url in contents {
            if isCancelled() { break }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false

            let size = isDir
                ? DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                : url.allocatedBytes

            // `addedToDirectoryDate` is when the item entered the Trash, which is
            // what matters. Apple warns it isn't supported on every volume, hence
            // the fallback — flagged as imprecise.
            let added = values?.addedToDirectoryDate
            info.items.append(TrashItem(
                path: url.path,
                name: url.lastPathComponent,
                size: size,
                discardedAt: added ?? values?.contentModificationDate,
                discardedDateIsExact: added != nil,
                isDirectory: isDir
            ))
            info.totalBytes += size
        }

        info.items.sort { $0.size > $1.size }
        info.isMeasured = true
        return info
    }

    // MARK: - Esvaziar

    /// Empties by enumerating the directory **live**.
    ///
    /// It deliberately does not take the list from the interface: the on-screen
    /// snapshot may predate the last cleanup — and it is precisely a cleanup in
    /// "Move to Trash" mode that fills this up. Iterating a stale snapshot, the
    /// app would report "Trash emptied" without deleting what had just been
    /// moved there.
    static func empty(progress: (String, Double) -> Void) -> TrashEmptyResult {
        var result = TrashEmptyResult()
        let fm = FileManager.default
        let root = trashURL
        let rootPath = root.standardizedFileURL.path

        // `standardizedFileURL` resolves `.` and `..` but does NOT resolve
        // symlinks. If `~/.Trash` is a link, the path guard below would pass and
        // the app would recursively delete the real target. This is the app's only
        // operation with no way back, so the check earns its place.
        let rootValues = try? root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard rootValues?.isSymbolicLink != true, rootValues?.isDirectory == true else {
            result.failures.append((root.path, L("~/.Trash is not a real folder — nothing was removed")))
            return result
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let contents = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: []
        ) else {
            result.failures.append((root.path, L("Could not read the Trash")))
            return result
        }

        let total = max(1, contents.count)
        for (index, url) in contents.enumerated() {
            progress(url.lastPathComponent, Double(index) / Double(total))

            guard url.deletingLastPathComponent().standardizedFileURL.path == rootPath else {
                result.failures.append((url.path, L("Outside the user's Trash")))
                continue
            }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = (values?.isDirectory ?? false)
                ? DiskMonitor.directorySize(at: url)
                : url.allocatedBytes

            do {
                // `removeItem` does not follow symlinks: a link inside the Trash
                // pointing outside has only the link removed.
                try fm.removeItem(at: url)
                result.removedCount += 1
                result.freedBytes += size
            } catch {
                result.failures.append((url.path, friendlyReason(for: error, url: url)))
            }
        }

        progress(L("Done"), 1.0)
        return result
    }

    /// Traduz os erros que de fato aparecem ao esvaziar a Lixeira.
    private static func friendlyReason(for error: Error, url: URL) -> String {
        let ns = error as NSError

        // A file with the immutable flag (`chflags uchg`) — Finder asks for
        // confirmation in that case; here we just report it.
        if let values = try? url.resourceValues(forKeys: [.isUserImmutableKey]),
           values.isUserImmutable == true {
            return L("File is locked. Unlock it in Finder (Get Info) and try again.")
        }

        switch ns.code {
        case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
            return L("No permission. It may belong to another user or be in use.")
        case NSFileWriteFileExistsError:
            return L("Name conflict inside the Trash.")
        default:
            return ns.localizedDescription
        }
    }
}
