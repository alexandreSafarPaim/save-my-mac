#!/bin/bash
# Ground truth for the Large Files scan: what is actually in the home folder,
# and which folders the app can and cannot read.
#
#   ./diagnostico-varredura.sh
#
# Written because I theorised three times about why the scan finds nothing —
# permission, then the error handler, then permission again — without ever
# measuring the home folder. This measures it.

OUT=/tmp/savemymac-varredura.txt
: > "$OUT"
say() { echo "$@" | tee -a "$OUT"; }

say "SaveMyMac — scan ground truth   $(date '+%Y-%m-%d %H:%M:%S')"
say ""

# ── 1. Is there anything over 500 MB at all? ─────────────────────────────────
# Terminal usually has its own Full Disk Access, so this sees what the app may
# not. If this comes back empty too, the app is right and the home folder simply
# has no large files.
say "═══ 1. Files over 500 MB in the home folder (Terminal's view)"
say ""
find "$HOME" -type f -size +500000k 2>/dev/null \
  | head -40 \
  | while read -r f; do
      printf "  %6s  %s\n" "$(du -h "$f" 2>/dev/null | cut -f1)" "${f/#$HOME/~}"
    done | tee -a "$OUT"

TOTAL=$(find "$HOME" -type f -size +500000k 2>/dev/null | wc -l | tr -d ' ')
say ""
say "  total over 500 MB: $TOTAL"

# How many of those are inside ~/Library, which the scanner excludes by design.
IN_LIBRARY=$(find "$HOME/Library" -type f -size +500000k 2>/dev/null | wc -l | tr -d ' ')
say "  of which inside ~/Library (excluded by the scanner): $IN_LIBRARY"
say "  visible to the scanner in principle: $((TOTAL - IN_LIBRARY))"

# ── 2. Files over 2 MB, which is what scannedFiles counts ────────────────────
say ""
say "═══ 2. Files over 2 MB (this is the number the app reports as 'walked')"
say ""
OVER2=$(find "$HOME" -type f -size +2000k 2>/dev/null | wc -l | tr -d ' ')
OVER2_NOLIB=$(find "$HOME" -type f -size +2000k -not -path "$HOME/Library/*" 2>/dev/null | wc -l | tr -d ' ')
say "  over 2 MB anywhere in home:        $OVER2"
say "  over 2 MB outside ~/Library:       $OVER2_NOLIB"
say ""
say "  The app reported 7. If the number above is much larger, the walk is being"
say "  blocked. If it is also small, the app is telling the truth."

# ── 3. Which top-level folders can be read, and by whom ──────────────────────
# TCC does not always surface as an error: macOS often returns an empty listing
# instead, which is why counting enumerator errors found nothing. Comparing what
# Terminal sees against what it can count is the reliable probe.
say ""
say "═══ 3. Top-level folders: entries visible to Terminal"
say ""
for dir in Desktop Documents Downloads Movies Music Pictures Library Developer; do
  path="$HOME/$dir"
  [ -d "$path" ] || continue
  count=$(ls -1 "$path" 2>/dev/null | wc -l | tr -d ' ')
  size=$(du -sh "$path" 2>/dev/null | cut -f1)
  printf "  %-12s %5s entries  %8s\n" "$dir" "$count" "${size:-?}" | tee -a "$OUT"
done

# ── 4. Does the app have Full Disk Access? ───────────────────────────────────
#
# The first version of this section printed "could not read the TCC database"
# whenever the query returned nothing — which is also what happens when the
# database reads perfectly and SaveMyMac simply has no entry in it. Those are
# opposite conclusions: one means "cannot tell", the other means "definitely not
# granted, and macOS never even asked". It reported the first while the truth was
# the second, and that ambiguity cost a full round trip.
#
# Same mistake as the app's own error counter, in a shell script.
say ""
say "═══ 4. Full Disk Access"
say ""
TCC_DB="$HOME/Library/Application Support/com.apple.TCC/TCC.db"

if ! command -v sqlite3 > /dev/null 2>&1; then
  say "  sqlite3 is not installed — cannot inspect the TCC database."
elif ! sqlite3 "$TCC_DB" "select count(*) from access;" > /dev/null 2>&1; then
  say "  Cannot read the TCC database, so THIS TERMINAL does not have Full Disk"
  say "  Access either. Sections 1-3 above may therefore also be underreporting."
  say "  Grant it: System Settings › Privacy & Security › Full Disk Access"
