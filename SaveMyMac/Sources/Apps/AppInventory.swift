import Foundation
import AppKit

/// A data item associated with an app (cache, preferences, container…).
struct AppResidue: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var label: String
    var size: Int64
    /// Cache is regenerable; the rest goes along with the app.
    var isCache: Bool
}

struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    var path: String
    var name: String
    var bundleID: String
    var version: String
    var bundleSize: Int64
    var lastUsed: Date?
    var isSystem: Bool
    var residues: [AppResidue]

    var cacheSize: Int64 {
        residues.filter(\.isCache).reduce(0) { $0 + $1.size }
    }

    var residueSize: Int64 {
        residues.reduce(0) { $0 + $1.size }
    }

    /// Tudo que sai do disco ao desinstalar completamente.
    var totalSize: Int64 { bundleSize + residueSize }

    var daysSinceUse: Int? {
        guard let lastUsed else { return nil }
        return Calendar.current.dateComponents([.day], from: lastUsed, to: Date()).day
    }

    var lastUsedLabel: String {
        guard let days = daysSinceUse else { return L("use unknown") }
        switch days {
        case ..<1: return L("used today")
        case 1: return L("used yesterday")
        case ..<90: return L("used %d d ago", days)
        default: return L("unused for %d d", days)
        }
    }

    var isStale: Bool { (daysSinceUse ?? 0) >= 90 }

    /// Apple apps built into the system shouldn't be uninstalled.
    var canUninstall: Bool { !isSystem }
}

struct AppInventoryResult {
    var apps: [InstalledApp] = []
    var staleCount: Int = 0

    var totalCache: Int64 { apps.reduce(0) { $0 + $1.cacheSize } }
    var totalSize: Int64 { apps.reduce(0) { $0 + $1.totalSize } }
    var isEmpty: Bool { apps.isEmpty }
}

/// Lists installed apps with their size, last use and all the support data
/// scattered around the Library. Read-only.
final class AppInventoryScanner: @unchecked Sendable {

    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    private let searchRoots: [(URL, Bool)] = [
        (URL(fileURLWithPath: "/Applications"), false),
        (URL(fileURLWithPath: "/Applications/Utilities"), false),
        (FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"), false),
        (URL(fileURLWithPath: "/System/Applications"), true),
        (URL(fileURLWithPath: "/System/Applications/Utilities"), true)
    ]

    // MARK: - Varredura

    func scan(
        progress: @escaping (String, Double) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> AppInventoryResult {

        progress(L("Finding applications…"), 0.02)

        var bundles: [(url: URL, isSystem: Bool)] = []
        for (root, isSystem) in searchRoots {
            guard let contents = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents where url.pathExtension == "app" {
                bundles.append((url, isSystem))
            }
        }

        guard !bundles.isEmpty else { return AppInventoryResult() }

        // Último uso via Spotlight, tudo de uma vez.
        progress(L("Querying Spotlight…"), 0.08)
        let lastUsedMap = lastUsedDates(for: bundles.map { $0.url.path }, isCancelled: isCancelled)

        // Index of the Library directories, read once, so we don't walk the whole
        // tree once per app.
        progress(L("Indexing support data…"), 0.14)
        let libraryIndex = buildLibraryIndex()

        var apps: [InstalledApp] = []
        let total = max(1, bundles.count)

        for (index, entry) in bundles.enumerated() {
            if isCancelled() { break }
            let fraction = 0.18 + (Double(index) / Double(total)) * 0.80
            progress("Medindo \(entry.url.lastPathComponent)…", fraction)

            guard let app = describe(
                bundle: entry.url,
                isSystem: entry.isSystem,
                lastUsed: lastUsedMap[entry.url.path],
                libraryIndex: libraryIndex,
                isCancelled: isCancelled
            ) else { continue }

            apps.append(app)
        }

        apps.sort { $0.totalSize > $1.totalSize }
        progress(L("Done"), 1.0)

        return AppInventoryResult(apps: apps, staleCount: apps.filter(\.isStale).count)
    }

    // MARK: - Um app

    private func describe(
        bundle: URL,
        isSystem: Bool,
        lastUsed: Date?,
        libraryIndex: [String: [URL]],
        isCancelled: () -> Bool
    ) -> InstalledApp? {

        let plist = bundle.appendingPathComponent("Contents/Info.plist")
        var bundleID = ""
        var version = "—"
        var displayName = bundle.deletingPathExtension().lastPathComponent

        if let data = try? Data(contentsOf: plist),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            bundleID = (dict["CFBundleIdentifier"] as? String) ?? ""
            version = (dict["CFBundleShortVersionString"] as? String)
                ?? (dict["CFBundleVersion"] as? String) ?? "—"
            if let pretty = dict["CFBundleDisplayName"] as? String, !pretty.isEmpty {
                displayName = pretty
            }
        }

        // System apps are excluded: there is nothing to uninstall and the size is misleading.
        if isSystem && bundleID.hasPrefix("com.apple.") {
            return nil
        }

        let bundleSize = isSystem ? 0 : DiskMonitor.directorySize(at: bundle, isCancelled: isCancelled)

        let residues = bundleID.isEmpty
            ? []
            : findResidues(
                bundleID: bundleID,
                appName: displayName,
                libraryIndex: libraryIndex,
                isCancelled: isCancelled
            )

        return InstalledApp(
            path: bundle.path,
            name: displayName,
            bundleID: bundleID.isEmpty ? "—" : bundleID,
            version: version,
            bundleSize: bundleSize,
            lastUsed: lastUsed,
            isSystem: isSystem,
            residues: residues
        )
    }

    // MARK: - Dados de apoio

    /// The Library directories where apps leave data, with a friendly label and
    /// whether it counts as cache (regenerable) or not.
    ///
    /// `var`, not `let`.
    ///
    /// A `static let` is evaluated exactly once, on first read. With `L()` inside,
    /// the labels would be frozen in whatever language was active at that instant
    /// and would not follow a switch in Settings — the list would stay English
    /// forever after changing language. As a computed `var` it is rebuilt on every
    /// access, which is cheap: twelve tuples.
    private static var residueLocations: [(relative: String, label: String, isCache: Bool)] {[
        ("Library/Caches", "Cache", true),
        ("Library/Application Support", L("Support data"), false),
        ("Library/Containers", "Container", false),
        ("Library/Group Containers", L("Group container"), false),
        ("Library/Saved Application State", L("Saved state"), true),
        ("Library/HTTPStorages", L("HTTP storage"), true),
        ("Library/WebKit", L("WebKit data"), true),
        ("Library/Logs", "Logs", true),
        ("Library/Preferences", L("Preferences"), false),
        ("Library/Application Scripts", "Scripts", false),
        ("Library/Cookies", "Cookies", false),
        ("Library/LaunchAgents", L("Launch agent"), false)
    ]}

    /// Reads the contents of each Library folder exactly once.
    private func buildLibraryIndex() -> [String: [URL]] {
        var index: [String: [URL]] = [:]
        for location in AppInventoryScanner.residueLocations {
            let root = home.appendingPathComponent(location.relative)
            let contents = (try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: []
            )) ?? []
            index[location.relative] = contents
        }
        return index
    }

