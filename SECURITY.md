# Security Policy

## Why this file exists

SaveMyMac asks for Full Disk Access and can delete files. That combination
deserves a real disclosure path, not a form letter.

## Reporting a vulnerability

**Please do not open a public issue for anything in the categories below.**

Use GitHub's private reporting — **Security → Report a vulnerability** on this
repository — or email **alexandre.paim@pentagrama.com.br**.

Report privately if you find a way to make the app:

- delete, move, or overwrite a file the user did not select
- act outside the boot volume when it believes it is inside it (symlink,
  firmlink, hardlink, or mount-point confusion)
- follow a symlink into a location it should have refused
- delete the *original* of a duplicate pair instead of the copy
- leave an offload migration in a state where data exists in neither the source
  nor the destination
- escalate privileges, or run a subprocess with input it did not construct itself
- report reclaimable space on one volume while deleting on another

Anything else — crashes, hangs, wrong numbers, UI problems — is a normal issue
and public discussion is fine and useful.

## What to expect

There is no bounty and no SLA; this is a personal project maintained in spare
time. What you will get is an acknowledgement and an honest assessment, and if
the report is valid, credit in the release notes unless you'd rather not have it.

## Supported versions

The `main` branch. There are no maintained release branches.

## Design notes relevant to security review

If you are auditing this, these are the load-bearing invariants. Each is enforced
in code, and each exists because it was once violated:

**Nothing is deleted without an explicit checkbox.** There is no automatic
cleaning path. If you find one, that is a bug in the sense this document cares
about.

**Deletion goes to the Trash** wherever the API allows, so a mistake is
recoverable. `TrashManager` empties only `~/.Trash` and refuses if that path is a
symlink — it deliberately does not touch `.Trashes` on external volumes.

**`VolumeResolver` gates reclaimable-space accounting.** It returns false for
symlinks and for any path not on the home volume. Before it existed, the scanner
counted space on an external disk as reclaimable from the boot disk, which meant
it would have deleted on the wrong volume.

**Duplicates are compared byte by byte** by `FileComparator.identical` before
removal. Size and grouping are used to *find* candidates, never to *confirm*
them.

**Offload migrations are journaled** with a quarantine step and rollback, so an
interrupted migration can be recovered rather than leaving a symlink pointing at
nothing.

**Subprocess arguments are never built from user input.** The app runs `/bin/ps`,
`/bin/launchctl`, and optionally `/usr/bin/powermetrics`, all with fixed
argument lists.

**The private temperature API degrades instead of failing.**
`IOHIDEventSystemClient` symbols are resolved with `dlsym` and every one is
checked; if any is missing the app shows the coarse thermal state.
