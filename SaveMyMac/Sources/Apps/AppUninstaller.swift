import Foundation

struct UninstallResult {
    var removedPaths: [String] = []
    var freedBytes: Int64 = 0
    var failures: [(path: String, reason: String)] = []
    var bundleRemoved = false

    var succeeded: Bool { !removedPaths.isEmpty }
}

/// Removes the cache, or the whole app with all its support data.
///
/// Always through the Trash: nothing is deleted irreversibly here, and no
/// operation asks for a password. If the bundle sits somewhere that requires
/// privilege, the failure is reported with instructions rather than escalating on
/// its own.
enum AppUninstaller {

    // MARK: - Apenas o cache

    static func clearCache(
        of app: InstalledApp,
        progress: (String, Double) -> Void
    ) -> UninstallResult {
        let targets = app.residues.filter(\.isCache)
        return remove(paths: targets.map { ($0.path, $0.size) },
                      label: L("%@ cache", app.name),
                      progress: progress)
    }

    // MARK: - App completo

    static func uninstall(
        app: InstalledApp,
        includeResidues: Bool = true,
        progress: (String, Double) -> Void
    ) -> UninstallResult {

        guard app.canUninstall else {
            var result = UninstallResult()
            result.failures.append((app.path, L("System application — cannot be removed")))
            return result
        }

        var entries: [(String, Int64)] = []
        if includeResidues {
            entries += app.residues.map { ($0.path, $0.size) }
        }
        entries.append((app.path, app.bundleSize))

        var result = remove(paths: entries, label: app.name, progress: progress)
        result.bundleRemoved = result.removedPaths.contains(app.path)
        return result
    }

    // MARK: - Core

    private static func remove(
        paths: [(String, Int64)],
        label: String,
        progress: (String, Double) -> Void
    ) -> UninstallResult {

        var result = UninstallResult()
        let total = max(1, paths.count)

        for (index, entry) in paths.enumerated() {
            progress(label, Double(index) / Double(total))

            let url = URL(fileURLWithPath: entry.0)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            if let reason = rejectionReason(for: url) {
                result.failures.append((entry.0, reason))
                continue
            }

            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                result.removedPaths.append(entry.0)
                result.freedBytes += entry.1
            } catch {
                let reason = url.path.hasPrefix("/Applications")
                    ? L("No permission. Drag the app to the Trash manually.")
                    : error.localizedDescription
                result.failures.append((entry.0, reason))
            }
        }

        progress(label, 1.0)
        return result
    }

    /// The safety guard specific to uninstallation.
    ///
    /// It is more permissive than cleanup's (here `/Applications` is a legitimate
    /// target) but still blocks the system, symlinks, and anything whose real
    /// content lives on another volume.
    static func rejectionReason(for url: URL) -> String? {
        let path = url.standardizedFileURL.path

        if VolumeResolver.isSymbolicLink(url) {
            return L("It's a symlink — remove it from the Offload panel")
        }
        if !VolumeResolver.isOnHomeVolume(url) {
            let volume = VolumeResolver.volumeName(of: url) ?? "outro volume"
            return L("The real content is on %@", volume)
        }

        // Caminhos protegidos pelo sistema (SIP) ou vitais.
        let forbidden = [
            "/System", "/usr", "/bin", "/sbin", "/private/var/db",
            "/Library/Apple", "/Library/Security"
        ]
        for prefix in forbidden where path.hasPrefix(prefix) {
            return L("Path protected by the system")
        }

        // Inside home, never the top-level folders.
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        if path.hasPrefix(home + "/") {
            let relative = String(path.dropFirst(home.count + 1))
            let components = relative.split(separator: "/")
            let protectedTop: Set<String> = [
                "Documents", "Desktop", "Downloads", "Library", "Pictures",
                "Movies", "Music", "Public", "Applications", ".Trash"
            ]
            if components.count == 1 && protectedTop.contains(String(components[0])) {
                return L("Protected user folder")
            }
            let blocked = [
                "Library/Keychains", "Library/Mail", "Library/CloudStorage",
                "Library/Mobile Documents", "Library/Preferences/com.apple"
            ]
            for prefix in blocked where relative.hasPrefix(prefix) {
                return L("Protected sensitive path")
            }
            return nil
        }

        // Outside home we only allow .app bundles in /Applications.
        if path.hasPrefix("/Applications") && url.pathExtension == "app" {
            return nil
        }
        if path == "/Applications" {
            return L("The Applications folder is not removable")
        }

        return L("Outside the allowed scope")
    }
}
