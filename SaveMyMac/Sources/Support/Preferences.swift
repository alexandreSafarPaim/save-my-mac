import Foundation
import Combine
import AppKit

/// App preferences, persisted in `UserDefaults`.
///
/// Deliberately separate from `GameStore`: that is progress, this is
/// configuration — and configuration has to be available before any scan,
/// including on a background launch.
///
/// ─────────────────────────────────────────────────────────────────────────
/// WHY NO PROPERTY HERE USES `@Published`
/// ─────────────────────────────────────────────────────────────────────────
///
/// `@Published` fires `objectWillChange` on **every assignment**, including
/// assignments where the new value equals the old one. That sounds like a
/// detail and it isn't.
///
/// `MenuBarExtra(isInserted:)` writes to its binding on every update pass, to
/// reflect the item's real insertion state. With `@Published` behind it, the
/// sequence became:
///
///     write false → publish → App body invalidated → menu bar scene rebuilt
///     → write false → publish → …
///
/// A cycle feeding itself at processor speed. Measured: **6,600 rebuilds in
/// 9.6 seconds, 100% of a core, +86 MB in 13 s**. The spindump showed the menu
/// update calling `invalidateProperties` on itself.
///
/// None of my earlier fixes caught this, because every one of them ended up
/// writing to the same `@Published`: first through `Binding(get:set:)`, then
/// through `$prefs.showMenuBar`. The path changed; the trigger didn't.
///
/// Now every setter compares before publishing. Writing the same value is a
/// no-op, and the cycle doesn't close. This applies to all the properties, not
/// just the one that broke: publishing a change that didn't happen is never
/// right.
@MainActor
final class Preferences: ObservableObject {

    private enum Key {
        static let showMenuBar = "showMenuBarExtra"
        static let hideDockIcon = "hideDockIcon"
        static let lowSpaceAlerts = "lowSpaceAlerts"
        static let lowSpaceThreshold = "lowSpaceThresholdPercent"
        static let menuBarMetric = "menuBarMetric"
    }

    /// What shows next to the clock when space runs short.
    enum MenuBarMetric: String, CaseIterable, Identifiable {
        case disk
        case memory
        case cpu
        case temperature
        case none

        var id: String { rawValue }

        var label: String {
            switch self {
            case .disk: return L("Free space")
            case .memory: return L("Memory pressure")
            case .cpu: return L("CPU usage")
            case .temperature: return L("Temperature")
            case .none: return L("Icon only")
            }
        }
    }

    // MARK: - Storage

    private var _showMenuBar: Bool
    private var _hideDockIcon: Bool
    private var _lowSpaceAlerts: Bool
    private var _lowSpaceThreshold: Double
    private var _menuBarMetric: MenuBarMetric

    // MARK: - Properties

    /// Written by `MenuBarExtra` on every update — this is exactly where the
    /// comparison stops the cycle. The counter records the frequency, so the
    /// next suspicion has a number instead of a hunch.
    var showMenuBar: Bool {
        get { _showMenuBar }
        set {
            Trace.count("Preferences.showMenuBar written", every: 500)
            guard newValue != _showMenuBar else { return }
            Trace.mark("showMenuBar actually changed: \(_showMenuBar) → \(newValue)")
            objectWillChange.send()
            _showMenuBar = newValue
            UserDefaults.standard.set(newValue, forKey: Key.showMenuBar)
        }
    }

    /// Hiding from the Dock turns the app into a menu bar utility.
    var hideDockIcon: Bool {
        get { _hideDockIcon }
        set {
            guard newValue != _hideDockIcon else { return }
            objectWillChange.send()
            _hideDockIcon = newValue
            UserDefaults.standard.set(newValue, forKey: Key.hideDockIcon)
            applyActivationPolicy()
        }
    }

    var lowSpaceAlerts: Bool {
        get { _lowSpaceAlerts }
        set {
            guard newValue != _lowSpaceAlerts else { return }
            objectWillChange.send()
            _lowSpaceAlerts = newValue
            UserDefaults.standard.set(newValue, forKey: Key.lowSpaceAlerts)
        }
    }

    /// Free-space percentage below which the app warns.
    var lowSpaceThreshold: Double {
        get { _lowSpaceThreshold }
        set {
            guard newValue != _lowSpaceThreshold else { return }
            objectWillChange.send()
            _lowSpaceThreshold = newValue
            UserDefaults.standard.set(newValue, forKey: Key.lowSpaceThreshold)
        }
    }

    var menuBarMetric: MenuBarMetric {
        get { _menuBarMetric }
        set {
            guard newValue != _menuBarMetric else { return }
            objectWillChange.send()
            _menuBarMetric = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.menuBarMetric)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.showMenuBar: true,
            Key.hideDockIcon: false,
            Key.lowSpaceAlerts: true,
            Key.lowSpaceThreshold: 10.0
        ])

        // One-off repair of a value written by a defect, not by the user.
        //
        // During the infinite update cycle, `MenuBarExtra` wrote `false` to the
        // binding thousands of times, and the `didSet` of the day persisted
        // every one of them to `UserDefaults`. Result: the preference ended up
        // stored as false without anyone having turned anything off — and
        // `register` does not override an explicitly stored value. The icon then
        // never appeared, even with the feature on and the bug fixed.
        //
        // This runs exactly once, marked by its own key. It isn't the app
        // ignoring the user's choice: it's the app undoing a choice the user
        // never made. After this once, the preference is always respected.
        let repairKey = "menuBarPreferenceRepaired.v1"
        if !defaults.bool(forKey: repairKey) {
            defaults.set(true, forKey: repairKey)
            if MenuBarFeature.isEnabled {
                defaults.set(true, forKey: Key.showMenuBar)
                NSLog("[SaveMyMac] Menu bar preference restored to on.")
            }
        }

        // The feature gate is applied here, once. The scene gets the projected
        // binding directly; wrapping it to apply the gate would create a new
        // object on every evaluation, which is another way to never converge.
        _showMenuBar = MenuBarFeature.isEnabled && defaults.bool(forKey: Key.showMenuBar)
        _hideDockIcon = defaults.bool(forKey: Key.hideDockIcon)
        _lowSpaceAlerts = defaults.bool(forKey: Key.lowSpaceAlerts)
        _lowSpaceThreshold = defaults.double(forKey: Key.lowSpaceThreshold)
        _menuBarMetric = MenuBarMetric(
            rawValue: defaults.string(forKey: Key.menuBarMetric) ?? MenuBarMetric.disk.rawValue
        ) ?? .disk
    }

    /// Applies the activation policy without restarting the app — that's what
    /// lets the Dock icon be hidden and shown immediately.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        if !hideDockIcon {
            NSApp.activate(ignoringOtherApps: false)
        }
    }
}
