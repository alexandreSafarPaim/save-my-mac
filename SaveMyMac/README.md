<img src="Resources/logo-1024.png" width="128" align="right" alt="SaveMyMac">

# SaveMyMac

🇧🇷 [Leia em português](README.pt-BR.md)

A native SwiftUI app that shows the machine's real state, lists what can be
removed **with a checkbox on every item**, and offloads heavy folders to an
external disk leaving a symlink in their place.

Layout designed in Claude Design and ported to native SwiftUI. Six screens,
light and dark themes, embedded variable fonts.

---

## 1. Building

Only Apple's Command Line Tools are needed — no Xcode:

```bash
xcode-select --install     # only if swiftc doesn't exist yet
cd SaveMyMac
chmod +x build.sh
./build.sh --run
```

| Command | What it does |
|---|---|
| `./build.sh` | compiles for your machine's architecture |
| `./build.sh --universal` | universal binary (Apple Silicon + Intel) |
| `./build.sh --run` | compiles and opens the app |
| `./build.sh --install` | **installs to `/Applications`** |
| `./build.sh --dmg` | builds a distributable installer `.dmg` |

### Installing as a real app

```bash
./build.sh --install --run
```

This does what dragging by hand does not:

- **Quits the running instance** before replacing the bundle. Swapping files
  under a running app leaves a process pointing at paths that no longer exist.
- **Removes the quarantine attribute.** The app was compiled here, not
  downloaded — without this, macOS would ask for confirmation on every launch.
- **Registers with Launch Services** (`lsregister -f`), so it shows up in
  Spotlight and Launchpad immediately, without waiting for reindexing.
- **Opens the Full Disk Access pane** at the end, because that is the one step
  that cannot be automated.

After that it is a normal app: ⌘Space, "SaveMyMac", enter.

### Building an installer for someone else

```bash
python3 tools/make-dmg-background.py   # first time only
./build.sh --dmg
```

Out comes a `build/SaveMyMac.dmg` with the app, an Applications shortcut and a
background with the arrow indicating the drag. The window layout is applied via
Finder, which depends on the Automation permission — if it fails, the DMG still
works, it just opens without the positioning.

#### The Finder label and the contrast math

Finder draws the name under each icon by itself, in the system appearance's
color: **black in light mode, white in dark mode**. The DMG background is a
fixed image, so neither extreme works:

| Background | Light mode | Dark mode |
|---|---|---|
| dark | 1.1:1 — unreadable | 18.8:1 |
| light | 17.9:1 | 1.2:1 — unreadable |

This can be solved with arithmetic instead of guessing. Setting the two WCAG
contrast formulas equal:

```
(L + 0.05) / 0.05  =  1.05 / (L + 0.05)   →   L = 0.179
```

At that luminance the contrast is **4.58:1 against black and 4.59:1 against
white** — the best possible worst case. In sRGB that is the gray `#757575`; in
the brand's ink, `#7D6D9B`.

Hence the design: dark background with two **half-tone plates** behind the
labels. `make-dmg-background.py` measures this on every generation and prints
both contrast ratios, instead of trusting the eye.

Two discarded attempts: a band across the window solved the contrast but cut
the icons in half; a large pedestal behind icon + label became a heavy block
and took the colorful icon off the dark background, where it looks best.

`--light` generates the light-background variant, if you only use light mode.

**The honest limitation:** the app is **ad-hoc signed**, not notarized. On your
own Mac that is irrelevant, because building locally sets no quarantine. On
**another** Mac, macOS will block the first launch — the person needs **System
Settings › Privacy & Security › Open Anyway**, or
`xattr -d com.apple.quarantine`. (The old right-click → Open trick no longer
offers "Open" for unnotarized apps on recent macOS.) Real notarization requires
a paid Apple Developer Program account and a pass through `notarytool` — there
is no scripting around that.

**Important permission:** grant **Full Disk Access** in System Settings →
Privacy & Security. Without it the app works, but several folders come back
empty and the numbers are underestimated. `--install` opens the pane for you,
and there is a button for it inside the app.

---

## 2. Visual system

Translated from the design's CSS variables:

| Token | Dark | Light |
|---|---|---|
| Background | `#08070F` / `#0D0B18` | `#EFEDF7` / `#F7F6FC` |
| Accent | `#7C5CFF` → `#22E0FF` | `#6A3FF5` → `#0FA5C9` |
| OK / caution / danger | `#3BE8A0` / `#FFB020` / `#FF5A6E` | `#0FA86E` / `#C97A00` / `#E0344B` |
| Text | `#F2F0FF` at 100 / 62 / 34 % | `#14102D` at 100 / 62 / 38 % |

**Fonts:** Space Grotesk for the interface, JetBrains Mono for numbers and
labels. The design bundle's `woff2` files were converted to **variable TTF**
(`wght` axis 300–700 and 400–800), renamed to expose the family correctly and
embedded in `Contents/Resources/Fonts`. `ATSApplicationFontsPath` in the
Info.plist makes macOS register them for this app only — nothing is installed
system-wide. If registration fails, everything falls back to SF Pro and SF Mono
without breaking the layout.

**Motion:** the eight named CSS animations (`smRise`, `smPop`, `smRing`,
`smScan`, `smBar`, `smFloat`, `smPulse`, `smDash`) have equivalents in
`Theme/Motion.swift`.

### Two deliberate divergences

**The fake window.** The design draws the three colored macOS buttons and a
centered strip at the top — that is mockup chrome. Reproducing it would give
two sets of buttons, because the real window already has its own. The app uses
`.hiddenTitleBar` and puts the strip and the theme button in a band of their
own, respecting the native controls' space.

**`backdrop-filter`.** The native equivalent is `.ultraThinMaterial`, which
respects the system blur instead of accepting an arbitrary radius. Very close,
not identical.

### The brand

The design's 4-point sparkle (tips on the axes, waist at 30% on the diagonal)
inside the gradient square, with the progress ring at 78%. One single
definition, in `tools/make-icon.py`, generates everything:

```bash
python3 tools/make-icon.py            # gradient variant (default)
python3 tools/make-icon.py --dark     # dark variant as the main icon
```

| Output | Purpose |
|---|---|
| `Resources/AppIcon.iconset/` | the 10 PNGs `iconutil` packs into the `.icns` — `build.sh` does that and only regenerates when the art changes |
| `Resources/logo.svg` | the brand as vector |
| `Resources/logo-1024.png` | README and promotion |
| `Resources/logo-dark.png` | the alternate variant |

The same drawing exists in SwiftUI (`Theme/Brand.swift`) as `Sparkle` (a
`Shape`) and `BrandMark`, used in the sidebar and the completion screen. No
bitmaps in the interface.

Three details that keep the icon from looking amateur:

**Different art at small sizes.** At 16 px the ring and the sparkle touch and
become a gray smudge. Below 64 px the iconset gets a ring-less version with a
bigger, fatter sparkle. That is what a well-made icon does, and the iconset
format exists precisely to allow it.

**A real squircle.** The macOS corner is a continuous curve, not a circular
arc. The mask is a superellipse (`|x|ⁿ + |y|ⁿ = 1`, n = 6.2), because PIL's
`rounded_rectangle` only does circular corners. The SVG uses an `rx` of 22.5%,
the standard approximation — SVG has no continuous corner.

**Apple's grid.** 824 px of content on a 1024 canvas, with a discreet shadow,
as the macOS specification demands since Big Sur.

---

## 3. Dashboard

Refreshes every 2 seconds.

**Health score 0–100.** There is no "health score" in macOS — this is the
app's own index, and for that reason it is fully explainable: click *How this
number is calculated* and every factor appears with its weight and the reason
for its grade.

| Factor | Weight |
|---|---|
| Free space on the boot disk | 34 |
| Memory pressure | 18 |
| Temperature / thermal state | 14 |
| Accumulated junk (proportional to disk) | 14 |
| Swap usage | 10 |
| Duplicates | 6 |
| Broken offload links | 4 |

**Metric cards:** memory decomposed as in Activity Monitor (apps, wired,
compressed, cache) plus swap and pressure; CPU by tick delta with load average
and process count; temperature; storage with every volume. Plus the real
cleanup history.

### Memory: why there is no "free memory" button

This is the most marketed feature of Mac cleaners and the least useful one, so
its absence deserves an explanation.

**On macOS, free RAM is wasted RAM.** The kernel deliberately uses all spare
memory as disk cache. Seeing "13% free" is not a problem — it is the system
working. The metric that matters is **memory pressure**.

The two common implementations of "free memory":

