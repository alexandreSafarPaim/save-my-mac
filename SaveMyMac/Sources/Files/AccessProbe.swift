import Foundation

/// What the app can actually read, measured folder by folder.
///
/// ── Why this exists ─────────────────────────────────────────────────────────
///
/// The first attempt at detecting a blocked scan counted errors from the deep
/// enumerator's `errorHandler`. It never fired once, because
/// `FileManager.enumerator` does not report a TCC denial as an error: it
/// descends into the folder, finds nothing, and moves on. The count stayed at
/// zero while the walk visited 46 files out of the 1360 the same home folder
/// really contains, and the screen said "no large files" with total confidence.
///
/// The lesson, learned several times in this project: an indicator that sits
/// *next to* the thing you want to know is not the thing. The error count was
/// adjacent to permission. It was not permission.
///
/// ── What this measures instead ──────────────────────────────────────────────
///
/// `contentsOfDirectory` — a shallow listing — *does* throw on a TCC denial
/// where the deep enumerator stays quiet. That difference is the whole probe.
///
/// Three outcomes per folder, and they are not equally informative:
///
///   * **throws**       — denied, no ambiguity.
///   * **N entries**    — readable.
///   * **zero entries** — *unknown*. An empty Desktop and a denied Desktop look
///                        identical from here. This is recorded as suspicious,
///                        never as proof. The Mac this was written on has a
///                        genuinely empty Desktop, so treating zero as denial
///                        would have produced a confident false alarm — the
///                        same mistake in the opposite direction.
///
/// Plus one canary: `~/Library/Application Support/com.apple.TCC/TCC.db` is
/// readable only with Full Disk Access. It answers a different question than
/// the per-folder probes — an app can have Documents and Downloads granted
/// individually without ever having Full Disk Access — so it is reported
/// alongside them, not merged into them.
struct AccessProbe {

    struct Folder: Identifiable {
        var name: String
        var id: String { name }

        /// Does the folder exist at all? A Mac with no `~/Movies` is not blocked.
        var exists: Bool
        /// Entries returned by a shallow listing.
        var entries: Int
        /// The listing threw. This is a denial.
        var deniedOutright: Bool
        /// POSIX/Cocoa error code, for the trace.
        var errorCode: Int?

        /// Exists, did not throw, and returned nothing. Could be denial, could
        /// be an empty folder. Deliberately not called "denied".
        var suspicious: Bool { exists && !deniedOutright && entries == 0 }
    }

    var folders: [Folder] = []

    /// Could the app read a file that only Full Disk Access unlocks?
    var hasFullDiskAccess: Bool = false

    /// Folders that threw. These are certain.
    var denied: [Folder] { folders.filter(\.deniedOutright) }

    /// Folders that came back empty without an error. These are a maybe.
    var suspicious: [Folder] { folders.filter(\.suspicious) }

    var readable: [Folder] { folders.filter { $0.exists && $0.entries > 0 } }

    /// The verdict shown to the user.
    ///
    /// A single outright denial is enough. Suspicious-only folders are not:
    /// combined with a walk that saw almost nothing, they become a verdict
    /// (`FileScanResult.looksBlocked` applies that second condition), but on
    /// their own an empty Desktop must not raise an alarm.
    var isDefinitelyBlocked: Bool { !denied.isEmpty }

    /// Folder names to show the user, certain ones first.
    var namesToReport: [String] {
        (denied + suspicious).map(\.name)
    }

    // MARK: - Running the probe

    /// The folders macOS protects with TCC, plus the one this scanner cares
    /// about most. `Application Support` is listed separately from `Library`
    /// because that is where multi-gigabyte payloads actually sit, and a denial
    /// there is what made this screen useless.
    static let protectedFolders = [
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
        "Library", "Library/Application Support", "Library/Caches",
    ]

    static func run(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AccessProbe {
        let fm = FileManager.default
        var probe = AccessProbe()

        for name in protectedFolders {
            let url = home.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else {
                probe.folders.append(Folder(name: name, exists: false, entries: 0,
                                            deniedOutright: false, errorCode: nil))
                continue
            }
            do {
                let contents = try fm.contentsOfDirectory(atPath: url.path)
                probe.folders.append(Folder(name: name, exists: true, entries: contents.count,
                                            deniedOutright: false, errorCode: nil))
            } catch {
                probe.folders.append(Folder(name: name, exists: true, entries: 0,
                                            deniedOutright: true,
                                            errorCode: (error as NSError).code))
            }
        }

        probe.hasFullDiskAccess = canReadTCCDatabase(home: home)
        return probe
    }

    /// Reads a single byte of the TCC database.
    ///
    /// Opening it is the check; the contents are never parsed and never leave
    /// this function. Only an app with Full Disk Access can open it, which is
    /// precisely the question.
    private static func canReadTCCDatabase(home: URL) -> Bool {
        let db = home
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: db) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    // MARK: - Trace

    /// One line per folder, written to the trace so a blocked scan leaves
    /// evidence instead of just a wrong number on screen.
    var traceReport: String {
        var lines = ["access probe — full disk access: \(hasFullDiskAccess ? "YES" : "no")"]
        for folder in folders {
            if !folder.exists {
                lines.append("  \(folder.name): does not exist")
            } else if folder.deniedOutright {
                lines.append("  \(folder.name): DENIED (error \(folder.errorCode ?? -1))")
            } else if folder.entries == 0 {
                lines.append("  \(folder.name): 0 entries — empty or silently denied")
            } else {
                lines.append("  \(folder.name): \(folder.entries) entries")
            }
        }
        return lines.joined(separator: "\n")
    }
}
