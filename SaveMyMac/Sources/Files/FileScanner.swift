import Foundation

/// Comparação integral de conteúdo.
///
/// A varredura usa hash de amostras porque precisa ser rápida em centenas de
/// milhares de arquivos. Mas amostrar início, meio e fim pode coincidir em
/// arquivos diferentes — dois discos de VM clonados e depois divergidos no
/// meio, por exemplo. Como apagar duplicado é irreversível na prática, cada
/// cópia é conferida byte a byte contra a original **antes** de sair.
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

// MARK: - Classificação para o treemap

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
        case .backup: return "Backups"
        case .audio: return L("Audio")
        case .image: return "Imagens"
        case .archive: return "Compactados"
        case .data: return L("Databases")
        case .other: return "Outros"
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

    /// Ordem no treemap: do mais "descarregável" para o menos.
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
        case ..<1: return "hoje"
        case ..<30: return "\(days) dias"
        case ..<365:
            let months = max(1, days / 30)
            return months == 1 ? L("1 month") : "\(months) meses"
        default:
            let years = max(1, days / 365)
            return years == 1 ? "1 ano" : "\(years) anos"
        }
    }
}

struct TreemapSlice: Identifiable {
    var id: String { kind.rawValue }
    var kind: FileKind
    var bytes: Int64
    var count: Int
}

// MARK: - Duplicados agrupados

struct DuplicateCopy: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var modified: Date?
    /// A cópia mais antiga é a preservada.
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

    /// Espaço recuperável: tudo menos a cópia preservada.
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

    var largeTotal: Int64 { largeFiles.reduce(0) { $0 + $1.size } }
    var duplicateTotal: Int64 { duplicates.reduce(0) { $0 + $1.reclaimable } }
    var isEmpty: Bool { largeFiles.isEmpty && duplicates.isEmpty }
}

/// Varre a pasta pessoal uma única vez e produz, da mesma passada, a lista de
/// arquivos grandes com o treemap e os grupos de duplicados.
final class FileScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private let largeThreshold: Int64 = 500 * 1024 * 1024
    private let duplicateThreshold: Int64 = 2 * 1024 * 1024

    private let excludedNames: Set<String> = [
        "Library", ".Trash", "node_modules", ".git", ".svn",
        ".npm", ".cache", ".cargo", ".gradle", ".m2", ".pub-cache",
        "Applications", "OrbStack"
    ]

    private let packageExtensions: Set<String> = [
        "photoslibrary", "app", "framework", "bundle", "musiclibrary",
        "tvlibrary", "aplibrary", "xcodeproj", "xcworkspace"
    ]

    private struct Entry {
        var url: URL
        /// Bytes ocupados em disco — é o que interessa na lista de grandes.
        var size: Int64
        /// Tamanho lógico do conteúdo — é o que interessa para duplicados,
        /// porque clones e arquivos esparsos têm alocado diferente do lógico.
        var logicalSize: Int64
        var modified: Date?
    }

    // MARK: - Entrada

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> FileScanResult {

        var result = FileScanResult()

        progress(L("Walking the home folder…"), 0.03)
        let entries = enumerateHome(isCancelled: isCancelled) { visited in
            progress("Percorrendo a pasta pessoal… (\(visited) arquivos)",
                     0.03 + min(0.52, Double(visited) / 250_000.0 * 0.52))
        }
        result.scannedFiles = entries.count

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

    // MARK: - Varredura

    private func enumerateHome(
        isCancelled: () -> Bool,
        progress: (Int) -> Void
    ) -> [Entry] {

        var entries: [Entry] = []
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey,
            .contentModificationDateKey, .isSymbolicLinkKey, .isUbiquitousItemKey
        ]

        guard let enumerator = fm.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return entries }

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
        return entries
    }

    // MARK: - Duplicados

    private func findDuplicates(
        in entries: [Entry],
        isCancelled: () -> Bool,
        progress: (Double) -> Void
    ) -> [DuplicateGroup] {

        // Passo 1: agrupa por tamanho LÓGICO exato em bytes.
        var bySize: [Int64: [Entry]] = [:]
        for entry in entries where entry.logicalSize >= duplicateThreshold {
            bySize[entry.logicalSize, default: []].append(entry)
        }
        let candidates = bySize.filter { $0.value.count > 1 && $0.value.count <= 60 }

        var groups: [DuplicateGroup] = []
        let total = max(1, candidates.count)
        var processed = 0

        // Passo 2: dentro de cada grupo de tamanho, compara amostras de conteúdo.
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
                // A cópia mais antiga é a preservada.
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

    /// FNV-1a sobre três amostras de 256 KB (início, meio e fim). Combinado com
    /// igualdade exata de tamanho, é rápido e suficiente na prática.
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
