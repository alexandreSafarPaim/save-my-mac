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

## Four bugs worth not reintroducing

These cost a full night of debugging between them. All four are documented in
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

## Debugging

The app writes an execution trace to `~/Library/Logs/SaveMyMac-trace.log` using
raw `write(2)`, not `os_log`. That choice is deliberate: when the app hangs and
gets force-killed, the unified log may have written nothing at all.

Every suspicious call site marks entry and exit, so **when the app freezes, the
last line of the file is where it stopped.** A watchdog thread also records when
the main thread stops responding.

```bash
tail -40 ~/Library/Logs/SaveMyMac-trace.log
./diagnostico.sh                 # full report: binary, trace, spindump, resources
```

If you file a hang report, `./diagnostico.sh` output is what makes it
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
