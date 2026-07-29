import Foundation

/// Moves a folder to another volume and leaves a symlink in its place.
///
/// The sequence is deliberately conservative, and every step is recorded in an
/// on-disk journal before it happens:
///
///   1. checks (does the volume support links? does it fit? is the path allowed?)
///   2. copy into a staging area at the destination, with `ditto`
///   3. verify file count and byte count
///   4. move the original into quarantine — a rename on the same volume, instant
///   5. publish the staging area as the final target
///   6. create the symlink
///   7. test reading and writing through the link
///
/// The original is never deleted: it stays in quarantine until you release it.
/// Any failure triggers an automatic rollback.
final class MigrationEngine: @unchecked Sendable {

    static let journalFile = "migrations.json"

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var quarantineRoot: URL {
        home.appendingPathComponent(".savemymac-quarantine", isDirectory: true)
    }

    private func stagingRoot(in destination: URL) -> URL {
        destination.appendingPathComponent(".savemymac-staging", isDirectory: true)
    }

    // MARK: - Journal

    func loadJournal() -> MigrationJournal {
        Store.load(MigrationJournal.self, from: MigrationEngine.journalFile) ?? MigrationJournal()
    }

    /// Persists a journal entry, returning whether it reached the disk.
    ///
    /// The journal is the only record of where a quarantined original went.
    /// Most callers can tolerate a failed write mid-flight (the next phase
    /// writes again), but the caller that quarantines the original MUST know:
    /// quarantining with an unwritten journal would strand the user's data at a
    /// path only the dead process knew.
    @discardableResult
    private func write(_ entry: MigrationJournalEntry) -> Bool {
        var journal = loadJournal()
        if let index = journal.entries.firstIndex(where: { $0.id == entry.id }) {
            journal.entries[index] = entry
        } else {
            journal.entries.insert(entry, at: 0)
        }
        return Store.save(journal, to: MigrationEngine.journalFile)
    }

    // MARK: - Checks

    /// Why the destination is unsuitable, or `nil` if everything is fine.
    static func destinationProblem(_ destination: URL, needing bytes: Int64) -> String? {
        let fm = FileManager.default

        guard fm.fileExists(atPath: destination.path) else {
            return L("The destination folder does not exist, or the volume is not mounted.")
        }

        let keys: Set<URLResourceKey> = [
            .volumeSupportsSymbolicLinksKey,
            .volumeIsReadOnlyKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey
        ]
        guard let values = try? destination.resourceValues(forKeys: keys) else {
            return L("Could not read the destination volume's characteristics.")
        }

        // The disqualifying gate: exFAT and FAT have no symlinks.
        if values.volumeSupportsSymbolicLinks == false {
            let name = values.volumeName ?? L("This volume")
            return L("%@ does not support symlinks. Format it as APFS or HFS+ to use offload.", name)
        }
        if values.volumeIsReadOnly == true {
            return L("The destination volume is read-only.")
        }
        if !fm.isWritableFile(atPath: destination.path) {
            return L("No write permission on the destination folder.")
        }

        // Margem de 3% para metadados.
        let needed = Int64(Double(bytes) * 1.03)
        if let available = values.volumeAvailableCapacityForImportantUsage, available < needed {
            return L("%@ short at the destination (needs %@).", Fmt.bytes(needed - available), Fmt.bytes(needed))
        }

        return nil
    }

