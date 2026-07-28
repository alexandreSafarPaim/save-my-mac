<img src="SaveMyMac/Resources/logo-1024.png" width="120" align="right" alt="SaveMyMac">

# SaveMyMac

A native SwiftUI app that shows what your Mac is actually doing, lists what can
be removed **with a checkbox on every single item**, and offloads heavy folders
to an external disk leaving a symlink behind.

[![Build](https://github.com/alexandreSafarPaim/save-my-mac/actions/workflows/build.yml/badge.svg)](https://github.com/alexandreSafarPaim/save-my-mac/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)

🇧🇷 [Leia em português](README.pt-BR.md)

---

## The one thing worth knowing first

**This app never deletes anything on its own.**

That is a design constraint, not a default setting — there is no "clean
everything" button to find. Every scan produces a list, every item has a
checkbox, nothing is unchecked-by-default into oblivion. Cleanup sends files to
the Trash where possible, so a bad decision is recoverable.

If you are looking for one-click automated cleaning, this is the wrong tool, on
purpose. Disk cleaners that decide for you are how people lose work.

## What it does

| Screen | What it gives you |
|---|---|
| **Dashboard** | Disk, memory pressure, CPU, temperature, uptime, top processes by CPU and RAM, and a health score that explains how it was calculated |
| **Cleanup** | Caches, logs, and leftovers grouped by category — you pick what goes |
| **Apps** | Every installed app with its cache size and last-used date; clear the cache or uninstall completely, support files included |
| **Large files** | Biggest files on the boot volume, filterable |
| **Duplicates** | Grouped by content, compared **byte by byte** before anything is removed |
| **Offload** | Move a heavy folder to another volume and leave a symlink, so apps keep finding it while the space is freed |

Plus a menu bar item with live metrics, a low-space alert, launch at login, and
light/dark themes.

### Temperature without a password

Sensor readings come from `IOHIDEventSystemClient`, a private Apple API resolved
at runtime with `dlopen`/`dlsym`. If Apple changes or removes it, the app shows
the coarse thermal state instead of crashing. There is also an optional
`powermetrics` path that asks for admin rights, for CPU die temperature.

## Requirements

- macOS 13 (Ventura) or newer
- Apple Command Line Tools — **Xcode is not required**

## Build

There is no `.xcodeproj`. The app is compiled by invoking `swiftc` directly,
which keeps the whole build readable in one shell script.

```bash
xcode-select --install        # only if swiftc is missing
git clone https://github.com/alexandreSafarPaim/save-my-mac.git
cd save-my-mac/SaveMyMac
chmod +x build.sh
./build.sh --run
```

| Command | Result |
|---|---|
| `./build.sh` | compiles for your machine's architecture |
| `./build.sh --universal` | universal binary (Apple Silicon + Intel) |
| `./build.sh --run` | compiles and launches |
| `./build.sh --install` | compiles and installs to `/Applications` |
| `./build.sh --dmg` | builds a distributable disk image |

## Installing

### Gatekeeper

Builds are **ad-hoc signed** — there is no paid Apple Developer certificate
behind them. macOS will refuse the first launch. Right-click the app and choose
**Open**, then confirm. You only do this once.

This also means `SMAppService` (the modern Login Items API) may refuse to
register the app. The app detects that and falls back to a user LaunchAgent,
and Settings tells you which mechanism is actually active.

### Full Disk Access

Without it, the scan silently skips protected folders and under-reports what can
be reclaimed. Grant it in:

**System Settings → Privacy & Security → Full Disk Access**

## Contributing

Pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first —
especially the section on code that deletes files, which is reviewed to a higher
standard than the rest for reasons that should be obvious.

Two things to know upfront:

- **Source comments are being translated from Portuguese to English.** The
  identifiers were always English; the prose was not. See
  [issue tracker](https://github.com/alexandreSafarPaim/save-my-mac/issues) for
  progress.
- **The UI is bilingual** (English and Portuguese), switchable in Settings and
  defaulting to your Mac's language.

## Architecture

The deep technical document lives at
[SaveMyMac/README.md](SaveMyMac/README.md) — module layout, how each scanner
decides what is safe, the offload journal and rollback design, and a list of
bugs that were expensive to find and are worth not reintroducing.

## Security

The app reads your whole disk and can delete files. If you find a way to make it
delete something it should not, please report it privately — see
[SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Alexandre Safar Paim
