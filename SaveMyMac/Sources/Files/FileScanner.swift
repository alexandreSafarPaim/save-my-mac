import Foundation

/// Full content comparison.
///
/// The scan uses a sampled hash because it has to be fast across hundreds of
/// thousands of files. But sampling the start, middle and end can collide across
/// different files — two VM disks cloned and later diverged in the middle, for
/// instance. Since deleting a duplicate is irreversible in practice, every copy
/// is checked byte by byte against the original **before** it goes.
enum FileComparator {

    static func identical(_ a: URL, _ b: URL) -> Bool {
        guard a.standardizedFileURL != b.standardizedFileURL else { return false }
        guard let ha = try? FileHandle(forReadingFrom: a),
              let hb = try? FileHandle(forReadingFrom: b) else { return false }
        defer {
            try? ha.close()
            try? hb.close()
        }

        let chunk = 1 << 20   // 1 MB
        while true {
            let da = (try? ha.read(upToCount: chunk)) ?? Data()
            let db = (try? hb.read(upToCount: chunk)) ?? Data()
            if da != db { return false }
            if da.isEmpty { return true }
        }
    }
}

// MARK: - Classification for the treemap

enum FileKind: String, CaseIterable, Identifiable {
    case video
    case virtualMachine
    case diskImage
    case backup
    case audio
    case image
    case archive
    case data
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .video: return L("Videos")
        case .virtualMachine: return L("Virtual machines")
        case .diskImage: return L("Disk images")
        case .backup: return L("Backups")
        case .audio: return L("Audio")
        case .image: return L("Images")
        case .archive: return L("Archives")
        case .data: return L("Databases")
        case .other: return L("Other")
        }
    }

    var symbol: String {
        switch self {
        case .video: return "film"
        case .virtualMachine: return "cube.transparent"
        case .diskImage: return "opticaldisc"
        case .backup: return "clock.arrow.circlepath"
        case .audio: return "waveform"
        case .image: return "photo"
        case .archive: return "doc.zipper"
        case .data: return "cylinder.split.1x2"
        case .other: return "doc"
        }
    }

    /// Treemap order: from most "offloadable" to least.
    var rank: Int {
        switch self {
        case .video: return 0
        case .virtualMachine: return 1
        case .diskImage: return 2
        case .backup: return 3
        case .archive: return 4
        case .audio: return 5
        case .image: return 6
        case .data: return 7
        case .other: return 8
        }
    }

    static func of(_ url: URL) -> FileKind {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        if ["mov", "mp4", "m4v", "avi", "mkv", "prores", "braw", "r3d", "mxf", "webm", "flv"].contains(ext) {
            return .video
        }
        if ["vmdk", "vdi", "qcow2", "hds", "pvm", "vbox", "utm", "img", "raw"].contains(ext)
            || name.contains(".pvm") || url.path.contains("/Parallels/")
            || url.path.contains("/Virtual Machines") || url.path.contains("/UTM/") {
            return .virtualMachine
        }
        if ["dmg", "iso", "sparsebundle", "sparseimage", "cdr", "pkg", "mpkg"].contains(ext) {
            return .diskImage
        }
        if ["backup", "bak", "tm", "aplibrary"].contains(ext)
            || name.contains("backup") || url.path.contains("/MobileSync/") {
            return .backup
        }
        if ["wav", "aiff", "aif", "flac", "mp3", "m4a", "caf", "logicx"].contains(ext) {
            return .audio
        }
        if ["psd", "psb", "tiff", "tif", "raw", "cr2", "cr3", "nef", "arw", "dng", "heic", "png", "jpg", "jpeg"].contains(ext) {
            return .image
        }
        if ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst"].contains(ext) {
            return .archive
        }
        if ["sqlite", "db", "sql", "dump", "realm", "parquet", "csv", "jsonl", "safetensors", "ckpt", "gguf", "bin", "pt", "pth", "onnx"].contains(ext) {
            return .data
        }
        return .other
    }
}

struct LargeFile: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var name: String
    var size: Int64
    var modified: Date?
    var kindRaw: String

    var kind: FileKind { FileKind(rawValue: kindRaw) ?? .other }
    var directory: String {
        (path as NSString).deletingLastPathComponent
    }

    var ageLabel: String {
        guard let modified else { return "—" }
        let days = Calendar.current.dateComponents([.day], from: modified, to: Date()).day ?? 0
        switch days {
        case ..<1: return L("today")
        case ..<30: return Lp("%d day", "%d days", count: days)
        case ..<365: return Lp("%d month", "%d months", count: max(1, days / 30))
        default: return Lp("%d year", "%d years", count: max(1, days / 365))
        }
    }
}

