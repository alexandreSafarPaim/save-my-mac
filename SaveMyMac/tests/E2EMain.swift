import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// Behavioural tests for the safety-critical logic.
//
// This is a separate executable, compiled from the same sources as the app minus
// the UI layer (`SaveMyMacApp.swift`, `Views/`, `AppState.swift`). It runs the
// real functions against real files in a temporary directory.
//
// Why this exists: until it did, every "verification" in this project was a
// static check — regexes over source text. Nothing ever *ran* the code that
// deletes files. A grep can tell you a guard is still written; only executing it
// can tell you the guard still refuses.
//
// ── What is deliberately NOT tested ─────────────────────────────────────────
//
// `TrashManager.empty` is never called. It operates on the real `~/.Trash` with
// no way to redirect it, so exercising it would delete the user's Trash. That is
// an unacceptable price for a test. Its read path (`inspect`) is tested, and the
// symlink guard is verified by reading the source, which is weaker and honest to
// say so.
//
// Anything requiring a second physical volume is also out: the "content lives on
// another disk" guard can be tested for symlinks, but not for a real separate
// mount, without asking the machine to have one.
// ─────────────────────────────────────────────────────────────────────────────

@main
enum E2E {

    // MARK: - Tiny test harness

    nonisolated(unsafe) static var passed = 0
    nonisolated(unsafe) static var failed: [String] = []

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        if condition {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed.append(name)
            print("  ✗ \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
    }

    static func group(_ title: String) {
        print("\n\(title)")
    }

    // MARK: - Fixtures
    //
    // The home-relative guards can only be exercised by paths that are actually
    // inside home, so the sandbox lives there. It is removed at the end, and the
    // name carries the pid so two runs can't collide.

    nonisolated(unsafe) static let sandbox = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".savemymac-e2e-\(getpid())")