    /// Why the source cannot be offloaded.
    static func sourceProblem(_ source: URL) -> String? {
        let fm = FileManager.default
        let path = source.standardizedFileURL.path

        guard fm.fileExists(atPath: path) else { return L("The source folder does not exist.") }

        if VolumeResolver.isSymbolicLink(source) {
            return L("This folder is already a symlink.")
        }
        if !VolumeResolver.isOnHomeVolume(source) {
            return L("The content is already off the Mac's disk.")
        }

        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard path.hasPrefix(home + "/") else {
            return L("Only folders inside your home folder can be offloaded.")
        }

        let relative = String(path.dropFirst(home.count + 1))
        let components = relative.split(separator: "/")

        let protectedTop: Set<String> = [
            "Documents", "Desktop", "Downloads", "Library", "Pictures",
            "Movies", "Music", "Public", "Applications", ".Trash"
        ]
        if components.count == 1 && protectedTop.contains(String(components[0])) {
            return L("Don't offload a whole top-level folder — pick something inside it.")
        }

        // Folders managed by system daemons: a symlink here causes trouble.
        let never: [(String, String)] = [
            ("Library/Mobile Documents", "iCloud Drive"),
            ("Library/CloudStorage", L("cloud providers")),
            ("Library/Keychains", L("the system keychain")),
            ("Library/Mail", L("Mail")),
            ("Library/Messages", L("Messages")),
            ("Library/Group Containers", L("group containers")),
            ("Library/Containers", L("sandboxed app containers")),
            ("Library/Preferences", L("its preferences"))
        ]
        for (prefix, who) in never where relative.hasPrefix(prefix) {
            return L("%@ does not handle symlinks well. This folder is out.", who)
        }
        if source.pathExtension.lowercased() == "photoslibrary" {
            return L("Apple does not support a link on the Photos library. Move the library and open Photos holding Option.")
        }

        return nil
    }

    /// Impede que o destino fique dentro da origem, ou vice-versa.
    static func nestingProblem(source: URL, target: URL) -> String? {
        let s = source.standardizedFileURL.path
        let t = target.standardizedFileURL.path
        if t.hasPrefix(s + "/") { return L("The destination cannot be inside the source itself.") }
        if s.hasPrefix(t + "/") { return L("The source cannot be inside the destination.") }
        if s == t { return L("Source and destination are the same path.") }
        return nil
    }

    // MARK: - Migration

