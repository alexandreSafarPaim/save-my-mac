import Foundation
import ServiceManagement

/// Open at login.
///
/// Two mechanisms, and the reason both exist matters:
///
/// - `SMAppService.mainApp` is the correct API on macOS 13+. It shows up in
///   System Settings › General › Login Items and the user can disable it there.
///   But it **requires a valid code signature** and the app to be in
///   `/Applications`. This project signs ad-hoc, so registration can fail.
///
/// - `LaunchAgent` (a plist in `~/Library/LaunchAgents`) is the old mechanism,
///   works without a signature, and is what rescues the ad-hoc case.
///
/// The order is: try the modern one, fall back to the old one, and have the
/// interface **say which is in use** instead of pretending they're the same.
enum LaunchAtLogin {

    enum Mechanism: String {
        case serviceManagement
        case launchAgent
        case none

        var label: String {
            switch self {
            case .serviceManagement: return L("system Login Items")
            case .launchAgent: return L("user LaunchAgent")
            case .none: return L("disabled")
            }
        }
    }

    private static let agentLabel = "br.com.pentagrama.savemymac.launcher"

    private static var agentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist")
    }

    // MARK: - State
    //
    // ┌─────────────────────────────────────────────────────────────────────┐
    // │ NOTHING HERE MAY BE READ FROM INSIDE A VIEW `init`.                 │
    // └─────────────────────────────────────────────────────────────────────┘
    //
    // `SMAppService.status` looks like a property getter and isn't: every read
    // makes a **synchronous** XPC round trip to `smd`, the Service Management
    // daemon. On the main thread that is blocking I/O disguised as field access.
    //
    // That is exactly how the app hung. `SettingsView` initialised `@State` with
    // `LaunchAtLogin.isEnabled` and `.statusDescription`. Because SwiftUI builds
    // the `Settings` scene content on every App body evaluation — even with the
    // Settings window closed, even if it was never opened — and because the App
    // body was invalidated by every `@Published` of `AppState`, the app fired
    // two synchronous XPC calls per update, dozens per second. `smd` clogged up,
    // stopped answering, and the main thread parked in `mach_msg`. The spindump
    // showed the whole path:
    //
    //     SaveMyMacApp.body.getter → Settings.init(content:) → SettingsView.init()
    //       → LaunchAtLogin.isEnabled → SMAppService.status → mach_msg
    //       (blocked by turnstile waiting for smd)
    //
    // The fix is for the read to become **cache plus async refresh**: the
    // interface reads an in-memory value for free, and the XPC happens off the
    // main thread, only when someone asks.

    struct Snapshot {
        var enabled = false
        var mechanism = Mechanism.none
        var description = L("Checking…")
        /// False until the first query finishes, so the interface can show that
        /// it doesn't know yet instead of lying "disabled".
        var isKnown = false
    }

    private static let cacheLock = NSLock()
    private static var cache = Snapshot()

    /// Instant read, no XPC. This is what the interface should use.
    static var snapshot: Snapshot {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache
    }

    /// The lock is deliberately confined to this **synchronous** function.
    ///
    /// Calling `lock()` directly inside an `async` function is an error in Swift
    /// 6, and the reason is real: between the `lock` and the `unlock` there may
    /// be a suspension, and the resumption may happen on another thread — which
    /// then tries to unlock a lock it never took. A synchronous function cannot
    /// suspend, so the `lock`/`unlock` pair runs entirely on one thread.
    private static func store(_ fresh: Snapshot) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        cache = fresh
    }

    /// Queries the real state off the main thread and returns the result on it.
    /// Call from `.task`/`.onAppear`, never from an initialiser.
    @MainActor
    static func refresh() async -> Snapshot {
        let fresh = await Task.detached(priority: .userInitiated) {
            read()
        }.value
        store(fresh)
        return fresh
    }

    /// The genuinely expensive query. Private on purpose: if nobody outside can
    /// call it, nobody outside can block the interface with it.
    private static func read() -> Snapshot {
        Trace.mark("→ SMAppService.status (XPC to smd)")
        let status = SMAppService.mainApp.status
        Trace.mark("← SMAppService.status")

        let hasAgent = FileManager.default.fileExists(atPath: agentURL.path)

        switch status {
        case .enabled:
            return Snapshot(
                enabled: true,
                mechanism: .serviceManagement,
                description: L("Active through the system Login Items."),
                isKnown: true
            )
        case .requiresApproval:
            return Snapshot(
                enabled: true,
                mechanism: .serviceManagement,
                description: L("Registered, but waiting for your approval in System Settings › General › Login Items."),
                isKnown: true
            )
        default:
            if hasAgent {
                return Snapshot(
                    enabled: true,
                    mechanism: .launchAgent,
                    description: L("Active through a LaunchAgent — the fallback path, used because the app is ad-hoc signed."),
                    isKnown: true
                )
            }
            return Snapshot(
                enabled: false,
                mechanism: .none,
                description: L("Disabled."),
                isKnown: true
            )
        }
    }

    // MARK: - Enable and disable

    struct Result {
        var enabled: Bool
        var mechanism: Mechanism
        var message: String
        var isError: Bool
    }

    /// Registering and unregistering are also synchronous XPC to `smd`, and
    /// `launchctl` is a subprocess. Both go off the main thread.
    @MainActor
    static func setEnabled(_ enabled: Bool) async -> Result {
        let result = await Task.detached(priority: .userInitiated) {
            enabled ? self.enable() : self.disable()
        }.value
        _ = await refresh()
        return result
    }

    private static func enable() -> Result {
        // 1) Modern path.
        do {
            try SMAppService.mainApp.register()
            let status = SMAppService.mainApp.status
            if status == .requiresApproval {
                return Result(
                    enabled: true,
                    mechanism: .serviceManagement,
                    message: L("Registered. Approve it in System Settings › General › Login Items to take effect."),
                    isError: false
                )
            }
            return Result(
                enabled: true,
                mechanism: .serviceManagement,
                message: L("SaveMyMac will open together with the Mac."),
                isError: false
            )
        } catch {
            // 2) Fallback: LaunchAgent. The expected case with an ad-hoc signature.
            if let failure = writeLaunchAgent() {
                return Result(
                    enabled: false,
                    mechanism: .none,
                    message: L("Could not enable: %@", failure),
                    isError: true
                )
            }
            return Result(
                enabled: true,
                mechanism: .launchAgent,
                message: L("Enabled through a LaunchAgent. Modern registration failed (%@) — expected in an ad-hoc signed app.", error.localizedDescription),
                isError: false
            )
        }
    }

    private static func disable() -> Result {
        var problems: [String] = []

        if SMAppService.mainApp.status != .notRegistered {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                problems.append(error.localizedDescription)
            }
        }

        if FileManager.default.fileExists(atPath: agentURL.path) {
            // Unload before deleting, otherwise the agent stays active until the
            // next login.
            _ = ProcessMonitor.run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(agentLabel)"])
            do {
                try FileManager.default.removeItem(at: agentURL)
            } catch {
                problems.append(error.localizedDescription)
            }
        }

        if problems.isEmpty {
            return Result(
                enabled: false,
                mechanism: .none,
                message: L("SaveMyMac will no longer open with the Mac."),
                isError: false
            )
        }
        let after = read()
        return Result(
            enabled: after.enabled,
            mechanism: after.mechanism,
            message: L("Failed to disable: %@", problems.joined(separator: "; ")),
            isError: true
        )
    }

    // MARK: - LaunchAgent

    /// Writes the plist and loads it. Returns the error message, or `nil` on success.
    private static func writeLaunchAgent() -> String? {
        let appPath = Bundle.main.bundlePath
        guard appPath.hasSuffix(".app") else {
            return L("the app has to be in a .app bundle (run ./build.sh --install)")
        }

        let plist: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
            // Without this, launchd would relaunch `open` in a loop.
            "KeepAlive": false
        ]

        do {
            let directory = agentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: agentURL, options: .atomic)
        } catch {
            return error.localizedDescription
        }

        let load = ProcessMonitor.run(
            "/bin/launchctl",
            ["bootstrap", "gui/\(getuid())", agentURL.path]
        )
        // `bootstrap` errors if it is already loaded; that is not a real failure.
        if load.status != 0 && !load.error.contains("already") {
            return "launchctl falhou (\(load.status)): \(load.error.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        return nil
    }
}