else
  ROWS=$(sqlite3 "$TCC_DB" \
    "select service || ' = ' || case auth_value when 2 then 'ALLOWED' when 0 then 'DENIED' else 'value ' || auth_value end from access where client like '%savemymac%';" \
    2>/dev/null)
  say "  This terminal HAS Full Disk Access, so the database is readable."
  if [ -n "$ROWS" ]; then
    say "  SaveMyMac's entries:"
    echo "$ROWS" | sed 's/^/    /' | tee -a "$OUT"
  else
    say "  SaveMyMac has NO entry at all in the TCC database."
    say ""
    say "  That is the finding, not a failure to read. No entry means macOS has"
    say "  never granted it anything and never asked you — it just returns empty"
    say "  folders. Grant it by hand: System Settings › Privacy & Security ›"
    say "  Full Disk Access › + › /Applications/SaveMyMac.app"
  fi
fi

# ── 5. Symlinks pointing off the Mac ────────────────────────────────────────
# This user offloads heavy folders to an external SSD, so content that looks
# missing from home may simply live elsewhere — and the scanner skips symlinks
# on purpose.
say ""
say "═══ 5. Symlinks in home pointing to another volume"
say ""
find "$HOME" -maxdepth 3 -type l 2>/dev/null | while read -r link; do
  target=$(readlink "$link")
  case "$target" in
    /Volumes/*) printf "  %s\n      → %s\n" "${link/#$HOME/~}" "$target" | tee -a "$OUT" ;;
  esac
done
grep -c '→' "$OUT" > /dev/null 2>&1 || say "  (none found at depth 3)"

# ── 6. Are there real duplicates at all? ─────────────────────────────────────
# The duplicate scan comes from the same walk as the large-file list, so the
# ~/Library exclusion blinded both identically. This is the ground truth: group
# files over 2 MB by exact byte size, keep the groups with more than one member,
# then confirm with a real hash. Same two-step the app uses.
say ""
say "═══ 6. Duplicate candidates (files over 2 MB sharing an exact size)"
say ""
find "$HOME" -type f -size +2000k 2>/dev/null -print0 \
  | xargs -0 stat -f '%z %N' 2>/dev/null \
  | sort -n \
  | awk '{ size=$1; $1=""; paths[size] = paths[size] $0 "\n"; count[size]++ }
         END { for (s in count) if (count[s] > 1) printf "%d bytes × %d files\n%s", s, count[s], paths[s] }' \
  | head -60 | tee -a "$OUT"

GROUPS=$(find "$HOME" -type f -size +2000k 2>/dev/null -print0 \
  | xargs -0 stat -f '%z' 2>/dev/null | sort -n | uniq -d | wc -l | tr -d ' ')
say ""
say "  size groups with more than one file: $GROUPS"
say ""
say "  Sharing a size is not being a duplicate — the app then compares content,"
say "  and only deletes after a full byte-by-byte check. If the number above is 0,"
say "  there is genuinely nothing to find and the empty screen is correct."

# ── 7. What the app itself measured ─────────────────────────────────────────
#
# Everything above is Terminal's view. This is the app's, written to the trace by
# `AccessProbe` at the start of every scan. Comparing the two side by side is the
# only way to tell "this Mac has nothing" from "this app cannot see it": if
# section 3 shows Downloads with 11 entries and the app reports 0, the answer is
# permission, not tidiness.
say ""
say "═══ 7. What SaveMyMac itself could read (from its trace)"
say ""
TRACE="$HOME/Library/Logs/SaveMyMac-trace.log"
if [ ! -f "$TRACE" ]; then
  say "  No trace file yet. Run the app and press Scan files, then run this again."
elif ! grep -q "access probe" "$TRACE"; then
  say "  The trace has no access probe. Either the app predates it or no scan has"
  say "  run since. Open SaveMyMac › Large files › Scan files, then run this again."
else
  # Keeps only the LAST probe block: the trace accumulates across runs, and an
  # old block from before permission was granted would be read as current.
  # A block starts at "access probe" and continues while lines are indented
  # continuations rather than new timestamped trace entries.
  awk '
    /access probe/ { count = 0; delete block; grabbing = 1; block[count++] = $0; next }
    # Stop BEFORE recording, not after: the first version appended the line that
    # ended the block, so the report always carried a stray "tick" at the bottom.
    grabbing && /^[0-9. ]*\[[A-Z]+\]/ { grabbing = 0; next }
    grabbing { block[count++] = $0 }
    END { for (i = 0; i < count; i++) print block[i] }
  ' "$TRACE" \
    | sed -E 's/^[0-9. ]*\[[A-Z]+\] //' | sed 's/^/  /' | tee -a "$OUT"
fi

say ""
say "Done: $OUT"