    func migrate(
        source: URL,
        destinationRoot: URL,
        progress: @escaping (MigrationPhase, String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> MigrationOutcome {

        progress(.preflight, L("Checking source and destination…"), 0.01)

        let name = source.lastPathComponent
        let target = destinationRoot.appendingPathComponent(name)
        let uuid = UUID()
        let staging = stagingRoot(in: destinationRoot).appendingPathComponent(uuid.uuidString)
        let stagingItem = staging.appendingPathComponent(name)
        let quarantine = quarantineRoot.appendingPathComponent(uuid.uuidString)
        let quarantineItem = quarantine.appendingPathComponent(name)

        var entry = MigrationJournalEntry(
            id: uuid,
            sourcePath: source.path,
            stagingPath: stagingItem.path,
            targetPath: target.path,
            quarantinePath: quarantineItem.path,
            phase: .preflight,
            startedAt: Date(),
            bytes: 0,
            fileCount: 0
        )

        func fail(_ message: String) -> MigrationOutcome {
            entry.phase = .failed
            entry.errorMessage = message
            entry.finishedAt = Date()
            write(entry)
            return MigrationOutcome(entry: entry, succeeded: false, message: message)
        }

        // --- 1. Checks ---
        if let problem = MigrationEngine.sourceProblem(source) { return fail(problem) }
        if let problem = MigrationEngine.nestingProblem(source: source, target: target) { return fail(problem) }
        if fm.fileExists(atPath: target.path) {
            return fail(L("\"%@\" already exists at the destination. Rename it or pick another folder.", name))
        }

        let measured = measure(source, isCancelled: isCancelled)
        entry.bytes = measured.bytes
        entry.fileCount = measured.files

        // Refusing here, not warning: if the measurement cannot see every file,
        // neither can the verification, and a migration whose verification is
        // blind is a copy the app cannot vouch for. The user can fix the
        // permission (usually Full Disk Access) and run it again.
        if measured.unreadable > 0 {
            return fail(Lp("%d file could not be read in the source, so the copy could not be verified. Nothing was moved.",
                           "%d files could not be read in the source, so the copy could not be verified. Nothing was moved.",
                           count: measured.unreadable))
        }

        if let problem = MigrationEngine.destinationProblem(destinationRoot, needing: measured.bytes) {
            return fail(problem)
        }

        // --- 2. Copy ---
        entry.phase = .copying
        write(entry)
        progress(.copying, L("Copying %@…", Fmt.bytes(measured.bytes)), 0.05)

        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            return fail(L("Could not create the staging area: %@", error.localizedDescription))
        }

        // `ditto` is Apple's and preserves metadata, xattrs, ACLs and resource
        // forks. We avoid `rsync` because the implementation changed in macOS 14.
        // `shell` returns "" when the command fails, so the exit status is the
        // only reliable way to detect a ditto error.
        let copy = ProcessMonitor.run("/usr/bin/ditto", ["--noqtn", source.path, stagingItem.path])
        guard copy.status == 0 else {
            cleanup(staging)
            let detail = copy.error.trimmingCharacters(in: .whitespacesAndNewlines)
            return fail(L("ditto failed (code %d)%@.", copy.status, detail.isEmpty ? "" : ": \(detail)"))
        }
        if isCancelled() {
            cleanup(staging)
            return fail(L("Cancelled during the copy."))
        }

        // --- 3. Verification ---
        entry.phase = .verifying
        write(entry)
        progress(.verifying, L("Checking %d files…", measured.files), 0.62)

        let copied = measure(stagingItem, isCancelled: isCancelled)
        // 0.5% byte tolerance: `ditto` can differ due to blocks and clones.
        let byteDelta = abs(copied.bytes - measured.bytes)
        let tolerance = Int64(Double(measured.bytes) * 0.005) + 4096
        guard copied.files == measured.files, byteDelta <= tolerance else {
            cleanup(staging)
            return fail(L("The copy does not match: %d of %d files, %@ of %@. Nothing was moved.", copied.files, measured.files, Fmt.bytes(copied.bytes), Fmt.bytes(measured.bytes)))
        }

        // --- 4. Quarentena do original ---
        entry.phase = .quarantining

        // This is the one write that MUST be confirmed before acting. From the
        // moment the original leaves `source`, the journal is the only map back
        // to it. Every other phase can tolerate a failed write — the next phase
        // writes again while the data is still somewhere predictable. Moving the
        // user's folder with the map unwritten would strand it at a path only
        // this process knows, and this process may not survive to tell anyone.
        guard write(entry) else {
            cleanup(staging)
            return fail(L("Could not write the migration journal — nothing was moved. Check the disk."))
        }
        progress(.quarantining, L("Moving the original into quarantine…"), 0.72)

        do {
            try fm.createDirectory(at: quarantine, withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: quarantineItem)
        } catch {
            cleanup(staging)
            return fail(L("Could not move the original: %@", error.localizedDescription))
        }

        // --- 5. Publish at the destination ---
        entry.phase = .publishing
        write(entry)
        progress(.publishing, L("Publishing to the destination…"), 0.80)

        do {
            try fm.moveItem(at: stagingItem, to: target)
        } catch {
            // Rollback: put the original back.
            let restored = putBack(quarantineItem, at: source)
            if restored { cleanup(quarantine) }
            cleanup(staging)
            entry.phase = restored ? .rolledBack : .failed
            write(entry)
            // These used to be one message that always claimed "original
            // restored" — asserting a state the code had never checked, in the
            // one dialog where the user decides whether their data is safe.
            return restored
                ? fail(L("Failed to publish to the destination, original restored: %@", error.localizedDescription))
                : fail(L("Failed to publish AND the original could not be put back. It is safe in quarantine: %@", entry.quarantinePath.tildeShortened))
        }
        cleanup(staging)

        // --- 6. Symlink ---
        entry.phase = .linking
        write(entry)
        progress(.linking, L("Creating the symlink…"), 0.88)

        do {
            try fm.createSymbolicLink(at: source, withDestinationURL: target)
        } catch {
            // The original is intact in quarantine: putting it back is a local,
            // instant rename. Bringing the copy back from the external volume
            // would be a slow physical copy, which could fail for lack of space
            // and would leave the quarantine orphaned on the disk forever.
            let restored = putBack(quarantineItem, at: source)
            try? fm.removeItem(at: target)
            if restored { cleanup(quarantine) }
            entry.phase = restored ? .rolledBack : .failed
            write(entry)
            return restored
                ? fail(L("Failed to create the link, the original was restored: %@", error.localizedDescription))
                : fail(L("Failed to create the link AND the original could not be put back. It is safe in quarantine: %@", entry.quarantinePath.tildeShortened))
        }

        // --- 7. Validate through the link ---
        entry.phase = .validating
        write(entry)
        progress(.validating, L("Testing reading and writing through the link…"), 0.94)

        if let problem = validate(link: source, expectedFiles: measured.files, isCancelled: isCancelled) {
            try? fm.removeItem(at: source)              // removes only the link
            let restored = putBack(quarantineItem, at: source)
            try? fm.removeItem(at: target)
            if restored { cleanup(quarantine) }
            entry.phase = restored ? .rolledBack : .failed
            write(entry)
            return restored
                ? fail(L("The link failed the test, everything was rolled back: %@", problem))
                : fail(L("The link failed the test AND the original could not be put back. It is safe in quarantine: %@", entry.quarantinePath.tildeShortened))
        }

        entry.phase = .done
        entry.finishedAt = Date()
        write(entry)
        progress(.done, L("Done"), 1.0)

        return MigrationOutcome(
            entry: entry,
            succeeded: true,
            message: L("%@ moved. The original stays in quarantine until you release it.", Fmt.bytes(measured.bytes))
        )
    }

    /// Returns the original from quarantine to its place, and says whether it
    /// actually got there.
    ///
    /// Every rollback path used to do this with `try?` and then report "the
    /// original was restored" unconditionally. If that rename failed — volume
    /// full, permissions, the folder recreated by an app mid-migration — the
    /// message asserted a state that was never verified, in exactly the moment
    /// the user needs the truth most. This is the app that promises to never
    /// lie about deletions; it cannot lie about restorations either.
    private func putBack(_ quarantineItem: URL, at source: URL) -> Bool {
        do {
            try fm.moveItem(at: quarantineItem, to: source)
            return true
        } catch {
            Trace.mark("putBack FAILED: \(quarantineItem.path) → \(source.path): \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Reverter

    /// Undoes a migration: deletes the link, restores the original from
    /// quarantine and removes the copy at the destination.
    func restore(_ entry: MigrationJournalEntry) -> MigrationOutcome {
        var updated = entry
        let source = URL(fileURLWithPath: entry.sourcePath)
        let target = URL(fileURLWithPath: entry.targetPath)
        let quarantine = URL(fileURLWithPath: entry.quarantinePath)

        guard fm.fileExists(atPath: quarantine.path) else {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("The original is no longer in quarantine — there is no way to undo."))
        }

        // Removes the link (never the target: removeItem on a symlink deletes only the link).
        if VolumeResolver.isSymbolicLink(source) {
            try? fm.removeItem(at: source)
        } else if fm.fileExists(atPath: source.path) {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("Something real already exists at %@. Resolve it manually before undoing.", entry.sourcePath.tildeShortened))
        }

        do {
            try fm.moveItem(at: quarantine, to: source)
        } catch {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("Failed to restore the original: %@", error.localizedDescription))
        }

        // The copy at the destination becomes junk — to the Trash, not deleted.
        // Trashing across volumes can fail (some external disks have no .Trashes
        // the user can write to); that must not fail the restore, but it must
        // not be silent either, or the stale copy quietly eats the external disk.
        var leftoverNote = ""
        if fm.fileExists(atPath: target.path) {
            do {
                try fm.trashItem(at: target, resultingItemURL: nil)
            } catch {
                leftoverNote = " " + L("The old copy could not be moved to the Trash and is still at %@.", entry.targetPath.tildeShortened)
            }
        }
        cleanup(quarantine.deletingLastPathComponent())

        updated.phase = .rolledBack
        updated.finishedAt = Date()
        write(updated)

        return MigrationOutcome(entry: updated, succeeded: true,
                                message: L("%@ is back in its original place.", updated.name) + leftoverNote)
    }

    /// Releases the quarantine of a completed migration — this is where the
    /// space genuinely returns to the Mac's disk.
    func releaseQuarantine(_ entry: MigrationJournalEntry) -> MigrationOutcome {
        var updated = entry
        let quarantine = URL(fileURLWithPath: entry.quarantinePath)

        guard fm.fileExists(atPath: quarantine.path) else {
            return MigrationOutcome(entry: entry, succeeded: true, message: L("Quarantine was already empty."))
        }
        // Verifies the link and target are sound before letting the original go.
        guard VolumeResolver.isSymbolicLink(URL(fileURLWithPath: entry.sourcePath)),
              fm.fileExists(atPath: entry.targetPath) else {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("The link or the target is not intact. Quarantine stays where it is."))
        }

        do {
            try fm.trashItem(at: quarantine, resultingItemURL: nil)
        } catch {
            return MigrationOutcome(entry: entry, succeeded: false,
                                    message: L("Failed to release the quarantine: %@", error.localizedDescription))
        }

        updated.quarantinePath = ""
        write(updated)
        return MigrationOutcome(entry: updated, succeeded: true,
                                message: L("%@ freed on the Mac's disk.", Fmt.bytes(entry.bytes)))
    }

