# Contributing to SaveMyMac

Thanks for considering it. This document is short on ceremony and long on the
few things that actually matter in this codebase.

🇧🇷 Comentários em português no código são esperados por enquanto — ver
[Language](#language).

---

## Getting it running

```bash
xcode-select --install        # only if swiftc is missing
cd SaveMyMac
./build.sh --run
```

That's the whole setup. No package manager, no Xcode project, no generated
files. `build.sh` globs `Sources/**/*.swift`, so a new file is picked up with no
registration step.

If the build fails on a fresh clone, that's a bug — open an issue.

## The rule that matters most

**Code that deletes files is reviewed to a different standard.**

That means `Cleanup/CleanupRemover.swift`, `Cleanup/TrashManager.swift`,
`Apps/AppUninstaller.swift`, `Offload/MigrationEngine.swift`, and
`Support/VolumeResolver.swift`.

For changes in those files, expect to be asked:

- Does it still refuse to follow symlinks? A cache "inside" the home folder can
  be a symlink to an external disk. An earlier version counted that space as
  reclaimable and would have deleted on the wrong volume.
- Does it still go to the Trash rather than unlinking, where possible?
- For duplicates: is the byte-by-byte comparison still there? Grouping by size
  and hash is not sufficient justification for deleting someone's file.
- Does anything become deletable without the user having checked a box?

A PR that makes cleanup faster by removing a safety check will be declined, even
if the measurement is real.

## Five bugs worth not reintroducing

These cost a full night of debugging between them. All five are documented in
the source at the point where they matter; this is the short version.

**1. Never do blocking I/O in a view initializer.**
`SettingsView` initialized `@State` with `LaunchAtLogin.isEnabled`, which calls
`SMAppService.status`. That looks like a property getter and is actually a
synchronous XPC round trip to `smd`. SwiftUI builds the `Settings` scene content
on every App body evaluation — even with the window closed — so the app made
dozens of blocking IPC calls per second until `smd` stopped answering and the
main thread parked in `mach_msg`.

**2. Never publish a change that did not happen.**
`@Published` sends `objectWillChange` on *every* assignment, including
assignments of an equal value. `MenuBarExtra(isInserted:)` writes to its binding
on every update pass. Together that was an update cycle running at CPU speed:
6,600 scene rebuilds in 9.6 seconds, 100% of a core, memory climbing 86 MB in 13
seconds. Every setter in `Preferences` now compares before publishing. Keep it
that way.

**3. Don't let the App body observe fast-changing state.**
Re-evaluating the App body triggers `scenesDidChange`, which rebuilds the
system's main menu. `AppState` publishes about ten times per metrics tick. The
objects live in `AppRoot` and the App holds them without observing; views
subscribe through `@EnvironmentObject`, which is where observation belongs.

**4. Drain subprocess pipes concurrently.**
Reading stdout to EOF and *then* stderr deadlocks if the child fills the 64 KB
stderr buffer: it blocks writing, never closes stdout, and the parent waits
forever. Silent — nothing crashes, the thread just disappears. See
`ProcessMonitor.run`.

**5. macOS denies file access by returning nothing, not by erroring.**
`FileManager.enumerator` does not report a TCC denial through its `errorHandler`
— it descends, finds an empty directory, and continues. The Large Files screen
was built on that error count and reported zero denials while walking 46 files in
a home folder that really held 1,360 over 2 MB. It then said "no large files
found", which is indistinguishable from a tidy Mac.

A shallow `contentsOfDirectory` *does* throw where the deep enumerator stays
quiet; that difference is what `AccessProbe` is built on. If you add a scan,
probe access separately and state the scope on screen. Do not infer permission
from a walk.

## The failure mode behind most of the above

Every one of those bugs was found late because a check measured something *near*
the thing it claimed to measure, and the near-miss read as a pass:

| The check | What it actually measured |
|---|---|
| menu bar item present | a window named `StatusBar` existed — SwiftUI creates it even when hidden |
| CPU healthy (`ps -o %cpu`) | average over process lifetime, so launch cost read as 42% steady load |
| Portuguese fully translated | presence of accented characters — missed `Text("Conquistas")`, 99 strings |
| ditto, second attempt | lowercase accents only — missed `MARK: - Varredura`, 31 lines |
| untranslated UI literals | literals with a UI token *on the same line* — missed `case .image: return "Imagens"` |
| scan blocked by permission | enumerator errors, which TCC never emits |

Before trusting a green check, ask what would have to be true for it to pass
while the thing it guards is broken. A check that can pass wrongly is worse than
no check: it hands out confidence it has not earned.

## Testing

```bash
cd SaveMyMac
./tools/e2e.sh              # everything
./tools/e2e.sh --quick      # skips the universal build and the runtime phase
```

Four phases, cheapest first, each gating the next:

**1. Static** — translation tables, hardcoded UI strings, and the two regressions
no compiler catches (`@Published` in `Preferences`, `SMAppService` in `Views/`).

**2. Build** — compiles universal, then checks the artifact rather than trusting
the exit code: executable present, Info.plist, icon, both fonts, both
architectures, valid signature.

**3. Behavioural** — `tests/E2EMain.swift`, compiled from the same sources as the
app minus the UI layer, so it links the real implementations. It runs the
safety-critical functions against real files in a temporary directory: the
symlink guard, every `CleanupRemover` refusal, byte-by-byte duplicate comparison
including the same-size-different-middle case, the `ps` parser with comma
decimals, the offload source guards, and the French zero-plural rule.

**This is the only phase that executes the code that deletes files.** Everything
before it is a regex over source text — it can tell you a guard is still written,
never that it still refuses. If you change anything in `Cleanup/`, `Offload/` or
`Apps/AppUninstaller`, this phase is the review.

**4. Runtime** — launches the app for 15 s and reads the trace: no main-thread
stall, no update-loop counters firing, HID clients created at most twice, metric
ticks at the expected cadence, CPU at rest under 15%, quits on request.

Two deliberate gaps, both documented in the test file:

- `TrashManager.empty` is never called. It acts on the real `~/.Trash` with no way
  to redirect it, so running it would delete your Trash. Only `inspect` is
  exercised.
- The "content lives on another disk" guard is tested for symlinks but not for a
  real second mount, which would require the machine to have one.

Phases 1–3 run in CI on every PR.

## Debugging

The app writes an execution trace to `~/Library/Logs/SaveMyMac-trace.log` using
raw `write(2)`, not `os_log`. That choice is deliberate: when the app hangs and
gets force-killed, the unified log may have written nothing at all.

Every suspicious call site marks entry and exit, so **when the app freezes, the
last line of the file is where it stopped.** A watchdog thread also records when
the main thread stops responding.

```bash
tail -40 ~/Library/Logs/SaveMyMac-trace.log
./SaveMyMac/tools/collect-hang-report.sh   # binary, trace, spindump, resources
```

If you file a hang report, `collect-hang-report.sh` output is what makes it
actionable. Use `spindump` rather than `sample` — `sample` fails to read thread
state on a wedged process.

## Style

- Follow the surrounding code. There is no linter and no formatter config.
- Comments explain **why**, not what. `// increment counter` adds nothing;
  `// This must be idempotent because MenuBarExtra writes on every pass` earns
  its line.
- When you fix a non-obvious bug, leave a note at the site explaining what broke.
  Half the comments in this codebase are that, and they are the useful half.
- No force unwrapping on anything derived from the filesystem. Disks lie,
  permissions change, volumes unmount mid-scan.

## Language

**Identifiers are English.** They always were.

**Comments are being migrated from Portuguese to English.** The project started
as a personal tool, so the prose is Portuguese. Migration is in progress. If you
touch a file with Portuguese comments, translating them in the same PR is
welcome but never required — and please don't submit PRs that *only* reformat
comments in files you aren't otherwise changing, since that collides with the
migration.

**UI strings are bilingual.** They live in the localization table, not inline in
views. Add both languages when you add a string; the language is user-selectable
in Settings and defaults to the Mac's language.

## Pull requests

- One concern per PR. A PR that fixes a bug and also renames things is two PRs.
- Say what you tested. "Builds" is not testing for a tool that deletes files.
- Screenshots for UI changes, in both themes if the change touches colors.
- CI compiles on macOS for every PR. It has to be green.

## Reporting bugs

Use the issue templates. For anything involving unexpected deletion, or data
loss, please use the private path in [SECURITY.md](SECURITY.md) instead.
