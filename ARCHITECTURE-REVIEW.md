# Architecture review

A meticulous pass over all 54 Swift files (16,000 lines), evaluating design
patterns, SOLID and DRY. Two independent audits — one for duplication, one for
coupling and layering — plus a manual read of the core. This document records
the verdict, what was fixed immediately, and what is deliberately staged.

The point of this file is not the grade. It is that half of the findings below
would be *worsened* by mechanical application of the principles they violate,
and the reasoning for each of those calls is worth more than the fixes.

## The verdict, per principle

**Layering — good, with one hard cycle (fixed).** No domain file imports
SwiftUI; dependencies point `Views → AppState → Domain → Support`. The one
cycle was `AppState → AppSection → SaveMyMacApp.swift`: the view-model depended
on the `@main` file, which kept `AppState` out of the test target — the app's
central object was untestable by construction, and `tools/e2e.sh` documented
that in a comment. Moving one enum to `Support/` fixed it; `AppState` is now
compiled into the behavioural tests.

**SRP — the weak spot, concentrated in known places.** `AppState` (1,216
lines) coordinates six domains, and carries four nearly identical copies of a
35-line scan driver. `ProcessMonitor` holds four unrelated jobs (subprocess
infra, `ps` parsing, a global error channel, AppKit enrichment).
`ThermalMonitor` holds three. These are real, they are also *stable* — they
change rarely and are heavily documented — so they are staged, not rushed (see
backlog).

**OCP/LSP/ISP — mostly not applicable, honestly.** Zero protocols exist in the
project. For an app this size with exactly one implementation of everything,
protocol-first design would be ceremony; the one place a protocol would pay
for itself today is the five scanners, which already share an identical
signature by convention (`scan(progress:isCancelled:)`) — convention is the
worst way to keep five things identical, so that is the top backlog item.

**DIP — violated in the places that hurt testing.** `Store.directory`,
`TrashManager.trashURL` and `Localization.active` are hardwired globals. The
project's own test suite states the cost: `TrashManager.empty` — the only
irreversible operation — is untested *because the path cannot be injected*.

**DRY — two clusters, and a lot of healthy non-duplication.** Cluster one: the
scan plumbing (drivers in `AppState`, headers/banners/empty-states in five
views). Cluster two: file measurement (two identically-named private
`fileSize(_:)` helpers plus six inline copies with a drifted fallback chain —
fixed with `URL.allocatedBytes`). Everything else that *looks* duplicated
mostly is not — see "What will NOT be unified".

## Bugs found by the audit (all fixed)

These are behavior bugs, not style. An architecture review that finds no bugs
was not looking.

1. **`Fmt` hardcoded `pt_BR`** in both date formatters while the Settings
   screen promised "dates follow your system region". One of those dates feeds
   the Trash-empty confirmation. Formatters are now cached per app language.
2. **`CleanupRecord.kind` was a raw string compared against Portuguese
   literals.** The Dashboard rendered it verbatim — "limpeza", "lixeira" in
   every language. Worse: one call site persisted `L("uninstall")`, so the
   stored value depended on the interface language at write time, and the XP
   counter matched it against `L("uninstall")` at read time. Now a typed enum
   whose raw values match what is already on disk, with tolerant decoding for
   the language-tagged legacy values.
3. **Every rollback in `MigrationEngine` reported "original restored" without
   checking.** The move back from quarantine was `try?`. If it failed, the user
   was told their data was safe at a moment it wasn't. Rollbacks now verify
   and, on failure, name the quarantine path where the data actually is.
4. **The migration journal could fail to write, silently, at the exact moment
   it becomes the only map to the user's data.** `Store.save` returned `Void`
   with the write in `try?`. It now reports failure, and the quarantine step
   refuses to move anything it cannot journal first.
5. **A corrupt journal read as "no migrations exist"** while quarantined
   originals sat on disk (`load` returned the same `nil` for missing and for
   corrupt). Corrupt files are now set aside as `.corrupt` and traced, never
   overwritten.
6. **`measure()` skipped unreadable files silently — inside the copy
   verification.** A source with unreadable entries produced an undercount, the
   equally incomplete copy matched it, and the original went to quarantine on a
   verification that verified nothing. Migration now refuses to start if the
   source has unreadable entries.
7. **`ProcessMonitor.shell` was a second, weaker subprocess implementation** —
   the serially-drained single pipe that `run`'s own comment forbids (64 KB
   deadlock), safe only because it discarded stderr. It now delegates to `run`,
   and failures reach the trace instead of collapsing into `nil`.