    // MARK: - Auxiliares

    private struct Measurement {
        var bytes: Int64
        var files: Int
        /// Entries the walk could not read. When this is nonzero on the SOURCE,
        /// the whole verification is standing on sand: `files` undercounts, so
        /// an equally incomplete copy compares as equal.
        var unreadable: Int = 0
    }

    /// Counts files and bytes. Used to size the job, then to verify it.
    private func measure(_ url: URL, isCancelled: () -> Bool) -> Measurement {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

        var isDirectory = false
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) {
            isDirectory = values.isDirectory ?? false
        }

        if !isDirectory {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            return Measurement(bytes: size, files: 1)
        }

        var bytes: Int64 = 0
        var files = 0
        var unreadable = 0

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                return true
            }
        ) else { return Measurement(bytes: 0, files: 0, unreadable: 1) }

        for case let item as URL in enumerator {
            if isCancelled() { break }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else {
                // This `continue` used to discard the item without a trace, and
                // that mattered more than it looks: this count is one side of
                // the copy verification. A source with unreadable files produced
                // a smaller `measured`, the incomplete copy then MATCHED it, and
                // the original went to quarantine on the strength of a
                // verification that verified nothing. Skipping is still right —
                // counting the skip is what was missing.
                unreadable += 1
                continue
            }
            guard values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return Measurement(bytes: bytes, files: files, unreadable: unreadable)
    }

    /// Verifies the link resolves, the count matches, and that writing through it
    /// works — that last test is what catches a read-only mounted volume.
    private func validate(link: URL, expectedFiles: Int, isCancelled: () -> Bool) -> String? {
        guard VolumeResolver.isSymbolicLink(link) else {
            return L("the link was not created")
        }
        guard let target = VolumeResolver.symlinkTarget(of: link),
              fm.fileExists(atPath: target.path) else {
            return L("the link does not resolve to an existing path")
        }

        let through = measure(link, isCancelled: isCancelled)
        guard through.files == expectedFiles else {
            return L("reading through the link gives %d files instead of %d", through.files, expectedFiles)
        }

        // Writes and deletes a test file inside the target.
        var isDirectory = false
        if let values = try? target.resourceValues(forKeys: [.isDirectoryKey]) {
            isDirectory = values.isDirectory ?? false
        }
        if isDirectory {
            let probe = link.appendingPathComponent(".savemymac-probe")
            do {
                try Data("ok".utf8).write(to: probe)
                try fm.removeItem(at: probe)
            } catch {
                return L("could not write through the link (%@)", error.localizedDescription)
            }
        }

        return nil
    }

    private func cleanup(_ url: URL) {
        guard fm.fileExists(atPath: url.path) else { return }
        try? fm.removeItem(at: url)
    }
}
