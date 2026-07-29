import Foundation
import UserNotifications

/// Warns when the startup disk is running low on space.
///
/// Two rules decide whether this is useful or annoying:
///
/// 1. **Hysteresis.** The warning fires on crossing the threshold downwards and
///    only rearms after rising 3 percentage points above it. Without that, a disk
///    hovering around 10% would notify on every check.
/// 2. **Minimum interval.** Even while still below the threshold, at most one
///    warning every 6 hours.
@MainActor
final class SpaceAlert: ObservableObject {

    private enum Key {
        static let lastAlert = "lowSpaceLastAlertAt"
        static let armed = "lowSpaceArmed"
    }

    /// How far free space must rise above the threshold to rearm the warning.
    private let rearmMargin = 3.0
    private let minimumInterval: TimeInterval = 6 * 3600

    @Published private(set) var permissionDenied = false
    @Published private(set) var unavailableReason: String?

    private var didRequestPermission = false

    // MARK: - Permission

    /// Requested only when the user turns the option on, not at launch — asking
    /// for notification permission before the user wants notifications is the
    /// fastest way to have it denied forever.
    func requestPermissionIfNeeded() {
        guard !didRequestPermission else { return }
        didRequestPermission = true

        // With no bundle identifier, UNUserNotificationCenter throws instead of
        // returning an error — this happens when running the binary outside a .app.
        guard Bundle.main.bundleIdentifier != nil else {
            permissionDenied = true
            unavailableReason = L("Notifications require the app to run as a bundle (.app).")
            return
        }

        // Off the main thread and non-blocking: if the notification service is
        // unhealthy, the app keeps working.
        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                await MainActor.run { [weak self] in
                    self?.permissionDenied = !granted
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.permissionDenied = true
                    self?.unavailableReason = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Evaluation

    /// Called on every metrics refresh. Returns `true` if it notified.
    @discardableResult
    func evaluate(volume: VolumeInfo?, thresholdPercent: Double, enabled: Bool) -> Bool {
        guard enabled, let volume, volume.total > 0 else { return false }

        let freePercent = Double(volume.available) / Double(volume.total) * 100
        let defaults = UserDefaults.standard
        let armed = defaults.object(forKey: Key.armed) as? Bool ?? true

        // Rose enough: rearm and stay quiet.
        if freePercent >= thresholdPercent + rearmMargin {
            if !armed { defaults.set(true, forKey: Key.armed) }
            return false
        }

        guard freePercent < thresholdPercent, armed else { return false }

        if let last = defaults.object(forKey: Key.lastAlert) as? Date,
           Date().timeIntervalSince(last) < minimumInterval {
            return false
        }

        notify(volume: volume, freePercent: freePercent)
        defaults.set(false, forKey: Key.armed)
        defaults.set(Date(), forKey: Key.lastAlert)
        return true
    }

    private func notify(volume: VolumeInfo, freePercent: Double) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = L("Low space on %@", volume.name)
        content.body = L("%@ left (%d%%).", Fmt.bytes(volume.available), Int(freePercent))
            + " " + L("Open SaveMyMac to see what can go.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lowSpace-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// So the interface can show the state without waiting for the next evaluation.
    func isLow(volume: VolumeInfo?, thresholdPercent: Double) -> Bool {
        guard let volume, volume.total > 0 else { return false }
        return Double(volume.available) / Double(volume.total) * 100 < thresholdPercent
    }
}
