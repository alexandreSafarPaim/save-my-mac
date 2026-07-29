import Foundation
import AppKit

enum CleanupRemover {

    /// Removes the selected items. Nothing is deleted without going through here.
    static func remove(
        items: [CleanupItem],
        mode: CleanupMode,
        progress: (String, Double) -> Void
    ) -> CleanupResult {

        struct Target {
            var path: String
            var size: Int64
            var label: String
        }

        var result = CleanupResult()
        var targets: [Target] = []

        for item in items {
            let paths = item.allPaths
            guard !paths.isEmpty else { continue }
            // Divide o tamanho entre os caminhos apenas para a barra de progresso.
            let share = item.size / Int64(paths.count)
            for path in paths {
                targets.append(Target(path: path, size: share, label: item.displayName))
            }
        }

        let total = max(1, targets.count)

        for (index, entry) in targets.enumerated() {
            progress(entry.label, Double(index) / Double(total))

            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            // Safety guard: never leave home, never touch system paths, and never
            // delete through a link to another volume.
            if let reason = rejectionReason(for: url) {
                result.failures.append((entry.path, reason))
                continue
            }

            do {
                switch mode {
                case .trash:
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                case .permanent:
                    try FileManager.default.removeItem(at: url)
                }
                result.removedCount += 1
                result.freedBytes += entry.size
            } catch {
                result.failures.append((entry.path, error.localizedDescription))
            }
        }

        progress(L("Done"), 1.0)
        return result
    }

    /// Returns the reason for refusing, or `nil` if the path may be removed.
    ///
    /// It only allows deletion inside the user's home folder, never the top-level
    /// folders (Documents, Desktop, Library…), and never content that lives on
    /// another volume — that last case protects anyone who offloaded folders to an
    /// external disk through a symlink: deleting there would give no space back to
    /// the Mac and would destroy data on the wrong disk.
    static func rejectionReason(for url: URL) -> String? {
        if VolumeResolver.isSymbolicLink(url) {
            return L("It's a symlink — removing it frees no space on the Mac")
        }

        if !VolumeResolver.isOnHomeVolume(url) {
            let volume = VolumeResolver.volumeName(of: url) ?? L("another volume")
            return L("The real content is on %@, not on the Mac's disk", volume)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.path
        let path = url.standardizedFileURL.path

        guard path.hasPrefix(home + "/") else {
            return L("Outside your home folder")
        }

        let relative = String(path.dropFirst(home.count + 1))
        let components = relative.split(separator: "/")

        guard !components.isEmpty else {
            return L("Invalid path")
        }

        // Blocks whole top-level folders
        let protectedTopLevel: Set<String> = [
            "Documents", "Desktop", "Downloads", "Library", "Pictures",
            "Movies", "Music", "Public", "Applications", ".Trash", "Developer"
        ]
        if components.count == 1 && protectedTopLevel.contains(String(components[0])) {
            return L("Protected user system folder")
        }

        // Blocks sensitive paths inside the Library
        let blockedPrefixes = [
            "Library/Keychains",
            "Library/Application Support/AddressBook",
            "Library/Application Support/com.apple.sharedfilelist",
            "Library/Mail",
            "Library/Messages/chat.db",
            "Library/Preferences/com.apple",
            "Library/CloudStorage",
            "Library/Mobile Documents",
            "Library/Group Containers"
        ]
        for prefix in blockedPrefixes where relative.hasPrefix(prefix) {
            return L("Protected sensitive path")
        }

        return nil
    }

    static func isSafeToDelete(_ url: URL) -> Bool {
        rejectionReason(for: url) == nil
    }

    static func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
}
