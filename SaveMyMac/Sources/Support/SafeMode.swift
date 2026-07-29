import Foundation

/// Bisection switch for isolating an interface hang.
///
/// Turn on with:
///     defaults write br.com.pentagrama.savemymac safeMode -bool true
/// Turn off with:
///     defaults write br.com.pentagrama.savemymac safeMode -bool false
///
/// With this on, the app disables everything that is decoration or recent
/// infrastructure, all at once:
///
///   - the atmospheric background (grid + radial gradients)
///   - the menu bar item
///   - `FlowLayout`, a hand-written custom `Layout` — the piece most likely to
///     get into an endless layout negotiation
///   - the entrance animations
///
/// If the app works in safe mode, the problem is in one of those four. If it
/// hangs anyway, it's in the core and the decoration is innocent. That's worth
/// more than any guess of mine.
enum SafeMode {

    /// Read once. Changing it requires reopening the app, which is deliberate:
    /// toggling live would rebuild the view tree and muddle the diagnosis.
    static let isOn: Bool = {
        let on = UserDefaults.standard.bool(forKey: "safeMode")
        if on {
            NSLog("[SaveMyMac] SAFE MODE on: background, menu bar, FlowLayout and animations disabled.")
        }
        return on
    }()
}

/// The menu bar scene — **on by default**.
///
/// It was disabled for a while, and it's worth recording why, because the
/// conclusion was wrong: when this feature landed, the app started hanging at
/// launch and the item never appeared next to the clock. It looked like its
/// fault.
///
/// It wasn't. The cause was in `Preferences`, which used `@Published`.
/// `MenuBarExtra(isInserted:)` writes to its binding on every update pass, and
/// `@Published` publishes on every assignment — including assignments that
/// don't change the value. That closed a cycle which burned 100% of a core and
/// kept the graph from converging. **The item never appeared because the app
/// never finished its first update.** The feature was the victim, not the
/// culprit.
///
/// With the setter fixed, it works. The key stays around as an emergency
/// switch — cheap to keep, and it avoids having to recompile to isolate
/// something:
///
///     defaults write br.com.pentagrama.savemymac enableMenuBar -bool false
///
/// The decision is read **once, at launch**: toggling live would rebuild the
/// scene tree, which is exactly what you don't want to be testing while
/// investigating instability.
enum MenuBarFeature {

    static let isEnabled: Bool = {
        guard !SafeMode.isOn else { return false }
        let defaults = UserDefaults.standard
        // Registered here rather than in `Preferences`: this is read at launch,
        // possibly before `Preferences.init` exists.
        defaults.register(defaults: ["enableMenuBar": true])
        let on = defaults.bool(forKey: "enableMenuBar")
        NSLog("[SaveMyMac] Menu bar: \(on ? "on" : "off")")
        return on
    }()
}
