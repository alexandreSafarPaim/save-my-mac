import Foundation

/// Inventories the symlinks in the home folder that point off the Mac's disk —
/// the "offload a heavy folder to an external SSD" pattern.
///
/// Entirely read-only: nothing is created, moved or deleted here.
final class OffloadScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Maximum depth from home. Covers the real cases (`~/.gradle`,
    /// `~/Library/Android/sdk`, `~/Library/Application Support/X/y`) without
    /// walking the entire tree.
    private let maxDepth = 4

    /// Cap on visited directories, so the scan always finishes quickly.
    private let maxDirectories = 40_000

    /// Never descend here: these are large, noisy and hold no offload links.
    ///
    /// `Containers` and `Group Containers` are essential entries: every sandboxed
    /// app has, inside `Data/`, relative links to the real home's Desktop,
    /// Documents, Downloads, Movies, Music and Pictures. Without the cut, the
    /// inventory would come back with hundreds of irrelevant links and the one the
    /// user actually created would be buried among them.
    private let skipDescend: Set<String> = [
        "node_modules", ".git", ".svn", ".Trash", "DerivedData",
        "Mobile Documents", "CloudStorage", "Pods", ".build", ".next",
        "build", "dist", "target", "vendor",
        "Containers", "Group Containers"
    ]

    private let skipExtensions: Set<String> = [
        "photoslibrary", "app", "framework", "bundle", "musiclibrary",
        "tvlibrary", "aplibrary", "sparsebundle", "xcodeproj", "xcworkspace"
    ]

    // MARK: - Entry point

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> OffloadInventory {

        var inventory = OffloadInventory()
        var visitedDirectories = 0
        var linkURLs: [URL] = []

        progress(L("Looking for symlinks…"), 0.05)
        walk(
            directory: home,
            depth: 0,
            visited: &visitedDirectories,
            found: &linkURLs,
            isCancelled: isCancelled,
            progress: { count in
                progress(L("Looking for symlinks… (%d folders)", count),
                         0.05 + min(0.35, Double(count) / 30_000.0 * 0.35))
            }
        )

        inventory.scannedDirectories = visitedDirectories
        inventory.reachedLimit = visitedDirectories >= maxDirectories

        guard !isCancelled() else { return inventory }

        // Resolves each link and computes the target's real size.
        var entries: [SymlinkEntry] = []
        var acceptedTargets: [String] = []
        let totalLinks = max(1, linkURLs.count)

        for (index, linkURL) in linkURLs.enumerated() {
            if isCancelled() { break }
            let fraction = 0.40 + (Double(index) / Double(totalLinks)) * 0.45
            progress(L("Measuring %@…", linkURL.lastPathComponent), fraction)

            guard let entry = describe(link: linkURL, isCancelled: isCancelled) else { continue }

            // Two nested links to the same target (e.g. `~/.gradle` and
            // `~/.gradle/caches`) would count the same content twice and inflate
            // the "off the Mac's disk" total. Keeps only the outer one.
            if entry.statusRaw == 0 {
                let isNested = acceptedTargets.contains { entry.targetPath.hasPrefix($0 + "/") }
                if isNested { continue }
                acceptedTargets.append(entry.targetPath)
            }

            entries.append(entry)
        }

        // Everything is worth showing, but the space-saving ones come first.
        inventory.links = entries.sorted { lhs, rhs in
            if lhs.savesSpace != rhs.savesSpace { return lhs.savesSpace }
            return lhs.size > rhs.size
        }

        inventory.groups = buildGroups(from: inventory.links)

        if !isCancelled() {
            progress(L("Looking for orphan data at the destination…"), 0.88)
            inventory.orphans = findOrphans(for: inventory.links, isCancelled: isCancelled)
        }

        progress(L("Done"), 1.0)
        return inventory
    }

    // MARK: - Scan

    private func walk(
        directory: URL,
        depth: Int,
        visited: inout Int,
        found: inout [URL],
        isCancelled: () -> Bool,
        // `progress` takes the count as a parameter on purpose: capturing
        // `visitedDirectories` at the call site while it is passed as `inout`
        // would be overlapping access and would crash the app at runtime.
        progress: (Int) -> Void
    ) {
        if isCancelled() || depth > maxDepth || visited >= maxDirectories { return }

        visited += 1
        if visited % 500 == 0 { progress(visited) }

        guard let contents = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []   // inclui ocultos: ~/.gradle, ~/.android etc.
        ) else { return }

        for url in contents {
            if isCancelled() || visited >= maxDirectories { return }

            guard let values = try? url.resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey]
            ) else { continue }

            if values.isSymbolicLink == true {
                found.append(url)
                continue   // nunca descer por dentro de um link
            }

            guard values.isDirectory == true else { continue }

            let name = url.lastPathComponent
            if skipDescend.contains(name) { continue }
            if skipExtensions.contains(url.pathExtension.lowercased()) { continue }

            walk(
                directory: url,
                depth: depth + 1,
                visited: &visited,
                found: &found,
                isCancelled: isCancelled,
                progress: progress
            )
        }
    }

    // MARK: - Describing a link

    private func describe(link: URL, isCancelled: () -> Bool) -> SymlinkEntry? {
        guard let target = VolumeResolver.symlinkTarget(of: link) else { return nil }

        let targetExists = fm.fileExists(atPath: target.path)
        let mountPoint = targetExists ? VolumeResolver.mountPoint(of: target) : nil
        let volumeName = targetExists ? VolumeResolver.volumeName(of: target) : nil

        // Works out whether the intended target is an external volume even when
        // it is absent: "/Volumes/Something/..." is the macOS convention.
        let looksLikeExternal = target.path.hasPrefix("/Volumes/")
        let inferredVolumeName: String? = {
            if let volumeName { return volumeName }
            guard looksLikeExternal else { return nil }
            let parts = target.path.split(separator: "/")
            return parts.count >= 2 ? String(parts[1]) : nil
        }()

        let status: Int
        if !targetExists {
            // Link pendurado: distingue "volume desmontado" de "alvo apagado".
            status = looksLikeExternal && !fm.fileExists(atPath: "/Volumes/\(inferredVolumeName ?? "")")
                ? 1   // volumeMissing
                : 2   // broken
        } else if VolumeResolver.isOnHomeVolume(target) {
            status = 3   // sameDisk
        } else {
            status = 0   // offloaded
        }

        let size: Int64 = status == 0
            ? DiskMonitor.directorySize(at: target, isCancelled: isCancelled)
            : 0

        // For loose files, directorySize returns 0 — falls back to the direct size.
        let finalSize: Int64 = {
            guard status == 0, size == 0 else { return size }
            return target.allocatedBytes
        }()

        let created = (try? link.resourceValues(forKeys: [.creationDateKey]))?.creationDate

        return SymlinkEntry(
            linkPath: link.path,
            targetPath: target.path,
            targetVolumeName: inferredVolumeName,
            targetMountPoint: mountPoint,
            size: finalSize,
            created: created,
            statusRaw: status
        )
    }

    // MARK: - Agrupamento por volume

    private func buildGroups(from links: [SymlinkEntry]) -> [OffloadVolumeGroup] {
        var buckets: [String: [SymlinkEntry]] = [:]

        for link in links where link.status != .sameDisk {
            // Chave: ponto de montagem real, ou o inferido de /Volumes/<nome>.
            let key = link.targetMountPoint
                ?? (link.targetVolumeName.map { "/Volumes/\($0)" })
                ?? "desconhecido"
            buckets[key, default: []].append(link)
        }

        return buckets.map { mountPoint, groupLinks in
            let isMounted = fm.fileExists(atPath: mountPoint)
            let capacity = isMounted ? VolumeResolver.capacity(ofMountPoint: mountPoint) : nil
            let name = groupLinks.compactMap(\.targetVolumeName).first
                ?? (mountPoint as NSString).lastPathComponent

            return OffloadVolumeGroup(
                name: name,
                mountPoint: mountPoint,
                isMounted: isMounted,
                capacityTotal: capacity?.total ?? 0,
                capacityAvailable: capacity?.available ?? 0,
                links: groupLinks.sorted { $0.size > $1.size }
            )
        }
        .sorted { $0.offloadedSize > $1.offloadedSize }
    }

    // MARK: - Orphan data at the destination

    /// Looks, in the targets' parent folders, for items that are not the target
    /// of any link. In the `/Volumes/X/mac-offload/*` pattern, this finds folders
    /// left over from a removed link that are still taking up the external disk.
    ///
    /// A parent folder is only considered if **most of what is in it is already a
    /// link target** — that is, if it really is a dedicated offload area. Without
    /// that check, a link pointing into some arbitrary folder on a working disk
    /// would make the app flag as "orphan" every file the user deliberately kept
    /// there.
    private func findOrphans(
        for links: [SymlinkEntry],
        isCancelled: () -> Bool
    ) -> [OrphanEntry] {

        let knownTargets = Set(
            links.map { URL(fileURLWithPath: $0.targetPath).standardizedFileURL.path }
        )

        // Distinct parent folders of the targets that are actually mounted.
        var parents = Set<String>()
        for link in links where link.status == .offloaded {
            let parent = URL(fileURLWithPath: link.targetPath)
                .deletingLastPathComponent().standardizedFileURL
            // Doesn't go up to the volume root: it only makes sense in a dedicated folder.
            guard parent.path != "/", parent.path.split(separator: "/").count >= 3 else { continue }
            parents.insert(parent.path)
        }

        var orphans: [OrphanEntry] = []

        for parentPath in parents.sorted() {
            if isCancelled() { break }
            let parent = URL(fileURLWithPath: parentPath)
            guard let contents = try? fm.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            // Confirms this folder is a dedicated offload area.
            let known = contents.filter { knownTargets.contains($0.standardizedFileURL.path) }.count
            guard contents.count > 1, known * 2 >= contents.count else { continue }

            for url in contents {
                if isCancelled() { break }
                let path = url.standardizedFileURL.path
                guard !knownTargets.contains(path) else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 10 * 1024 * 1024 else { continue }

                orphans.append(OrphanEntry(
                    path: path,
                    size: size,
                    modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate,
                    volumeName: VolumeResolver.volumeName(of: url) ?? "—"
                ))
            }
        }

        return orphans.sorted { $0.size > $1.size }
    }
}