    private func findResidues(
        bundleID: String,
        appName: String,
        libraryIndex: [String: [URL]],
        isCancelled: () -> Bool
    ) -> [AppResidue] {

        let lowerID = bundleID.lowercased()
        // Fragmento do fabricante: "com.google.Chrome" -> "google"
        let vendor = bundleID.split(separator: ".").dropFirst().first?.lowercased() ?? ""
        let lowerName = appName.lowercased()

        var residues: [AppResidue] = []

        for location in AppInventoryScanner.residueLocations {
            if isCancelled() { break }
            guard let candidates = libraryIndex[location.relative] else { continue }

            for url in candidates {
                let name = url.lastPathComponent
                let lower = name.lowercased()

                let matches: Bool = {
                    if lower == lowerID { return true }
                    if lower.hasPrefix(lowerID + ".") { return true }   // .plist, .savedState…
                    if lower.contains(lowerID) { return true }
                    // A folder named after the app, for those that don't use a bundle id
                    if lower == lowerName && !lowerName.isEmpty { return true }
                    // Container de grupo do tipo "ABCDE12345.com.vendor.app"
                    if !vendor.isEmpty && lower.hasSuffix("." + lowerID) { return true }
                    return false
                }()

                guard matches else { continue }
                // Never consider something that already lives on another volume.
                guard VolumeResolver.freesSpaceOnMac(url) else { continue }

                let size = DiskMonitor.directorySize(at: url, isCancelled: isCancelled)
                let finalSize = size > 0 ? size : fileSize(url)
                guard finalSize > 0 else { continue }

                residues.append(AppResidue(
                    path: url.path,
                    label: location.label,
                    size: finalSize,
                    isCache: location.isCache
                ))
            }
        }

        return residues.sorted { $0.size > $1.size }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
    }

    // MARK: - Último uso via Spotlight

    /// Uses `mdls` to read `kMDItemLastUsedDate`. Several processes in parallel,
    /// because one call per app would be slow with 150 apps.
    private func lastUsedDates(for paths: [String], isCancelled: () -> Bool) -> [String: Date] {
        var result: [String: Date] = [:]
        let lock = NSLock()
        let chunks = paths.chunked(into: 12)

        DispatchQueue.concurrentPerform(iterations: chunks.count) { index in
            if isCancelled() { return }
            let chunk = chunks[index]
            for path in chunk {
                // LC_ALL=C so the date always comes out in the format
                // `parseSpotlightDate` expects, not the system language's.
                let outcome = ProcessMonitor.run(
                    "/usr/bin/mdls",
                    ["-name", "kMDItemLastUsedDate", "-raw", path],
                    forceCLocale: true
                )
                guard outcome.status == 0 else { continue }

                let trimmed = outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed != "(null)", !trimmed.isEmpty,
                      let date = AppInventoryScanner.parseSpotlightDate(trimmed) else { continue }

                lock.lock()
                result[path] = date
                lock.unlock()
            }
        }

        return result
    }

    /// `mdls -raw` devolve algo como "2026-07-26 14:03:11 +0000".
    static func parseSpotlightDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