| Trick | What it actually does |
|---|---|
| `sudo purge` | drops the file cache and inactive pages. The "free" number goes up instantly and for the next several minutes everything gets **slower**, because what was cached comes back from disk. Doesn't touch swap. It is a benchmarking tool, for measuring with a cold cache. |
| allocate a giant block and release it | forces the kernel to compress and swap out the working set of the apps in use. Actively makes things worse. |

So the app does something else, which attacks the cause:

**Pressure curve for the last 15 minutes.** An instantaneous number does not
answer the real question. "Green for the last half hour" says more RAM would
solve nothing today; "red for ten minutes" says something is out of control.
The chart has reference lines at 35% and 60%, the same cutoffs as the
Normal / Moderate / High labels.

**Growth detection.** The app tracks each process's RSS across the session and
marks with an amber badge whoever grew more than 250 MB **and** more than 50%
relative to when it was first seen, with at least 2.5 minutes of observation.
That minimum avoids accusing an app that just launched and naturally grew while
loading. It is the leak symptom that an instantaneous number hides.

**Quitting what is eating memory.** In each process's menu:

- *Ask to quit* — for an app with an interface, sends the same event as ⌘Q, so
  it can ask about unsaved work; for a daemon, `SIGTERM`.
- *Force quit* — `forceTerminate`/`SIGKILL`, only after explicit confirmation,
  because then whatever wasn't saved is lost.

Guards: it never quits pid ≤ 1, nor SaveMyMac itself, nor the ~29 processes on
the critical list (killing `WindowServer` takes down the interface; killing
`launchd` reboots the machine), nor another user's process — and in that case
the app does **not** escalate privileges, because trading stability for a
number is not worth it. Processes macOS relaunches by itself (Finder, Dock) are
allowed with a warning.

An implementation detail worth recording: the pretty name and the icon come
from `NSRunningApplication`, which is AppKit. Resolving that during the `ps`
parse would mean hundreds of AppKit queries on a background thread every 2
seconds — so the enrichment happens on the main thread and only for the ~12
rows that reach the screen.

### About temperature on the Mac

The honestly hard part: Apple exposes no public API for CPU temperature. The
app tries, in order:

1. **IOHID sensors** (`IOHIDEventSystemClient`) — works on several Apple
   Silicon Macs, no password. It is a private API, resolved at runtime with
   `dlsym`: if Apple changes something, the app stops showing the temperature
   instead of crashing.
2. **Battery temperature**, from the IORegistry — almost always available on
   laptops.
3. **Thermal state** (`ProcessInfo.thermalState`) — Normal / Warming / Hot /
   Critical. Always available.
4. **Admin read button** — runs `powermetrics` once via `osascript`, with the
   native password dialog. On Intel Macs it reliably delivers CPU/GPU
   temperature and fan RPM.

---

## 4. Cleanup

The scan is **read-only**. Nothing leaves until you check it and confirm.

Each category has a risk level and a **RISK n/10** grade, more granular than
the level — "caution" spans everything from npm cache (4) to iOS simulators
(5).

| Risk | Meaning | Pre-checked |
|---|---|---|
| 🟢 Safe (1–2) | temporary, the system recreates it | yes |
| 🟠 Caution (3–5) | recreatable, but costs a download or a build | no |
| 🔴 Review (6–10) | may contain your own files | no |

**Categories:** application caches (including inside sandboxed containers),
logs and crash reports, `.DS_Store`, developer tools (DerivedData,
DeviceSupport, simulators, VS Code, JetBrains, Android system images, Docker's
VM), the caches of 22 package managers, `node_modules` with no activity for 90
days, `.dmg`/`.pkg`/`.iso` installers, old downloads, local iPhone/iPad
backups, and leftovers from uninstalled apps.

The default removal mode is **Move to Trash**. The celebration says "moved to
the Trash" in that case, not "freed", because the space only comes back when
you empty it.

### Emptying the Trash

A card at the top of the Cleanup tab, with the total, the count and the date of
the oldest item. **Scope: `~/.Trash` only.** Every external volume has its own
Trash at `/Volumes/<name>/.Trashes/<uid>/` and those are not touched.

This is the app's only irreversible operation — there is no "move to Trash" for
what is already in it — so it always goes through a confirmation with the total
and the count.

The Trash is **not** a scan category anymore, and that fixes a bug: in the
default mode the remover called `trashItem` on something already in the Trash,
which Cocoa rejects — or worse, renames within it, making the app report
success without freeing a single byte. Emptying is always permanent, so it
cannot share the other categories' code path.

