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
say ""
say "═══ 4. Full Disk Access"
say ""
if sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
     "select client, auth_value from access where service='kTCCServiceSystemPolicyAllFiles' and client like '%savemymac%';" \
     2>/dev/null | grep -q .; then
  sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
    "select client, case auth_value when 2 then 'ALLOWED' when 0 then 'DENIED' else auth_value end from access where service='kTCCServiceSystemPolicyAllFiles' and client like '%savemymac%';" \
    2>/dev/null | sed 's/^/  /' | tee -a "$OUT"
else
  say "  Could not read the TCC database (normal — it is protected)."
  say "  Check by hand: System Settings › Privacy & Security › Full Disk Access"
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

say ""
say "Done: $OUT"
