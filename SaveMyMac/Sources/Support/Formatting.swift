import Foundation

enum Fmt {

    static func bytes(_ value: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        f.isAdaptive = false
        return f.string(fromByteCount: value)
    }

    static func bytes(_ value: UInt64) -> String {
        bytes(Int64(clamping: value))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", (value * 100).clamped(0, 100))
    }

    static func percent1(_ value: Double) -> String {
        String(format: "%.1f%%", (value * 100).clamped(0, 100))
    }

    static func celsius(_ value: Double) -> String {
        String(format: "%.1f °C", value)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)min" }
        if hours > 0 { return "\(hours)h \(minutes)min" }
        return "\(minutes)min"
    }

    // Building a formatter is expensive and these functions are called per list
    // cell, inside `body`, so the instances are cached — but keyed by language.
    //
    // They used to hardcode `Locale(identifier: "pt_BR")`, which was a live bug:
    // the Settings screen promised "dates follow your system region", and every
    // date on screen ignored the app language entirely. Worse, one of those
    // dates is `TrashManager.oldestLabel`, which feeds the confirmation dialog
    // for the app's only irreversible action. Found during the architecture
    // audit, not by any of the localization checkers — none of them look at
    // formatter configuration.
    private static var cachedLanguage: Language?
    private static var relativeFormatter = RelativeDateTimeFormatter()
    private static var shortFormatter = DateFormatter()

    private static func refreshFormattersIfNeeded() {
        let language = Localization.appLanguage
        guard language != cachedLanguage else { return }
        cachedLanguage = language

        let locale = Localization.appLocale
        relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = locale
        relativeFormatter.unitsStyle = .full

        shortFormatter = DateFormatter()
        shortFormatter.locale = locale
        shortFormatter.dateStyle = .short
        shortFormatter.timeStyle = .short
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        refreshFormattersIfNeeded()
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        refreshFormattersIfNeeded()
        return shortFormatter.string(from: date)
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double {
        Swift.min(Swift.max(self, lo), hi)
    }
}

extension String {
    /// Replaces the home path with "~" for display.
    var tildeShortened: String {
        let home = NSHomeDirectory()
        if hasPrefix(home) {
            return "~" + dropFirst(home.count)
        }
        return self
    }
}

// MARK: - Sizing

extension URL {
    /// Bytes this file occupies on disk.
    ///
    /// Two scanners carried an identical private `fileSize(_:)` each, and two
    /// more modules inlined the same expression with a slightly different
    /// fallback chain — drift nobody chose. One definition, one fallback order:
    /// allocated size first (what the disk actually loses), logical size as the
    /// last resort.
    var allocatedBytes: Int64 {
        let values = try? resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        )
        return Int64(values?.totalFileAllocatedSize
                     ?? values?.fileAllocatedSize
                     ?? values?.fileSize
                     ?? 0)
    }

    var modificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