Three safeguards:

- **It enumerates the folder live**, never the on-screen list. The interface's
  snapshot can predate the latest cleanup — and it is precisely the cleanup
  that fills the Trash. Iterating the snapshot, the app would say "emptied"
  without deleting what had just been moved there.
- **It refuses if `~/.Trash` is not a real folder.** `standardizedFileURL`
  resolves `.` and `..` but does not resolve symlinks; without this check, a
  redirected Trash would make the app recursively delete the target.
- **It does not reward zero removals.** An already-empty Trash or items locked
  with `chflags uchg` produce a warning, not XP and a celebration.

---

## 5. Applications

Lists installed apps with real size, icon and **last use** (via Spotlight's
`kMDItemLastUsedDate`, queried in parallel). Apple's built-in apps are
excluded.

For each app, the scanner sweeps 12 places in the Library and shows everything
it left scattered — cache, support data, containers, saved state, HTTPStorages,
WebKit, logs, preferences, scripts, cookies, launch agents. Matching is by
bundle id, by prefix (`com.foo.App.Helper`) and by name.

Two actions:

- **Clear cache** — removes only what is regenerable.
- **Uninstall** — the bundle plus all support data, with the total confirmed
  first.

Everything through the Trash, always. No operation asks for a password. If the
bundle is somewhere that requires privileges, the failure is reported with the
instruction instead of escalating on its own.

---

## 6. Large files and duplicates

**Treemap** proportional by kind — videos, virtual machines, disk images,
backups, audio, images, archives, databases. Click a band to filter the list.

**Grouped duplicates.** Two safeguards worth explaining:

1. The scan groups by exact **logical size**, not by allocated-on-disk size. On
   APFS, clones and sparse files have an allocated size different from the
   logical one: using the allocated size would keep real duplicates from
   grouping, and would promise space that deleting a clone does not return.
2. The sample hash (3 × 256 KB) is fast enough for hundreds of thousands of
   files, but can collide on different files — two VM disks cloned and later
   diverged in the middle, for instance. So **before deleting**, every copy is
   compared **byte by byte** against the original. The ones that fail are
   preserved and reported.

The oldest copy in each group is always preserved and never appears in the
removal.

---

## 7. Offload via symlink

Moves a heavy folder to another disk and leaves a link in its place. macOS
keeps finding everything; the space returns to the internal SSD.

### Candidates

The app does not suggest by size. The distinction is between big-and-cold,
regenerable, and managed-by-someone-else:

| Verdict | When | Examples |
|---|---|---|
| **Good candidate** | big, cold, no native alternative | iOS DeviceSupport, simulators, iPhone backups, Android SDK, AVDs, Movies, VMs, Ollama models |
| **Better to delete** | regenerable and cheap | npm, pip and Homebrew caches, and Xcode's DerivedData — which on an external disk makes builds *slower* |
| **Use the app's setting** | the app manages the file | Docker (Settings → Resources → Disk image location), Steam (library folders), Adobe (Media Cache) |
| **Never link** | a system daemon touches it | iCloud Drive, Photos library |

### The migration sequence

Every step is written to the journal **before** it happens:

1. **Checks** — does the volume support symlinks?
   (`volumeSupportsSymbolicLinksKey` — exFAT and FAT do not, and the app
   refuses before touching anything). Does it fit? Is the path allowed? Is
   there nesting?
2. **Copy** with `ditto`, into a staging area at the destination. `ditto` is
   Apple's and preserves metadata, xattrs, ACLs and resource forks — `rsync`
   was avoided because its implementation changed in macOS 14.
3. **Verification** — file and byte counts match, with 0.5% tolerance.
4. **Quarantine** — the original goes to `~/.savemymac-quarantine`. It is a
   rename on the same volume, instantaneous.
5. **Publication** — the staging area becomes the final target.
6. **Symlink** in the original's place.
7. **Validation** — reads through the link, checks the count, and
   writes/deletes a test file. That last one catches a volume mounted
   read-only.

**The original is never deleted.** It stays in quarantine until you release it
— and only at that moment does the space return to the disk. While it is there,
every migration can be undone with one click.

Any failure rolls everything back automatically, always returning the original
from quarantine (an instantaneous local rename) instead of bringing the
external copy back.

### Inventory of existing links

