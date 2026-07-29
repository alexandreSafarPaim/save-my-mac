import Foundation

/// Scans the disk for what can be removed, grouped by category and risk.
/// Nothing is deleted here — the scan is read-only.
final class CleanupScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    // Large files and duplicates now live in `FileScanner`, each with its own
    // screen. Only the regenerable categories remain here.

    // MARK: - Entry point

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> [CleanupCategory] {

        var categories: [CleanupCategory] = []

        let steps: [(String, () -> CleanupCategory?)] = [
            (L("Application caches"), { self.userCaches(isCancelled) }),
            ("Logs", { self.logs(isCancelled) }),
            (L("Developer tools"), { self.developerJunk(isCancelled) }),
            (L("Package manager caches"), { self.packageManagerCaches(isCancelled) }),
            ("Pastas node_modules antigas", { self.staleNodeModules(isCancelled) }),
            ("Backups de iPhone/iPad", { self.deviceBackups(isCancelled) }),
            (L("Old downloads"), { self.oldDownloads(isCancelled) }),
            ("Instaladores", { self.installers(isCancelled) }),
            ("Sobras de apps removidos", { self.appLeftovers(isCancelled) }),
            (L(".DS_Store files"), { self.dsStoreFiles(isCancelled) })
        ]

        let stepWeight = 1.0 / Double(steps.count)

        for (index, step) in steps.enumerated() {
            if isCancelled() { return categories }
            progress(step.0, Double(index) * stepWeight)
            if let category = step.1(), !category.isEmpty {
                categories.append(category)
            }
        }

        progress(L("Done"), 1.0)
        return categories.sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - 1. User caches

    private func userCaches(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let root = home.appendingPathComponent("Library/Caches")
        // These have annoying side effects if deleted while the app is running.
        let skip: Set<String> = [
            "com.apple.containermanagerd",
            "CloudKit",
            "com.apple.aned",
            "com.apple.iCloudHelper"
        ]

        var items = childItems(of: root, isCancelled: isCancelled) { name in
            !skip.contains(name)
        }

        // Caches dentro de containers de apps sandboxados
        let containers = home.appendingPathComponent("Library/Containers")
        if let apps = try? fm.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil) {
            for app in apps.prefix(400) {
                if isCancelled() { break }
                let cache = app.appendingPathComponent("Data/Library/Caches")
                guard fm.fileExists(atPath: cache.path) else { continue }
                guard freesSpace(cache) else { continue }
                let size = DiskMonitor.directorySize(at: cache, isCancelled: isCancelled)
                guard size > 5 * 1024 * 1024 else { continue }
                items.append(CleanupItem(
                    path: cache.path,
                    displayName: "\(app.lastPathComponent) (cache do container)",
                    size: size,
                    modified: modificationDate(cache),
                    isDirectory: true,
                    note: "Cache interno de app sandboxado"
                ))
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Application caches"),
            subtitle: L("Temporary data the apps recreate on their own"),
            symbol: "shippingbox",
            risk: .safe,
            riskScore: 1,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 2. Logs

    private func logs(_ isCancelled: () -> Bool) -> CleanupCategory? {
        var items = childItems(
            of: home.appendingPathComponent("Library/Logs"),
            isCancelled: isCancelled,
            minimumSize: 1024 * 1024
        )

        // Crash reports
        let crashDirs = [
            "Library/Logs/DiagnosticReports",
            "Library/Application Support/CrashReporter"
        ]
        for relative in crashDirs {
            let url = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard freesSpace(url) else { continue }
            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 512 * 1024 else { continue }
            items.append(CleanupItem(
                path: url.path,
                displayName: url.lastPathComponent,
                size: size,
                modified: modificationDate(url),
                isDirectory: true,
                note: L("Old crash reports")
            ))
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Logs and error reports"),
            subtitle: L("Diagnostic records nobody reads anymore"),
            symbol: "doc.text.magnifyingglass",
            risk: .safe,
            riskScore: 1,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 3. Ferramentas de desenvolvedor

    private func developerJunk(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let candidates: [(String, String, String)] = [
            ("Library/Developer/Xcode/DerivedData", "Xcode — DerivedData",
             L("Intermediate builds; Xcode rebuilds them on the next compile")),
            ("Library/Developer/Xcode/Archives", "Xcode — Archives",
             L("Old distribution archives")),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Xcode — iOS DeviceSupport",
             L("Symbols for iOS versions you probably no longer debug")),
            ("Library/Developer/Xcode/watchOS DeviceSupport", "Xcode — watchOS DeviceSupport",
             L("Old watchOS symbols")),
            ("Library/Developer/Xcode/UserData/IB Support", "Xcode — IB Support",
             "Cache do Interface Builder"),
            ("Library/Developer/CoreSimulator/Caches", "Simuladores — Caches",
             L("Simulator runtime cache")),
            ("Library/Developer/CoreSimulator/Devices", "Simuladores — Dispositivos",
             L("Every simulator you create takes space; Xcode can recreate them")),
            ("Library/Caches/com.apple.dt.Xcode", "Xcode — Cache geral",
             L("Xcode index and download cache")),
            ("Library/Developer/CoreSimulator/Temp", "Simuladores — Temp",
             L("Simulator temporaries")),
            ("Library/Application Support/Code/Cache", "VS Code — Cache", "Cache do editor"),
            ("Library/Application Support/Code/CachedData", "VS Code — CachedData", "Cache do editor"),
            ("Library/Caches/JetBrains", "JetBrains — Cache", L("JetBrains IDE indexes")),
            ("Library/Android/sdk/system-images", "Android SDK — System Images",
             "Imagens de emulador Android (pesadas)"),
            (".android/avd", "Android — Emuladores (AVD)", L("Android virtual machines")),
            ("Library/Containers/com.docker.docker/Data/vms", "Docker — VMs",
             "Disco virtual do Docker Desktop")
        ]

        var items: [CleanupItem] = []
        for (relative, name, note) in candidates {
            if isCancelled() { break }
            let url = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard freesSpace(url) else { continue }
            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 1024 * 1024 else { continue }
            items.append(CleanupItem(
                path: url.path,
                displayName: name,
                size: size,
                modified: modificationDate(url),
                isDirectory: true,
                note: note
            ))
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Developer tools"),
            subtitle: L("Builds, symbols and simulators — usually the biggest win on a dev Mac"),
            symbol: "hammer",
            risk: .caution,
            riskScore: 5,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 4. Caches de gerenciadores de pacotes

    private func packageManagerCaches(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let candidates: [(String, String)] = [
            (".npm/_cacache", "npm"),
            (".yarn/cache", "Yarn"),
            ("Library/Caches/Yarn", "Yarn (legado)"),
            (".pnpm-store", "pnpm"),
            ("Library/pnpm/store", "pnpm (store)"),
            (".bun/install/cache", "Bun"),
            ("Library/Caches/deno", "Deno"),
            ("Library/Caches/pip", "pip"),
            ("Library/Caches/pypoetry", "Poetry"),
            (".cache/uv", "uv"),
            ("Library/Caches/Homebrew", "Homebrew"),
            (".cargo/registry/cache", "Cargo (Rust)"),
            (".gradle/caches", "Gradle"),
            (".m2/repository", "Maven"),
            ("Library/Caches/go-build", "Go (build)"),
            ("go/pkg/mod/cache/download", "Go (modules)"),
            ("Library/Caches/CocoaPods", "CocoaPods"),
            ("Library/Caches/composer", "Composer (PHP)"),
            (".nuget/packages", "NuGet"),
            (".rustup/toolchains", "rustup (toolchains)"),
            ("Library/Caches/ms-playwright", "Playwright (navegadores)"),
            (".cache/puppeteer", "Puppeteer (navegadores)")
        ]

        var items: [CleanupItem] = []
        for (relative, name) in candidates {
            if isCancelled() { break }
            let url = home.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard freesSpace(url) else { continue }
            let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
            guard size > 1024 * 1024 else { continue }
            items.append(CleanupItem(
                path: url.path,
                displayName: name,
                size: size,
                modified: modificationDate(url),
                isDirectory: true,
                note: L("It will be downloaded again when needed")
            ))
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Package manager caches"),
            subtitle: L("npm, pip, Homebrew, Gradle and similar"),
            symbol: "arrow.down.circle",
            risk: .caution,
            riskScore: 4,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 5. node_modules abandonados

    private func staleNodeModules(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let cutoff = Date().addingTimeInterval(-90 * 86_400)
        var items: [CleanupItem] = []

        let roots = ["Developer", "Projects", "projetos", "Documents", "Sites", "code", "Code", "dev", "src", "work"]
            .map { home.appendingPathComponent($0) }
            .filter { fm.fileExists(atPath: $0.path) && freesSpace($0) }

        for root in roots {
            if isCancelled() { break }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { break }
                guard url.lastPathComponent == "node_modules" else { continue }
                enumerator.skipDescendants()
                guard freesSpace(url) else { continue }

                let modified = modificationDate(url)
                guard let modified, modified < cutoff else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 20 * 1024 * 1024 else { continue }

                items.append(CleanupItem(
                    path: url.path,
                    displayName: url.deletingLastPathComponent().lastPathComponent + "/node_modules",
                    size: size,
                    modified: modified,
                    isDirectory: true,
                    note: L("No changes since %@ — recoverable with npm install", Fmt.shortDate(modified))
                ))
                if items.count >= 100 { break }
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("abandoned node_modules"),
            subtitle: L("Projects with no activity for over 90 days"),
            symbol: "folder.badge.minus",
            risk: .caution,
            riskScore: 4,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 6. Backups de dispositivos

    private func deviceBackups(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let root = home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        let items = childItems(of: root, isCancelled: isCancelled, minimumSize: 1024 * 1024)
            .map { item -> CleanupItem in
                var copy = item
                copy.note = L("Local iPhone/iPad backup — confirm you have an iCloud backup before removing")
                return copy
            }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Local iPhone/iPad backups"),
            subtitle: L("Usually the biggest hidden files on the Mac"),
            symbol: "iphone.gen3",
            risk: .review,
            riskScore: 8,
            items: items
        )
    }

    // The Trash deliberately left this file.
    //
    // It became its own card on the Cleanup tab, backed by `TrashManager`. The
    // reason is a real bug: in the default mode ("Move to Trash") the remover
    // called `trashItem` on something already in the Trash — Cocoa either returns
    // an error or, worse, renames it inside the Trash and the app reported success
    // without freeing a byte. Emptying is always permanent, so it cannot share the
    // path the other categories take.

    // MARK: - 8. Downloads antigos

    private func oldDownloads(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let root = home.appendingPathComponent("Downloads")
        let cutoff = Date().addingTimeInterval(-90 * 86_400)

        let items = childItems(of: root, isCancelled: isCancelled, minimumSize: 1024 * 1024)
            .filter { item in
                guard let modified = item.modified else { return false }
                return modified < cutoff
            }
            .map { item -> CleanupItem in
                var copy = item
                copy.note = L("Downloaded %@", Fmt.relativeDate(item.modified))
                return copy
            }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Old downloads"),
            subtitle: L("Unused for over 90 days"),
            symbol: "arrow.down.doc",
            risk: .review,
            riskScore: 6,
            items: items
        )
    }

    // MARK: - 9. Instaladores

    private func installers(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso"]
        let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        var items: [CleanupItem] = []

        for root in roots {
            if isCancelled() { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                guard freesSpace(url) else { continue }
                let size = fileSize(url)
                guard size > 5 * 1024 * 1024 else { continue }
                items.append(CleanupItem(
                    path: url.path,
                    displayName: url.lastPathComponent,
                    size: size,
                    modified: modificationDate(url),
                    isDirectory: false,
                    note: L("Installer in %@ — the installed app does not need it", root.lastPathComponent)
                ))
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Installers (.dmg, .pkg, .iso)"),
            subtitle: L("Installer images that already did their job"),
            symbol: "externaldrive.badge.xmark",
            risk: .caution,
            riskScore: 3,
            items: items.sorted { $0.size > $1.size }
        )
    }

    // MARK: - 10. Sobras de apps removidos

    private func appLeftovers(_ isCancelled: () -> Bool) -> CleanupCategory? {
        let installed = installedBundleIdentifiers()
        guard !installed.isEmpty else { return nil }

        let searchDirs = [
            "Library/Application Support",
            "Library/Containers",
            "Library/Saved Application State",
            "Library/HTTPStorages"
        ]

        var items: [CleanupItem] = []

        for relative in searchDirs {
            if isCancelled() { break }
            let root = home.appendingPathComponent(relative)
            guard let contents = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents.prefix(600) {
                if isCancelled() { break }
                var name = url.lastPathComponent
                if name.hasSuffix(".savedState") { name = String(name.dropLast(11)) }

                // Only folders named like a bundle id (with dots) and not Apple's
                guard name.contains("."), !name.hasPrefix("com.apple.") else { continue }
                // Prefix match: `com.foo.App.Helper` and
                // `com.foo.App.binarycookies` belong to `com.foo.app` and must not
                // be treated as leftovers from an uninstalled app.
                let lowerName = name.lowercased()
                guard !installed.contains(where: { lowerName == $0 || lowerName.hasPrefix($0 + ".") })
                else { continue }
                guard freesSpace(url) else { continue }
                // Ignora prefixos conhecidos do sistema
                guard !name.hasPrefix("com.microsoft.autoupdate"),
                      !name.hasPrefix("CrashReporter") else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                guard size > 5 * 1024 * 1024 else { continue }

                items.append(CleanupItem(
                    path: url.path,
                    displayName: name,
                    size: size,
                    modified: modificationDate(url),
                    isDirectory: true,
                    note: L("No installed app matches this identifier (%@)", relative.tildeShortened)
                ))
            }
        }

        guard !items.isEmpty else { return nil }
        return CleanupCategory(
            name: L("Leftovers from uninstalled apps"),
            subtitle: L("Support data with no matching application"),
            symbol: "app.badge.checkmark",
            risk: .review,
            riskScore: 7,
            items: items.sorted { $0.size > $1.size }
        )
    }

    private func installedBundleIdentifiers() -> Set<String> {
        var ids = Set<String>()
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices"),
            home.appendingPathComponent("Applications")
        ]

        for root in roots {
            guard let contents = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for app in contents where app.pathExtension == "app" {
                let plist = app.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let dict = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil
                      ) as? [String: Any],
                      let bundleID = dict["CFBundleIdentifier"] as? String
                else { continue }
                ids.insert(bundleID.lowercased())
            }
        }
        return ids
    }

    // MARK: - 11. .DS_Store

    private func dsStoreFiles(_ isCancelled: () -> Bool) -> CleanupCategory? {
        var totalSize: Int64 = 0
        var count = 0
        var paths: [String] = []

        let roots = ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0) }
        for root in roots {
            if isCancelled() { break }
            guard freesSpace(root) else { continue }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                if isCancelled() { break }
                guard url.lastPathComponent == ".DS_Store" else { continue }
                totalSize += fileSize(url)
                count += 1
                if paths.count < 5000 { paths.append(url.path) }
            }
        }

        guard count > 0, let first = paths.first else { return nil }
        // Grouped into a single item so the list isn't polluted with thousands of rows.
        let item = CleanupItem(
            path: first,
            displayName: "\(count) arquivos .DS_Store",
            size: totalSize,
            modified: nil,
            isDirectory: false,
            note: L("Finder view metadata — recreated automatically"),
            extraPaths: Array(paths.dropFirst())
        )
        return CleanupCategory(
            name: L(".DS_Store files"),
            subtitle: L("Finder clutter scattered across folders"),
            symbol: "eye.slash",
            risk: .safe,
            riskScore: 1,
            items: [item]
        )
    }

    // MARK: - Utilities

    /// Lists a directory's direct children as cleanup items.
    private func childItems(
        of root: URL,
        isCancelled: () -> Bool,
        minimumSize: Int64 = 1024 * 1024,
        filter: (String) -> Bool = { _ in true }
    ) -> [CleanupItem] {

        guard fm.fileExists(atPath: root.path) else { return [] }
        guard let contents = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: []
        ) else { return [] }

        var items: [CleanupItem] = []
        for url in contents {
            if isCancelled() { break }
            guard filter(url.lastPathComponent) else { continue }
            guard freesSpace(url) else { continue }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let size = isDir
                ? DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                : fileSize(url)

            guard size >= minimumSize else { continue }

            items.append(CleanupItem(
                path: url.path,
                displayName: url.lastPathComponent,
                size: size,
                modified: modificationDate(url),
                isDirectory: isDir,
                note: nil
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Only things that genuinely free space on the Mac enter the cleanup list.
    ///
    /// Symlinks are discarded (deleting the link gives no bytes back) and so is
    /// content living on another volume — the case of folders already offloaded to
    /// an external SSD, such as `~/.gradle` pointing at `/Volumes/CachePart`.
    /// Without this filter the app would count external-disk space as reclaimable
    /// on the internal one, and delete data on the wrong side.
    private func freesSpace(_ url: URL) -> Bool {
        VolumeResolver.freesSpaceOnMac(url)
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