8. **~40 more untranslated Portuguese strings** in positions the checker didn't
   watch: `progress()` status lines, `fail()` messages, `.help()` tooltips,
   interpolated tuple values in `sourceProblem`. Fixed, and the checker learned
   each position (its fifth and sixth holes — every one had the same shape: a
   UI position its list didn't know about).
9. Assorted: dead `AppKit` imports in two domain files; preference keys
   duplicated as raw literals across files; `EmptyStateView`'s minimum height
   repeated at six call sites, one of which had drifted to a different value.

## What will NOT be unified, and why

DRY is about knowledge, not text. These look duplicated and are not:

- **The three path-safety guards** (`CleanupRemover.rejectionReason`,
  `AppUninstaller.rejectionReason`, `MigrationEngine.sourceProblem`). Same
  skeleton, deliberately different policies: uninstall must allow `.app`
  bundles in `/Applications`, cleanup must forbid them; migration bans
  `Library/Containers` wholesale, the others allow it. Each is a security
  boundary, each divergence has a documented reason. One parameterised guard
  would turn three auditable lists into one list plus three exception sets —
  harder to review, and a mistake in the shared path is data loss in three
  features. *(One flag: only `CleanupRemover` protects `~/Developer`. That
  looks like drift, not policy — worth an explicit decision.)*
- **The five `scan()` bodies.** The signatures should unify behind a protocol;
  the internals must not. `FileScanner` is a deep flat walk with package
  opaqueness; `OffloadScanner` is bounded-depth recursion that must never
  follow symlinks; `CleanupScanner` is a shallow catalog sweep. A common
  `DirectoryWalker` would need more configuration surface than the three call
  sites have code.
- **`LargeFile.ageLabel` vs `InstalledApp.lastUsedLabel`.** Same bucketing
  shape, different vocabulary on purpose ("3 months" vs "used 90 d ago").
  Unifying the label would make one of the two screens say something slightly
  wrong forever.
- **Similar-looking exclusion lists** in FileScanner and OffloadScanner encode
  opposite intents (not-worth-listing vs cannot-contain-a-link).

## Staged backlog (ordered, each one PR-sized)

1. **Unify the four scan drivers in `AppState`.** One `ScanTask` value
   (isScanning/progress/status/lastDate) plus one generic runner removes ~140
   lines and 16 `@Published` properties. Biggest single win in the codebase.
   Wants a compiler in the loop — that is the only reason it isn't in this
   commit.
2. **`ScanHeader` + `ScreenScroll` + `Callout` view components.** The five
   scan screens repeat the same header block (~90 lines), page chrome (6×) and
   tinted-callout chrome (7×). Pure view extraction, no behavior.
3. **Injectable roots for `Store` and `TrashManager`.** Two initializer
   parameters with the current values as defaults. Unlocks testing `empty`,
   the journal, and the game store against a temp directory.
4. **Move theme ownership.** `GameState.theme: ThemeMode` makes the persisted
   progress model depend on a SwiftUI file. Theme belongs in `Preferences`;
   `ThemeMode` belongs outside `Theme/Palette.swift`. Needs a small data
   migration for existing `game.json`.
5. **Extract subprocess infra from `Metrics/` into `Support/`** and give `run`
   a timeout. Today `ditto` on a wedged external volume parks a worker thread
   forever, and mid-copy cancellation does not exist
   (`AppState` passes `isCancelled: { false }` to `migrate`).
6. **Unify the failure vocabulary.** `failures: [(path, reason)]` is declared
   four times; `ProcessController.Outcome` is the one well-modelled error type
   in the app and nothing else uses the pattern. One `ItemFailure` struct, one
   naming convention (`…Result` everywhere or `…Outcome` everywhere).
7. **Retire `AppRoot.shared` in favor of `@StateObject` at the App level.**
   The 7,200-rebuild loop it guards against is real, but the rest of the file
   already solves it the idiomatic way (never read observed state in the App
   body). Verify with the trace counters that exist for exactly this.
8. **`forceCLocale` should be the default** in `ProcessMonitor.run`, opt-out —
   `launchctl`'s stderr is string-matched in English today.

## How this was verified

No compiler was available in the review environment, so: every edit was made
with exact-match assertions (count == 1 before replacing), brace/paren/bracket
balance was checked on all 25 touched Swift files, and the three static
checkers pass (`check-translations`: 649/652/648 keys, no errors;
`check-untranslated-ui`: clean; the e2e static phase). The behavioural test
run and a full build are the required next step, and item 1 of the backlog
should not start until this commit has been built and run.