| Status | Meaning |
|---|---|
| **OK** | points to another volume, mounted, target exists |
| **Volume missing** | the destination disk is not mounted right now |
| **Broken** | the volume is mounted but the target no longer exists |
| **Same disk** | points elsewhere on the Mac's own disk — works, but saves nothing |

Plus **orphaned data**: folders in the offload area that no link points to. To
avoid false positives, a parent folder is only analyzed if most of what is in
it is already a link target — so an ordinary work disk is not accused
wholesale.

In each link's context menu: reveal source or target in Finder, and **copy a
ready-made `ln -s` command**.

### The bug this tab revealed

If `~/.gradle` is a link to `/Volumes/CachePart/mac-offload/gradle`,
`fileExists` walks through the link. Untreated, the Cleanup tab would do two
wrong things: count the external disk's space as reclaimable on the internal
one, and delete real data on the external SSD believing it was cleaning the
Mac.

`VolumeResolver` solves this by comparing each path's **volume identity**
(`volumeIdentifierKey`) with the volume the home folder lives on — and not with
`/`, because on modern macOS the home lives on the Data volume, tied to the
root by a *firmlink*, which is not a symlink and does not show up in path
resolution.

---

## 8. Menu bar, launch at login and alerts

### The item next to the clock

A `MenuBarExtra` with the `.window` style — a real panel, not a menu list,
because the content has bars and numbers. It shows free space on the boot disk,
memory pressure, CPU usage, temperature and what is in the Trash, plus the
health score. Below, shortcuts that jump straight to the tabs.

The label next to the icon is configurable (space, memory, CPU, temperature, or
icon only) and kept tiny on purpose: the menu bar is shared space. **The icon
switches to a warning triangle when space drops below the threshold**,
regardless of the chosen metric.

Clicking a shortcut does not touch the activation policy — if you hid the Dock
icon, the app stays `.accessory` and still shows the window. Bringing the icon
back would undo your preference behind your back.

### Launch at login

There is a trap here worth explaining. The correct API on macOS 13+ is
`SMAppService.mainApp.register()`: it appears in System Settings › General ›
Login Items and the user can disable it there. But it **requires a valid code
signature** — and this build is ad-hoc signed.

So the app tries the modern one and, if registration is refused, falls back to
a **LaunchAgent** in `~/Library/LaunchAgents`, which works without a signature.
The Settings screen **says which mechanism is active** instead of pretending
they are the same. On disable, both paths are undone: `unregister()` and
`launchctl bootout` + plist removal.

There is also a toggle to **hide the Dock icon**, applied instantly via
`setActivationPolicy` — no restart. With it on, the app becomes a menu-bar
utility.

For the app to survive the window closing (a requirement for any menu bar app),
a minimal `NSApplicationDelegate` returns `false` from
`applicationShouldTerminateAfterLastWindowClosed`.

### Low space alert

Notification via `UNUserNotificationCenter`, with an adjustable threshold from
3% to 30% (default 10%). Two rules that separate a useful alert from an
irritating one:

- **Hysteresis.** It fires when crossing the threshold downward and only rearms
  after space rises 3 percentage points above it. Without that, a disk
  oscillating around 10% would notify on every 2-second check.
- **Minimum interval.** Even staying below, at most one warning every 6 hours.

Notification permission is requested when you **turn the option on**, not at
startup — asking before the user wants it is the fastest way to get denied
forever. If it is denied, the menu bar warning keeps working and the Settings
screen says so.

---

## 9. Progress and achievements

Stored in `~/Library/Application Support/SaveMyMac/game.json`, with atomic
writes.

Level (1200 XP each), XP proportional to the space processed, a streak of
consecutive ISO weeks, 12 achievements and a monthly goal. **This is app state,
not system state** — XP, level and streak are SaveMyMac's invention. What is
real is the history: every record corresponds to bytes that actually left the
disk, with a date and a type.

The streak does not reset just because the current week has had no cleanup yet
— it only breaks when an entire week passes without one.

---

## 10. Safety guards

- Every scan is read-only.
- Default removal is the Trash; *Delete permanently* exists but is not the
  default.
- `CleanupRemover.rejectionReason` refuses: symlinks, content on another
  volume, anything outside your home folder, the home's top-level folders, and
  Keychains / Mail / AddressBook / CloudStorage / Mobile Documents / Group
  Containers / `com.apple.*` preferences.
