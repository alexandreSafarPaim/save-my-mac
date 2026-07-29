import Foundation
import AppKit
import Darwin

/// Quits processes, with the guards a bare `kill` lacks.
///
/// The order matters: it first asks the app to quit — which gives it the chance
/// to save what was open — and only forces if the user confirms afterwards. A
/// "free memory" button that force-kills processes trades the user's work for a
/// number that, on macOS, shouldn't be optimised in the first place.
enum ProcessController {

    enum Outcome {
        case askedToQuit(String)
        case terminated(String)
        case refused(String)
        case failed(String)

        var message: String {
            switch self {
            case .askedToQuit(let name):
                return L("Quit request sent to %@. If anything is unsaved, it will ask.", name)
            case .terminated(let name):
                return L("%@ was quit.", name)
            case .refused(let reason):
                return reason
            case .failed(let reason):
                return reason
            }
        }

        var isError: Bool {
            switch self {
            case .askedToQuit, .terminated: return false
            case .refused, .failed: return true
            }
        }
    }

    /// Processes the app never quits.
    ///
    /// This is not a "might cause trouble" list: it is a "will break the session"
    /// list. Killing WindowServer takes down the entire interface; killing
    /// launchd reboots the machine.
    private static let critical: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logind",
        "opendirectoryd", "securityd", "secinitd", "trustd", "configd",
        "distnoted", "notifyd", "syslogd", "powerd", "watchdogd", "hidd",
        "coreaudiod", "diskarbitrationd", "fseventsd", "mds", "mds_stores",
        "cfprefsd", "UserEventAgent", "amfid", "kextd", "nsurlsessiond",
        "backupd", "installd", "runningboardd", "SystemUIServer"
    ]

    /// Processes that come back on their own and whose termination is merely
    /// annoying. Allowed, but with a warning.
    static let relaunches: Set<String> = ["Finder", "Dock", "ControlCenter", "NotificationCenter"]

    // MARK: - Checks

    /// Reason not to quit, or `nil` if it is allowed.
    static func rejectionReason(for row: ProcessInfoRow) -> String? {
        if row.pid <= 1 {
            return L("Core system process.")
        }
        if row.pid == ProcessInfo.processInfo.processIdentifier {
            return L("This is SaveMyMac itself.")
        }
        if critical.contains(row.name) {
            return L("%@ is essential to the session — quitting it would take down the interface.", row.name)
        }
        // Without root there is no way to quit another owner's process, and
        // asking for a password to do it would trade stability for a number.
        // `bitPattern` rather than `Int32(getuid())`: converting from UInt32 would
        // trap if the uid exceeded Int32.max.
        if let uid = row.uid, uid != Int32(bitPattern: getuid()) {
            return L("%@ is not yours (runs as uid %d). The app does not escalate privileges for that.", row.name, uid)
        }
        return nil
    }

    /// Extra warning for processes macOS relaunches by itself — quitting breaks
    /// nothing, it just flickers the interface.
    static func warning(for row: ProcessInfoRow) -> String? {
        guard relaunches.contains(row.name) else { return nil }
        return L("macOS relaunches %@ automatically.", row.name)
    }

    static func canQuit(_ row: ProcessInfoRow) -> Bool {
        rejectionReason(for: row) == nil
    }

    // MARK: - Encerrar

    /// Pedido gentil: o app decide quando sair e pode pedir para salvar.
    @discardableResult
    static func requestQuit(_ row: ProcessInfoRow) -> Outcome {
        if let reason = rejectionReason(for: row) {
            return .refused(reason)
        }

        // App with a UI: `terminate()` sends a quit Apple Event, which is the
        // same as ⌘Q. A bare `kill` would not give it that chance.
        if let app = NSRunningApplication(processIdentifier: row.pid) {
            let name = app.localizedName ?? row.name
            return app.terminate()
                ? .askedToQuit(name)
                : .failed(L("%@ did not accept the quit request. Use force quit if you need to.", name))
        }

        // Daemon or headless helper: SIGTERM is the polite equivalent.
        if kill(row.pid, SIGTERM) == 0 {
            return .askedToQuit(row.name)
        }
        return .failed(L("Could not quit %@: %@.", row.name, String(cString: strerror(errno))))
    }

    /// Forces it. Should only be called after explicit confirmation, because
    /// unsaved work is lost.
    @discardableResult
    static func forceQuit(_ row: ProcessInfoRow) -> Outcome {
        if let reason = rejectionReason(for: row) {
            return .refused(reason)
        }

        if let app = NSRunningApplication(processIdentifier: row.pid) {
            let name = app.localizedName ?? row.name
            return app.forceTerminate()
                ? .terminated(name)
                : .failed(L("Could not force quit %@.", name))
        }

        if kill(row.pid, SIGKILL) == 0 {
            return .terminated(row.name)
        }
        return .failed(L("Could not force %@: %@.", row.name, String(cString: strerror(errno))))
    }

    // MARK: - Extra information

    /// The real name and icon when the process is an app with a UI.
    static func appInfo(for pid: Int32) -> (name: String, bundlePath: String)? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let url = app.bundleURL else { return nil }
        return (app.localizedName ?? url.deletingPathExtension().lastPathComponent, url.path)
    }
}