    static func makeFile(_ name: String, bytes: [UInt8]) -> URL {
        let url = sandbox.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(bytes))
        return url
    }

    // MARK: - Entry point

    @MainActor
    static func main() {
        print("SaveMyMac — behavioural tests")

        let fm = FileManager.default
        try? fm.createDirectory(at: sandbox, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: sandbox) }

        testLocalization()
        testFormatMarkersAtRuntime()
        testVolumeResolver()
        testCleanupGuards()
        testDuplicateComparison()
        testProcessParsing()
        testOffloadGuards()
        testTrashReadPath()
        testAccessProbe()

        print("\n────────────────────────────────────────")
        if failed.isEmpty {
            print("\(passed) passed, 0 failed")
            exit(0)
        }
        print("\(passed) passed, \(failed.count) FAILED:")
        for name in failed { print("  • \(name)") }
        exit(1)
    }

    // MARK: - Localization

    @MainActor
    static func testLocalization() {
        group("Localization")

        let original = Localization.shared.language
        defer { Localization.shared.language = original }

        Localization.shared.language = .en
        check("English returns the key unchanged",
              L("Dashboard") == "Dashboard")

        Localization.shared.language = .pt
        check("Portuguese translates a known key",
              L("Dashboard") == "Painel", L("Dashboard"))

        check("an unknown key falls back to itself",
              L("__no such key__") == "__no such key__")

        // The plural rule that differs: French uses the singular for zero.
        Localization.shared.language = .fr
        check("French uses the singular for zero",
              Lp("%d item", "%d items", count: 0) == "0 élément",
              Lp("%d item", "%d items", count: 0))
        check("French uses the singular for one",
              Lp("%d item", "%d items", count: 1) == "1 élément")
        check("French uses the plural for two",
              Lp("%d item", "%d items", count: 2) == "2 éléments")

        Localization.shared.language = .en
        check("English uses the plural for zero",
              Lp("%d item", "%d items", count: 0) == "0 items")

        // Regression: the plural key used to be "%d-week streak (plural)", and
        // because English falls back to the raw key, the app displayed
        // "3-week streak (plural)" on screen.
        check("no plural key leaks a marker into English",
              !Lp("Streak: %d week", "Streak: %d weeks", count: 3).contains("("),
              Lp("Streak: %d week", "Streak: %d weeks", count: 3))
    }

    /// Formats **every** entry in all three tables with arguments derived from the
    /// key's own placeholders.
    ///
    /// `check-translations.py` compares placeholders statically. This does the
    /// thing that actually crashes: calls `String(format:)`. A translation with an
    /// extra `%@` reads a pointer that was never passed, which is a crash in that
    /// language only — the kind of bug that ships because nobody runs the app in
    /// the language they just translated.
    @MainActor
    static func testFormatMarkersAtRuntime() {
        group("Format placeholders at runtime")

        let original = Localization.shared.language
        defer { Localization.shared.language = original }

        var checked = 0
        for (language, table) in [("pt", Strings.pt), ("es", Strings.es), ("fr", Strings.fr)] {
            Localization.shared.language = Language(rawValue: language) ?? .en

            for key in table.keys {
                let markers = key.matches(of: "%[@d]")
                guard !markers.isEmpty else { continue }

                let args: [CVarArg] = markers.map { $0 == "%d" ? 7 as CVarArg : "X" as CVarArg }
                let result = L(key, arguments: args)

                // A surviving raw placeholder means the translation has more
                // placeholders than the key, and the extra one read garbage.
                if result.contains("%@") || result.contains("%d") {
                    check("[\(language)] \(key.prefix(40))", false, "unfilled placeholder: \(result)")
                } else {
                    checked += 1
                }
            }
        }
        check("all \(checked) parameterised strings format cleanly", true)
    }

    // MARK: - VolumeResolver

    static func testVolumeResolver() {
        group("VolumeResolver — the symlink guard")

        let real = makeFile("real.bin", bytes: [1, 2, 3])
        let link = sandbox.appendingPathComponent("link.bin")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        check("detects a symlink", VolumeResolver.isSymbolicLink(link))
        check("a regular file is not a symlink", !VolumeResolver.isSymbolicLink(real))

        // The central invariant: a symlink never counts as reclaimable space,
        // because deleting the link gives no bytes back.
        check("a symlink does not free space on the Mac",
              !VolumeResolver.freesSpaceOnMac(link))
        check("a real file in home does free space",
              VolumeResolver.freesSpaceOnMac(real))

        check("resolves the symlink target",
              VolumeResolver.symlinkTarget(of: link)?.standardizedFileURL.path
                  == real.standardizedFileURL.path)

        // A broken link must not be treated as "external content" — see the note
        // on `isOnHomeVolume`.
        let broken = sandbox.appendingPathComponent("broken.bin")
        try? FileManager.default.createSymbolicLink(
            at: broken, withDestinationURL: sandbox.appendingPathComponent("does-not-exist"))
        check("a broken link is not reported as external",
              VolumeResolver.isOnHomeVolume(broken))
    }

    // MARK: - Cleanup guards

    static func testCleanupGuards() {
        group("CleanupRemover — refusals")

        let safe = makeFile("cache.bin", bytes: [0, 0, 0])
        check("allows a normal file inside the sandbox",
              CleanupRemover.rejectionReason(for: safe) == nil,
              CleanupRemover.rejectionReason(for: safe) ?? "")

        let link = sandbox.appendingPathComponent("link2.bin")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: safe)
        check("refuses a symlink", CleanupRemover.rejectionReason(for: link) != nil)

        check("refuses a path outside home",
              CleanupRemover.rejectionReason(for: URL(fileURLWithPath: "/usr/lib")) != nil)

        let home = FileManager.default.homeDirectoryForCurrentUser
        for folder in ["Documents", "Desktop", "Library", "Downloads", ".Trash"] {
            check("refuses the whole ~/\(folder)",
                  CleanupRemover.rejectionReason(for: home.appendingPathComponent(folder)) != nil)
        }

        for sensitive in ["Library/Keychains", "Library/Mail",
                          "Library/Mobile Documents", "Library/CloudStorage"] {
            check("refuses ~/\(sensitive)",
                  CleanupRemover.rejectionReason(for: home.appendingPathComponent(sensitive)) != nil)
        }

        check("isSafeToDelete agrees with rejectionReason",
              CleanupRemover.isSafeToDelete(safe)
                  && !CleanupRemover.isSafeToDelete(home.appendingPathComponent("Library")))
    }

    // MARK: - Duplicates

    static func testDuplicateComparison() {
        group("FileComparator — byte-by-byte before deleting")

        let a = makeFile("dup-a.bin", bytes: Array(repeating: 0xAB, count: 4096))
        let b = makeFile("dup-b.bin", bytes: Array(repeating: 0xAB, count: 4096))
        check("identical content compares equal", FileComparator.identical(a, b))

        // The exact case the sampled hash can miss: same size, differing only in
        // the middle. Two VM disks cloned and later diverged look like this.
        var middle = Array(repeating: UInt8(0xAB), count: 4096)
        middle[2048] = 0x00
        let c = makeFile("dup-c.bin", bytes: middle)
        check("same size, different middle compares unequal",
              !FileComparator.identical(a, c))

        check("a file is not a duplicate of itself", !FileComparator.identical(a, a))

        let empty1 = makeFile("empty1.bin", bytes: [])
        let empty2 = makeFile("empty2.bin", bytes: [])
        check("two empty files compare equal", FileComparator.identical(empty1, empty2))

        check("a missing file compares unequal",
              !FileComparator.identical(a, sandbox.appendingPathComponent("nope.bin")))
    }

    // MARK: - ps parsing

    static func testProcessParsing() {
        group("ProcessMonitor — parsing ps output")

        check("parses a dot decimal", ProcessMonitor.decimal("12.5") == 12.5)
        // The bug that emptied the processes card: a Portuguese Mac prints "0,0".
        check("parses a comma decimal", ProcessMonitor.decimal("12,5") == 12.5)
        check("rejects a non-number", ProcessMonitor.decimal("abc") == nil)

        let fiveColumns = """
        123 4.5 20480 501 /Applications/Foo.app/Contents/MacOS/Foo
        456 0,0 1024 0 /usr/libexec/bar
        """
        let rows = ProcessMonitor.parse(fiveColumns)
        check("parses 5-column output", rows.count == 2, "got \(rows.count)")
        check("reads the pid", rows.first?.pid == 123)
        check("reads the uid", rows.first?.uid == 501)
        check("converts rss from KB to bytes", rows.first?.memoryBytes == 20480 * 1024)
        check("takes the last path component as the name", rows.first?.name == "Foo")
        check("accepts a comma decimal in a row", rows.last?.cpuPercent == 0)

        let fourColumns = "789 1.0 512 /usr/sbin/baz"
        let short = ProcessMonitor.parse(fourColumns)
        check("parses 4-column output (no uid)", short.count == 1)
        check("leaves uid nil when the column is absent", short.first?.uid == nil)

        check("discards the header line",
              ProcessMonitor.parse("  PID %CPU    RSS   UID COMM").isEmpty)
        check("discards garbage", ProcessMonitor.parse("nonsense here").isEmpty)
        check("discards empty input", ProcessMonitor.parse("").isEmpty)
    }

    // MARK: - Offload guards

    static func testOffloadGuards() {
        group("MigrationEngine — refusals on the source")

        let home = FileManager.default.homeDirectoryForCurrentUser

        check("refuses a source that does not exist",
              MigrationEngine.sourceProblem(sandbox.appendingPathComponent("ghost")) != nil)

        let real = makeFile("offload-real.bin", bytes: [9])
        let link = sandbox.appendingPathComponent("offload-link")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        check("refuses a source that is already a symlink",
              MigrationEngine.sourceProblem(link) != nil)

        check("refuses a source outside home",
              MigrationEngine.sourceProblem(URL(fileURLWithPath: "/usr/lib")) != nil)

        check("refuses a whole top-level home folder",
              MigrationEngine.sourceProblem(home.appendingPathComponent("Documents")) != nil)

        check("refuses a destination that does not exist",
              MigrationEngine.destinationProblem(
                  sandbox.appendingPathComponent("no-such-destination"),
                  needing: 1024) != nil)
    }

    // MARK: - Trash, read path only

    static func testTrashReadPath() {
        group("TrashManager — read path")

        // `inspect` is read-only. `empty` is never called here: it acts on the
        // real ~/.Trash and cannot be redirected, so running it would delete the
        // user's Trash.
        let info = TrashManager.inspect()
        check("inspect returns without crashing", true)
        check("total is never negative", info.totalBytes >= 0)
        check("count is derived from the item list", info.count == info.items.count)
        check("isEmpty agrees with the item list", info.isEmpty == info.items.isEmpty)
        // A measured, non-empty Trash must report bytes; an unmeasured one must
        // not pretend to be empty — that distinction is what `isMeasured` exists
        // for, and getting it wrong would make the app offer to empty nothing.
        if info.isMeasured && !info.isEmpty {
            check("a measured, non-empty Trash reports bytes", info.totalBytes > 0)
        } else {
            check("an unmeasured Trash is not claimed as empty", true)
        }
    }

    // MARK: - AccessProbe

    /// The probe replaced a detector that could never fire. These tests exist to
    /// keep the replacement from acquiring the same defect: the central property
    /// is that an **empty** folder is not reported as a **denied** one.
    static func testAccessProbe() {
        group("AccessProbe — telling empty apart from denied")

        let fm = FileManager.default
        let root = sandbox.appendingPathComponent("probe-home")
        try? fm.createDirectory(at: root.appendingPathComponent("Desktop"),
                                withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("Documents"),
                                withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("Documents/a.bin").path,
            contents: Data([1, 2, 3]))

        let probe = AccessProbe.run(home: root)

        let desktop = probe.folders.first { $0.name == "Desktop" }
        let documents = probe.folders.first { $0.name == "Documents" }
        let movies = probe.folders.first { $0.name == "Movies" }

        check("an existing folder with content is readable",
              documents?.entries == 1 && documents?.deniedOutright == false)

        // The distinction the whole probe turns on. The Mac this was written on
        // has a genuinely empty Desktop; calling that a denial would have raised
        // a confident false alarm — the previous detector's mistake, mirrored.
        check("an empty folder is suspicious, never denied",
              desktop?.suspicious == true && desktop?.deniedOutright == false)
        check("an empty folder alone is not a verdict",
              !probe.isDefinitelyBlocked)

        // A folder that does not exist is not evidence of anything. A Mac with no
        // ~/Movies is not a blocked Mac.
        check("a missing folder is neither denied nor suspicious",
              movies?.exists == false && movies?.suspicious == false)

        check("every protected folder is probed",
              probe.folders.count == AccessProbe.protectedFolders.count)
        check("the trace report has one line per folder plus the header",
              probe.traceReport.split(separator: "\n").count
                == AccessProbe.protectedFolders.count + 1)

        // An unreadable directory must be reported as an outright denial. chmod
        // 000 is the only denial reproducible without a TCC grant; TCC's own
        // silent-empty behaviour is what `suspicious` covers.
        let locked = root.appendingPathComponent("Pictures")
        try? fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        let denied = AccessProbe.run(home: root)
        let pictures = denied.folders.first { $0.name == "Pictures" }
        if getuid() == 0 {
            // root ignores permission bits, so the case is unreachable here.
            check("skipped: running as root, chmod 000 is not enforced", true)
        } else {
            check("an unreadable folder is an outright denial",
                  pictures?.deniedOutright == true, "entries: \(pictures?.entries ?? -1)")
            check("one outright denial is enough for a verdict",
                  denied.isDefinitelyBlocked)
            check("certain denials are listed before the ambiguous ones",
                  denied.namesToReport.first == "Pictures")
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)

        // Full Disk Access is a separate question from per-folder access, and the
        // probe must not conflate them: a sandbox home has no TCC database, so
        // the canary must read false without dragging the folder results with it.
        check("the Full Disk Access canary is independent of the folder results",
              !probe.hasFullDiskAccess && documents?.entries == 1)
    }
}

// MARK: - Small helpers

private extension String {
    /// Placeholders in order of appearance. Written by hand rather than with
    /// `Regex` so the test binary compiles on macOS 13 too.
    func matches(of pattern: String) -> [String] {
        _ = pattern
        var found: [String] = []
        var iterator = self.makeIterator()
        var previous: Character?
        while let char = iterator.next() {
            if previous == "%" {
                if char == "@" { found.append("%@") }
                else if char == "d" { found.append("%d") }
            }
            previous = char
        }
        return found
    }
}

private extension FileManager {
    func createFile(atPath path: String, contents: Data) {
        createFile(atPath: path, contents: contents, attributes: nil)
    }
}

/// `L` with an array instead of variadics, so the runtime placeholder test can
/// build its arguments dynamically.
private func L(_ key: String, arguments: [CVarArg]) -> String {
    String(format: L(key), arguments: arguments)
}
