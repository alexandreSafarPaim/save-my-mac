#!/bin/bash
# Collects everything a SaveMyMac hang report needs, into a single file.
#
# Usage:
#   1. Open SaveMyMac and wait for it to hang.
#   2. Run:  ./tools/collect-hang-report.sh
#   3. Attach the contents of /tmp/savemymac-diagnostics.txt to the issue.
#
# Asks for the password once, for the spindump. `sample` has already failed to
# read this process's threads once; spindump uses a different mechanism (a
# kernel stackshot) and tends to work where sample gives up.

OUT=/tmp/savemymac-diagnostics.txt
: > "$OUT"

say() { echo "$@" | tee -a "$OUT"; }
sec() { echo "" >> "$OUT"; echo "===== $* =====" >> "$OUT"; }

say "SaveMyMac — hang report  $(date '+%Y-%m-%d %H:%M:%S')"

PID=$(pgrep -x SaveMyMac | head -1)
if [ -z "$PID" ]; then
  say "!! SaveMyMac is not running. Open the app, wait for the hang, run again."
else
  say "pid: $PID"
fi

# ---------------------------------------------------------------- 1. binary
# We have lost time debugging a stale copy before. This settles it first.
sec "WHICH BINARY IS RUNNING"
for APP in /Applications/SaveMyMac.app "$HOME/Applications/SaveMyMac.app"; do
  BIN="$APP/Contents/MacOS/SaveMyMac"
  [ -f "$BIN" ] && {
    echo "$BIN" >> "$OUT"
    stat -f '   modified: %Sm   size: %z bytes' -t '%Y-%m-%d %H:%M:%S' "$BIN" >> "$OUT"
    lipo -archs "$BIN" 2>/dev/null | sed 's/^/   architectures: /' >> "$OUT"
  }
done
[ -n "$PID" ] && ps -o comm= -p "$PID" | sed 's/^/running: /' >> "$OUT"

# Is the installed binary older than the source tree? Then the build never got
# there, and everything below describes a version that no longer exists.
SRC=$(cd "$(dirname "$0")/.." 2>/dev/null && \
      find Sources -name '*.swift' -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1)
BIN=/Applications/SaveMyMac.app/Contents/MacOS/SaveMyMac
if [ -n "$SRC" ] && [ -f "$BIN" ]; then
  BINT=$(stat -f '%m' "$BIN")
  if [ "$SRC" -gt "$BINT" ]; then
    say ""
    say "########################################################################"
    say "#  WARNING: the installed app is OLDER than the source tree.           #"
    say "#  The last build never reached /Applications.                         #"
    say "#  Run  ./build.sh --install --run  and LET IT FINISH before repeating #"
    say "#  this report. Everything below describes an obsolete version.        #"
    say "########################################################################"
    say ""
  fi
fi

# ------------------------------------------------------------------ 2. trace
# The most important part: the last line says where the app stopped.
sec "EXECUTION TRACE (~/Library/Logs/SaveMyMac-trace.log)"
TRACE="$HOME/Library/Logs/SaveMyMac-trace.log"
if [ -f "$TRACE" ]; then
  echo "--- first 40 lines ---" >> "$OUT"
  head -40 "$TRACE" >> "$OUT"
  echo "--- last 60 lines (THE ANSWER IS HERE) ---" >> "$OUT"
  tail -60 "$TRACE" >> "$OUT"
  echo "--- total: $(wc -l < "$TRACE") lines ---" >> "$OUT"
else
  echo "!! Does not exist. The running app is a build WITHOUT instrumentation —" >> "$OUT"
  echo "   meaning the build never reached the app you opened." >> "$OUT"
fi

# ------------------------------------------------------------- 3. resources
# Threads and descriptors growing without bound point to task pile-up.
if [ -n "$PID" ]; then
  sec "PROCESS RESOURCES"
  echo "threads: $(ps -M "$PID" 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')" >> "$OUT"
  echo "open descriptors: $(lsof -p "$PID" 2>/dev/null | wc -l | tr -d ' ')" >> "$OUT"
  ps -o pid,%cpu,%mem,rss,state,wq,etime -p "$PID" >> "$OUT" 2>&1
  echo "" >> "$OUT"
  echo "-- leftover subprocesses (ps/zombies) --" >> "$OUT"
  ps -axo pid,ppid,state,comm | awk -v p="$PID" '$2==p' >> "$OUT"
fi

# ------------------------------------------------------------- 4. spindump
sec "SPINDUMP (real stacks)"
if [ -n "$PID" ]; then
  echo "Asking for the password for spindump…"
  sudo spindump "$PID" 5 -file /tmp/savemymac-spindump.txt >/dev/null 2>&1
  if [ -f /tmp/savemymac-spindump.txt ]; then
    # Stacks only, without the giant binary catalog at the end.
    sed -n '/^Process:/,/^Binary Images:/p' /tmp/savemymac-spindump.txt \
      | head -250 >> "$OUT"
  else
    echo "!! spindump produced no file." >> "$OUT"
  fi
fi

# ------------------------------------------------------------ 5. hidd health
# If hidd is suffering, the freeze is system-wide, not the app's.
sec "hidd (keyboard/mouse daemon)"
ps -axo pid,%cpu,%mem,etime,comm | grep -E '[h]idd' >> "$OUT" 2>&1

say ""
say "Done: $OUT"
say "Open with:  open -e $OUT"
