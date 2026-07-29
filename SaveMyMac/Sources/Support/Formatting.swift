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
    // cell, inside `body`. A single instance, used on the main thread only.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .full
        return f
    }()

    private static let shortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
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