- `AppUninstaller.rejectionReason` is more permissive (`/Applications` is a
  legitimate target) but blocks `/System`, `/usr`, `/bin`, `/sbin`,
  `/Library/Apple` and `/Library/Security`.
- `MigrationEngine.sourceProblem` blocks iCloud Drive, CloudStorage, Keychains,
  Mail, Messages, containers, preferences and the Photos library.
- Duplicates only leave after a byte-by-byte comparison.
- A migration is not cancellable mid-flight, on purpose.
- No operation asks for a password, except the optional temperature read.
- No network, no telemetry, nothing resident in the background.

---

## 11. Structure

```
SaveMyMac/
├── build.sh                        compiles and assembles the .app
├── Info.plist
├── Resources/Fonts/                Space Grotesk + JetBrains Mono (variable)
└── Sources/
    ├── SaveMyMacApp.swift          @main, sidebar, top strip, navigation
    ├── AppState.swift              observable state and orchestration
    ├── Theme/
    │   ├── Palette.swift           light and dark palettes
    │   ├── Typography.swift        Space Grotesk + JetBrains Mono
    │   └── Motion.swift            the design's eight animations
    ├── Support/
    │   ├── Preferences.swift       persisted configuration
    │   ├── LaunchAtLogin.swift     SMAppService with LaunchAgent fallback
    │   ├── SpaceAlert.swift        low-space alert with hysteresis
    │   ├── Formatting.swift        bytes, %, dates, durations
    │   ├── CancellationFlag.swift  thread-safe cancellation flag
    │   ├── VolumeResolver.swift    which volume a path really lives on
    │   └── Persistence.swift       atomic JSON in Application Support
    ├── Metrics/                    system, RAM, CPU, disk, battery, thermal
    │   ├── ProcessMonitor.swift    process list via ps, with a pinned locale
    │   ├── ProcessController.swift quitting with safety guards
    │   └── MemoryHistory.swift     pressure curve and growth detection
    ├── Health/HealthScore.swift    explainable 0–100 score
    ├── Gamification/GameStore.swift level, XP, streak, achievements, history
    ├── Cleanup/                    models, scanner and guarded remover
    ├── Apps/                       inventory, cache and clean uninstall
    ├── Files/FileScanner.swift     large files + treemap + duplicates + comparator
    ├── Offload/
    │   ├── OffloadModels.swift     link, status, orphan, per-volume group
    │   ├── OffloadScanner.swift    inventory of existing links
    │   ├── MigrationModels.swift   phases, journal, candidates
    │   ├── MigrationEngine.swift   copy, verify, quarantine, link, validate
    │   └── CandidateScanner.swift  candidate catalog with verdicts
    └── Views/                      the six screens + components + celebration
```

## 12. Shortcuts

| Shortcut | Action |
|---|---|
| ⌘R | Analyze the Mac |
| ⇧⌘F | Scan files and duplicates |
| ⇧⌘A | Scan applications |
| ⌘L | Check offload links |
| ⌘U | Refresh metrics |
| ⇧⌘T | Switch theme |
| ⌘, | Settings |

## 13. Tuning the thresholds

| What | Where | Value |
|---|---|---|
| Old downloads | `CleanupScanner.oldDownloads` | 90 days |
| Abandoned `node_modules` | `CleanupScanner.staleNodeModules` | 90 days, > 20 MB |
| Unused app | `InstalledApp.isStale` | 90 days |
| Large file | `FileScanner.largeThreshold` | 500 MB |
| Duplicate minimum | `FileScanner.duplicateThreshold` | 2 MB |
| Offload candidate | `CandidateScanner` | 200 MB in the catalog, 5 GB in discoveries |
| XP per GB | `GameStore.xpReward` | 12, floor of 20 |
| Pressure curve window | `MemoryHistory.capacity` | 450 samples (15 min) |
| Suspicious growth | `GrowthTracker` | 250 MB, +50%, min. 2.5 min |
| Monthly goal | `GameState.monthlyGoalBytes` | 60 GB |
| Low-space threshold | Settings (or `lowSpaceThreshold`) | 10% free |
| Alert rearm | `SpaceAlert.rearmMargin` | +3 percentage points |
| Interval between alerts | `SpaceAlert.minimumInterval` | 6 hours |

To add a folder to the offload catalog, add a line to
`CandidateScanner.catalog` with its verdict. For a new cleanup category, an
item in `CleanupScanner.scan` and the corresponding function.