struct TreemapSlice: Identifiable {
    var id: String { kind.rawValue }
    var kind: FileKind
    var bytes: Int64
    var count: Int
}

// MARK: - Grouped duplicates

struct DuplicateCopy: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var modified: Date?
    /// The oldest copy is the one preserved.
    var isOriginal: Bool

    var directory: String {
        ((path as NSString).deletingLastPathComponent).tildeShortened
    }
}

struct DuplicateGroup: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var fileSize: Int64
    var copies: [DuplicateCopy]
    var kindRaw: String

    var kind: FileKind { FileKind(rawValue: kindRaw) ?? .other }
    var copyCount: Int { copies.count }

    /// Reclaimable space: everything except the preserved copy.
    var reclaimable: Int64 {
        Int64(max(0, copies.count - 1)) * fileSize
    }

    var removable: [DuplicateCopy] {
        copies.filter { !$0.isOriginal }
    }
}

// MARK: - Resultado

struct FileScanResult {
    var largeFiles: [LargeFile] = []
    var treemap: [TreemapSlice] = []
    var duplicates: [DuplicateGroup] = []
    var scannedFiles: Int = 0

    /// Files actually visited by the walk.
    ///
    /// Kept separate from `scannedFiles` because the screen was reporting one and
    /// calling it the other. `scannedFiles` counts candidates — entries above the
    /// 2 MB duplicate threshold. Saying "the scan walked 7 files" when it had
    /// visited thousands and found 7 candidates is a number that invites exactly
    /// the wrong conclusion.
    var visitedFiles: Int = 0

    /// Directories the deep walk reported as errors.
    ///
    /// Kept, but it is close to useless and should not be trusted alone.
    /// `FileManager.enumerator` does not surface a TCC denial as an error — it
    /// descends, finds nothing, and continues — so on a Mac where six protected
    /// folders were unreadable this counter stayed at **zero**. That is why
    /// `AccessProbe` exists and why `looksBlocked` no longer depends on this.
    var deniedDirectories: Int = 0

    /// Folders the deep walk errored on, for showing the user which ones.
    var deniedExamples: [String] = []

    /// What the app could actually read, measured per folder rather than
    /// inferred from the walk. See `AccessProbe`.
    var probe = AccessProbe()

    /// Did the scan see so little that permission is the likely explanation?
    ///
    /// Two independent grounds, because one is certain and one is not:
    ///
    ///   1. A folder that *threw* on a shallow listing. No ambiguity.
    ///   2. A folder that came back empty **and** a walk that visited under 200
    ///      files. An empty folder is normal; an empty folder on a Mac whose
    ///      entire home apparently holds 46 files is not.
    ///
    /// The second condition uses `visitedFiles`, not `scannedFiles`. A tidy Mac
    /// can legitimately have few candidates over 2 MB; no home folder has fewer
    /// than a few hundred files in total. Judging by the candidate count would
    /// call a clean machine blocked.
    var looksBlocked: Bool {
        if probe.isDefinitelyBlocked { return true }
        if !probe.suspicious.isEmpty && visitedFiles < 200 { return true }
        return deniedDirectories > 0 && visitedFiles < 200
    }

    /// Folder names to name on screen: the probe's list, falling back to the
    /// walk's if the probe found nothing to report.
    var blockedFolderNames: [String] {
        probe.namesToReport.isEmpty ? deniedExamples : probe.namesToReport
    }

    var largeTotal: Int64 { largeFiles.reduce(0) { $0 + $1.size } }
    var duplicateTotal: Int64 { duplicates.reduce(0) { $0 + $1.reclaimable } }
    var isEmpty: Bool { largeFiles.isEmpty && duplicates.isEmpty }
}

