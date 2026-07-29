import Foundation

struct VolumeInfo: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var total: Int64
    var available: Int64
    var isRemovable: Bool
    var isInternal: Bool

    var used: Int64 { max(0, total - available) }

    var usedFraction: Double {
        total <= 0 ? 0 : Double(used) / Double(total)
    }
}

enum DiskMonitor {

    static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsInternalKey,
            .volumeIsBrowsableKey,
            .volumeIsLocalKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return [rootVolumeFallback()]
        }

        var result: [VolumeInfo] = []

        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.volumeIsLocal ?? true else { continue }
            guard values.volumeIsBrowsable ?? true else { continue }

            let total = Int64(values.volumeTotalCapacity ?? 0)
            guard total > 0 else { continue }

            // "ForImportantUsage" is the number Finder shows (includes purgeable space).
            let available = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)

            result.append(VolumeInfo(
                name: values.volumeName ?? url.lastPathComponent,
                path: url.path,
                total: total,
                available: max(0, available),
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? true
            ))
        }

        if result.isEmpty { result = [rootVolumeFallback()] }

        // Volume de boot primeiro, depois por tamanho decrescente.
        return result.sorted { lhs, rhs in
            let lhsIsRoot = lhs.path == "/"
            let rhsIsRoot = rhs.path == "/"
            if lhsIsRoot != rhsIsRoot { return lhsIsRoot }
            return lhs.total > rhs.total
        }
    }

    private static func rootVolumeFallback() -> VolumeInfo {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        return VolumeInfo(
            name: "Macintosh HD",
            path: "/",
            total: Int64(values?.volumeTotalCapacity ?? 0),
            available: values?.volumeAvailableCapacityForImportantUsage ?? 0,
            isRemovable: false,
            isInternal: true
        )
    }

    /// A directory's recursive size (bytes allocated on disk).
    static func directorySize(at url: URL, isCancelled: () -> Bool = { false }) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let item as URL in enumerator {
            if isCancelled() { return total }
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
