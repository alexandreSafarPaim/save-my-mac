<!--
One concern per PR. If this fixes a bug and also renames things, it's two PRs.
-->

## What this changes

<!-- And why. Link the issue if there is one: Fixes #123 -->

## How you tested it

<!--
"Builds" is not testing, for a tool that deletes files.
Say what you actually exercised and what you observed.
-->

## Checklist

- [ ] Builds clean: `cd SaveMyMac && ./build.sh`
- [ ] Ran the app and used the screen I changed
- [ ] Checked `~/Library/Logs/SaveMyMac-trace.log` for an update loop
      (a counter climbing hundreds of times per second means the graph isn't converging)
- [ ] Screenshots below, if the UI changed — both themes if colors moved

### If this touches code that deletes, moves, or overwrites files

<!--
That means Cleanup/, Apps/AppUninstaller, Offload/MigrationEngine, Support/VolumeResolver.
Delete this whole section if it doesn't apply.
-->

- [ ] Symlinks are still refused, not followed
- [ ] Paths outside the boot volume are still excluded from reclaimable space
- [ ] Deletion still goes to the Trash where the API allows it
- [ ] Byte-by-byte comparison still runs before removing a duplicate
- [ ] Nothing became deletable without the user checking a box
- [ ] I tested with a real file I would have been upset to lose, and I didn't lose it

### If this adds UI text

- [ ] Added both English and Portuguese to the localization table
- [ ] No string literals left inline in the view

## Screenshots

<!-- Drag images here. -->