/// Walks the home folder exactly once and produces, from the same pass, the
/// large-file list with its treemap and the duplicate groups.
final class FileScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private let largeThreshold: Int64 = 500 * 1024 * 1024
    private let duplicateThreshold: Int64 = 2 * 1024 * 1024

    /// Folders never descended into.
    ///
    /// `~/Library` used to be on this list and is deliberately **not** any more.
    ///
    /// The reason it was excluded — leave Library to the Cleanup and Offload tabs
    /// — sounded tidy and made this screen useless. Measured on a real Mac: five
    /// files over 500 MB in the entire home folder, all five inside `~/Library`
    /// (a Chrome on-device model, Claude's VM images, a Google updater cache).
    /// Files visible to the scanner: zero. The screen was correct and worthless.
    ///
    /// On modern macOS that is the normal case, not an unlucky one. Application
    /// Support is where apps put multi-gigabyte payloads. A "large files" screen
    /// that cannot see there is not showing large files.
    ///
    /// It is safe here because this screen never deletes: it reveals in Finder,
    /// copies the path, or offers to offload. Cleanup, which does delete, keeps
    /// its own much stricter guards.
    private let excludedNames: Set<String> = [
        ".Trash", "node_modules", ".git", ".svn",
        ".npm", ".cache", ".cargo", ".gradle", ".m2", ".pub-cache",
        "Applications", "OrbStack"
    ]

    private let packageExtensions: Set<String> = [
        "photoslibrary", "app", "framework", "bundle", "musiclibrary",
        "tvlibrary", "aplibrary", "xcodeproj", "xcworkspace"
    ]

    private struct Entry {
        var url: URL
        /// Bytes occupied on disk — what matters for the large-files list.
        var size: Int64
        /// Logical content size — what matters for duplicates, because clones and
        /// sparse files have an allocated size different from the logical one.
        var logicalSize: Int64
        var modified: Date?
    }

    // MARK: - Entry point

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> FileScanResult {

        var result = FileScanResult()

        // Runs before the walk, so a blocked scan is diagnosed even if the walk
        // then returns cleanly with nothing — which is exactly what it does.
        progress(L("Checking folder access…"), 0.01)
        result.probe = AccessProbe.run(home: home)
        Trace.mark(result.probe.traceReport)

        progress(L("Walking the home folder…"), 0.03)
        let walk = enumerateHome(isCancelled: isCancelled) { visited in
            progress(L("Walking the home folder… (%d files)", visited),
                     0.03 + min(0.52, Double(visited) / 250_000.0 * 0.52))
        }
        let entries = walk.entries
        result.scannedFiles = entries.count
        result.visitedFiles = walk.visited
        result.deniedDirectories = walk.denied
        result.deniedExamples = walk.examples

        guard !isCancelled() else { return result }

        progress(L("Sorting the large files…"), 0.60)
        result.largeFiles = entries
            .filter { $0.size >= largeThreshold }
            .sorted { $0.size > $1.size }
            .prefix(120)
            .map { entry in
                LargeFile(
                    path: entry.url.path,
                    name: entry.url.lastPathComponent,
                    size: entry.size,
                    modified: entry.modified,
                    kindRaw: FileKind.of(entry.url).rawValue
                )
            }

        result.treemap = buildTreemap(from: result.largeFiles)

        guard !isCancelled() else { return result }

        progress(L("Comparing content to find duplicates…"), 0.70)
        result.duplicates = findDuplicates(in: entries, isCancelled: isCancelled) { fraction in
            progress(L("Comparing content to find duplicates…"), 0.70 + fraction * 0.28)
        }

        progress(L("Done"), 1.0)
        return result
    }

    // MARK: - Treemap

    private func buildTreemap(from files: [LargeFile]) -> [TreemapSlice] {
        var byKind: [FileKind: (bytes: Int64, count: Int)] = [:]
        for file in files {
            var current = byKind[file.kind] ?? (0, 0)
            current.bytes += file.size
            current.count += 1
            byKind[file.kind] = current
        }
        return byKind
            .map { TreemapSlice(kind: $0.key, bytes: $0.value.bytes, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.kind.rank < rhs.kind.rank
            }
    }

    // MARK: - Scan

    private func enumerateHome(
        isCancelled: () -> Bool,
        progress: (Int) -> Void
    ) -> (entries: [Entry], denied: Int, examples: [String], visited: Int) {

        var entries: [Entry] = []
        var denied = 0
        var deniedExamples: [String] = []
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .isSymbolicLinkKey, .isUbiquitousItemKey
        ]

        guard let enumerator = fm.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            // Still returns `true` — one unreadable folder must not abort the
            // walk. But the error is counted now instead of vanishing. Silently
            // continuing was right; silently forgetting was not.
            errorHandler: { url, _ in
                denied += 1
                if deniedExamples.count < 6 {
                    deniedExamples.append(url.lastPathComponent)
                }
                return true
            }
        ) else { return (entries, denied, deniedExamples, 0) }

        var visited = 0
        for case let url as URL in enumerator {
            if isCancelled() { break }
            visited += 1
            if visited % 5000 == 0 { progress(visited) }

            if excludedNames.contains(url.lastPathComponent)
                || packageExtensions.contains(url.pathExtension.lowercased()) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            if values.isUbiquitousItem == true { continue }

            let logical = Int64(values.fileSize ?? 0)
            let size = Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            guard size >= duplicateThreshold || logical >= duplicateThreshold else { continue }

            entries.append(Entry(
                url: url,
                size: size,
                logicalSize: logical,
                modified: values.contentModificationDate
            ))
            if entries.count > 300_000 { break }
        }

        progress(visited)
        return (entries, denied, deniedExamples, visited)
    }

    // MARK: - Duplicates

    private func findDuplicates(
        in entries: [Entry],
        isCancelled: () -> Bool,
        progress: (Double) -> Void
    ) -> [DuplicateGroup] {

        // Step 1: group by exact LOGICAL size in bytes.
        var bySize: [Int64: [Entry]] = [:]
        for entry in entries where entry.logicalSize >= duplicateThreshold {
            bySize[entry.logicalSize, default: []].append(entry)
        }
        // Every group with more than one member is a candidate.
        //
        // There used to be a `count <= 60` ceiling here, meant to avoid hashing a
        // pathological group of hundreds of same-size files. What it actually did
        // was make large groups vanish with no trace on screen — and large groups
        // are the ones worth the most space. On the Mac this was measured on, a
        // browser cache holds 25 files of exactly 5013504 bytes; sixty-one of them
        // and the whole group would have disappeared silently.
        //
        // Cost of removing the ceiling: the hash reads three 256 KB samples per
        // file, so even a 500-file group is a few hundred milliseconds. The
        // ceiling was buying almost nothing and paying for it with a silent
        // wrong answer — the same trade this project has had to undo repeatedly.
        let candidates = bySize.filter { $0.value.count > 1 }

        var groups: [DuplicateGroup] = []
        let total = max(1, candidates.count)
        var processed = 0

        // Step 2: within each size group, compare content samples.
        for (size, group) in candidates {
            if isCancelled() { break }
            processed += 1
            if processed % 40 == 0 { progress(Double(processed) / Double(total)) }

            var byHash: [UInt64: [Entry]] = [:]
            for entry in group {
                guard let hash = sampleHash(of: entry.url, size: entry.logicalSize) else { continue }
                byHash[hash, default: []].append(entry)
            }

            for (_, matches) in byHash where matches.count > 1 {
                // The oldest copy is the one preserved.
                let sorted = matches.sorted {
                    ($0.modified ?? .distantPast) < ($1.modified ?? .distantPast)
                }
                let copies = sorted.enumerated().map { index, entry in
                    DuplicateCopy(
                        path: entry.url.path,
                        modified: entry.modified,
                        isOriginal: index == 0
                    )
                }
                groups.append(DuplicateGroup(
                    name: sorted[0].url.lastPathComponent,
                    fileSize: size,
                    copies: copies,
                    kindRaw: FileKind.of(sorted[0].url).rawValue
                ))
            }

            if groups.count > 400 { break }
        }

        progress(1.0)
        return groups.sorted { $0.reclaimable > $1.reclaimable }
    }

    /// FNV-1a over three 256 KB samples (start, middle and end). Combined with
    /// exact size equality, it is fast and sufficient in practice.
    private func sampleHash(of url: URL, size: Int64) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let chunk = 256 * 1024
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        let prime: UInt64 = 0x100_0000_01b3

        var offsets: [UInt64] = [0]
        if size > Int64(chunk) * 3 {
            offsets.append(UInt64(size / 2))
            offsets.append(UInt64(size - Int64(chunk)))
        }

        for offset in offsets {
            do { try handle.seek(toOffset: offset) } catch { continue }
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { continue }
            for byte in data {
                hash = (hash ^ UInt64(byte)) &* prime
            }
        }

        return (hash ^ UInt64(bitPattern: size)) &* prime
    }
}
