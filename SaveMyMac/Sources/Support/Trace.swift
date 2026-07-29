import Foundation

/// Execution trace written to a file, for diagnosing hangs.
///
/// Why not `NSLog`/`os_log`: when the app hangs and gets force-killed, the
/// unified logging subsystem may simply not have written anything — which is
/// exactly what happened (`log show` returned zero lines). Here the write is a
/// raw `write(2)`, with no library buffering, straight to the descriptor.
/// Whatever was marked is on disk the instant after, even if the process dies
/// immediately afterwards.
///
/// The idea is simple and depends on neither `sample` nor guesswork: every
/// suspicious call site marks entry and exit. When the app freezes, **the last
/// line of the file is where it stopped**.
///
/// File: ~/Library/Logs/SaveMyMac-trace.log
///
/// Note that these messages are deliberately **not** localized. They are
/// developer diagnostics, read by whoever is debugging a report — translating
/// them would make a hang report unreadable to the person receiving the issue.
enum Trace {

    static let path = NSHomeDirectory() + "/Library/Logs/SaveMyMac-trace.log"

    private static let lock = NSLock()
    private static let start = Date()

    /// `O_TRUNC`: every run starts from scratch. A trace that accumulates
    /// sessions forces you to guess where one ends and the next begins.
    private static let fd: Int32 = {
        let dir = NSHomeDirectory() + "/Library/Logs"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    }()

    static func mark(_ text: @autoclosure () -> String) {
        guard fd >= 0 else { return }
        let elapsed = Date().timeIntervalSince(start)
        let where_ = Thread.isMainThread ? "MAIN" : "bg  "
        let line = String(format: "%8.3f [%@] %@\n", elapsed, where_, text())
        lock.lock()
        _ = line.withCString { write(fd, $0, strlen($0)) }
        lock.unlock()
    }

    /// Marks entry and exit of a section, with its duration.
    /// If the exit never shows up in the file, that's where it hung.
    @discardableResult
    static func span<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        mark("→ \(name)")
        let t0 = Date()
        defer { mark(String(format: "← %@ (%.0f ms)", name, Date().timeIntervalSince(t0) * 1000)) }
        return try work()
    }

    /// Counts something that happens a lot and only records it periodically.
    /// Useful for measuring frequency without flooding the file.
    private static var counters: [String: Int] = [:]

    static func count(_ name: String, every: Int = 100) {
        lock.lock()
        let n = (counters[name] ?? 0) + 1
        counters[name] = n
        lock.unlock()
        // Outside the lock: `mark` takes it too, and NSLock isn't reentrant.
        if n % every == 0 { mark("\(name): \(n)×") }
    }

    // MARK: - Header

    /// Identifies **which binary** is running. We already lost time debugging an
    /// old version installed by mistake; the executable's modification date
    /// settles that in one line.
    static func begin() {
        let exe = Bundle.main.executablePath ?? "?"
        let stamp = (try? FileManager.default.attributesOfItem(atPath: exe)[.modificationDate])
            .flatMap { $0 as? Date }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"

        mark("SaveMyMac starting — pid \(getpid())")
        mark("executable: \(exe)")
        mark("built at: \(stamp.map(fmt.string(from:)) ?? "unknown")")
        mark("safe mode: \(SafeMode.isOn) · menu bar: \(MenuBarFeature.isEnabled)")
    }

    // MARK: - Main thread watchdog

    private static var lastPing = Date()
    private static var stalled = false

    /// Detects when the main thread stops responding.
    ///
    /// The main thread checks in every 0.25 s through the run loop. A plain
    /// thread, which doesn't depend on the run loop, verifies it. If the
    /// check-in goes stale, the interface is frozen — and the trace records the
    /// exact moment, which cross-referenced with the last mark says what was in
    /// flight.
    static func startWatchdog() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            lock.lock(); lastPing = Date(); lock.unlock()
        }

        Thread.detachNewThread {
            Thread.current.name = "savemymac.watchdog"
            while true {
                Thread.sleep(forTimeInterval: 0.5)
                lock.lock()
                let age = Date().timeIntervalSince(lastPing)
                lock.unlock()

                if age > 3, !stalled {
                    stalled = true
                    mark(String(format: "⚠️  MAIN THREAD STALLED for %.1f s", age))
                } else if age < 1, stalled {
                    stalled = false
                    mark("✅ main thread responded again")
                }
            }
        }
    }
}
