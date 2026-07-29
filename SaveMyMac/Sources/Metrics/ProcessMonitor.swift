import Foundation
import AppKit

struct ProcessInfoRow: Identifiable, Hashable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpuPercent: Double
    var memoryBytes: Int64
    /// The process owner. `nil` when `ps` didn't return the column.
    var uid: Int32?
    /// Bundle path, when the process is an app with a UI — lets us show the real
    /// icon and the name the user recognises.
    var bundlePath: String?

    var isApp: Bool { bundlePath != nil }
}

enum ProcessMonitor {

    /// Why the last read failed. It exists so the interface can state the reason
    /// instead of rendering an empty card.
    private static let failureLock = NSLock()
    private static var storedFailure: String?

    static var lastFailure: String? {
        failureLock.lock()
        defer { failureLock.unlock() }
        return storedFailure
    }

    private static func setFailure(_ reason: String?) {
        failureLock.lock()
        storedFailure = reason
        failureLock.unlock()
    }

    /// Top processes by CPU and by memory, through `ps`.
    static func top(limit: Int = 8) -> (byCPU: [ProcessInfoRow], byMemory: [ProcessInfoRow]) {
        let rows = allProcesses()
        let byCPU = Array(rows.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(limit))
        let byMemory = Array(rows.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(limit))
        return (byCPU, byMemory)
    }

    static func allProcesses() -> [ProcessInfoRow] {
        // Three ways to call `ps`. The first uses `=` to suppress the header;
        // the others are a safety net, because the parser ignores any line whose
        // first field isn't a number — the header falls out on its own.
        let attempts: [[String]] = [
            ["-axo", "pid=,pcpu=,rss=,uid=,comm="],
            ["-axo", "pid,pcpu,rss,uid,comm"],
            ["-axo", "pid=,pcpu=,rss=,comm="],
            ["-Ao", "pid,pcpu,rss,comm"]
        ]

        var lastError = ""
        for arguments in attempts {
            let outcome = run("/bin/ps", arguments, forceCLocale: true)
            if outcome.status != 0 {
                lastError = outcome.error.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            let rows = parse(outcome.output)
            if !rows.isEmpty {
                setFailure(nil)
                return rows
            }
        }

        setFailure(
            lastError.isEmpty
                ? L("/bin/ps answered, but no line could be parsed.")
                : L("Failed to run /bin/ps: %@", lastError)
        )
        return []
    }

    /// Resolves the localized name and bundle for the rows on screen.
    ///
    /// Has to run on the main thread: it touches AppKit. That's ~12 lookups, not
    /// the hundreds that resolving during the parse would do.
    @MainActor
    static func enrich(_ rows: [ProcessInfoRow]) -> [ProcessInfoRow] {
        rows.map { row in
            guard let info = ProcessController.appInfo(for: row.pid) else { return row }
            var copy = row
            copy.name = info.name
            copy.bundlePath = info.bundlePath
            return copy
        }
    }

    /// Parses a number accepting either a dot **or** a comma as the decimal
    /// separator. A second line of defence: LC_ALL=C should already guarantee the
    /// dot, but not depending on that costs three lines.
    static func decimal(_ text: Substring) -> Double? {
        if let value = Double(text) { return value }
        return Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Parses `ps` output, skipping the header and malformed lines.
    ///
    /// Accepts both formats: with the `uid` column (5 fields) and without it (4).
    /// It tells them apart by the 4th field — if it's a bare integer it's the uid,
    /// because no command path is all digits.
    static func parse(_ output: String) -> [ProcessInfoRow] {
        var rows: [ProcessInfoRow] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let cpu = ProcessMonitor.decimal(parts[1]),
                  let rss = Int64(parts[2]) else { continue }

            var uid: Int32?
            var commandStart = 3
            if parts.count >= 5, let parsed = Int32(parts[3]) {
                uid = parsed
                commandStart = 4
            }

            let commandPath = parts[commandStart...].joined(separator: " ")
            let fallbackName = (commandPath as NSString).lastPathComponent

            // The pretty name and the icon are deliberately NOT resolved here:
            // `NSRunningApplication` is AppKit, this function runs on a
            // background thread, and resolving for hundreds of processes every
            // 2 s would be expensive and of dubious thread safety. `enrich(_:)`
            // does that, called only for the rows that reach the screen.
            rows.append(ProcessInfoRow(
                pid: pid,
                name: fallbackName.isEmpty ? "pid \(pid)" : fallbackName,
                cpuPercent: cpu,
                memoryBytes: rss * 1024,
                uid: uid,
                bundlePath: nil
            ))
        }

        return rows
    }

    /// Runs a command and returns status, stdout and stderr.
    /// Needed when the exit code matters — `shell` alone can't tell "ran and
    /// printed nothing" from "failed".
    ///
    /// `forceCLocale` exists for a concrete reason: BSD utilities format numbers
    /// with the system's decimal separator. On a Portuguese Mac, `ps` prints
    /// `%CPU` as "0,0", and `Double("0,0")` returns nil — which made EVERY line
    /// be discarded and left the processes card empty. With LC_ALL=C the output is
    /// always "0.0". It also stabilises `mdls` date formatting.
    static func run(
        _ launchPath: String,
        _ arguments: [String],
        forceCLocale: Bool = false
    ) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        if forceCLocale {
            var env = ProcessInfo.processInfo.environment
            env["LC_ALL"] = "C"
            env["LANG"] = "C"
            process.environment = env
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        Trace.mark("exec \(launchPath) \(arguments.joined(separator: " "))")
        do {
            try process.run()
        } catch {
            Trace.mark("exec failed: \(error.localizedDescription)")
            return (-1, "", error.localizedDescription)
        }
        defer { Trace.mark("exec \(launchPath) finished") }

        // Both pipes are drained **in parallel**.
        //
        // Reading stdout to EOF and only then stderr looks harmless and isn't: a
        // pipe's buffer is 64 KB. If the child fills the stderr one while the
        // parent is still waiting for the end of stdout, the child blocks on the
        // write, never closes stdout, and the parent waits forever. It is a
        // silent deadlock — nothing crashes, nothing fails, the thread just
        // disappears.
        //
        // With one task per pipe, neither can hold the other.
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let sink = DispatchQueue(label: "savemymac.pipe-drain")

        for (handle, isOut) in [(outPipe.fileHandleForReading, true),
                                (errPipe.fileHandleForReading, false)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = handle.readDataToEndOfFile()
                sink.async {
                    if isOut { outData = data } else { errData = data }
                    group.leave()
                }
            }
        }

        group.wait()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }

    /// Convenience over `run` for callers that only want stdout.
    ///
    /// This used to be a second, independent `Process` implementation with a
    /// single serially-drained pipe — the exact shape the comment inside `run`
    /// forbids. It was safe only because it discarded stderr entirely, which its
    /// one caller (`powermetrics`, the most verbose command in the app) relied
    /// on implicitly. Thirty lines of process-launching existed twice with
    /// different failure semantics; now there is one.
    ///
    /// It also swallowed every failure into the same `nil`, so "you cancelled
    /// the password prompt" and "the tool crashed" were indistinguishable no-ops.
    /// The stderr detail now at least reaches the trace.
    static func shell(_ launchPath: String, _ arguments: [String]) -> String? {
        let result = run(launchPath, arguments)
        guard result.status == 0 else {
            Trace.mark("shell \(launchPath) status \(result.status): \(result.error.prefix(200))")
            return nil
        }
        return result.output
    }
}
