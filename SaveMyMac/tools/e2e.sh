#!/bin/bash
# End-to-end verification for SaveMyMac.
#
#   ./tools/e2e.sh            full run
#   ./tools/e2e.sh --quick    skip the universal build and the runtime phase
#
# Four phases, cheapest first, each one gating the next:
#
#   1. static      — translation tables, hardcoded UI strings, known regressions
#   2. build       — compiles, bundles, signs, and verifies the artifact
#   3. behaviour   — runs the safety-critical functions against real files
#   4. runtime     — launches the app and reads the trace for stalls and loops
#
# Phase 3 is the one that was missing for most of this project's life. Everything
# before it is a regex over source text: it can tell you a guard is still written,
# never that it still refuses.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; OFF=$'\033[0m'
FAILURES=0

phase() { printf "\n%s══ %s %s\n" "$BOLD" "$1" "$OFF"; }
ok()    { printf "  %s✓%s %s\n" "$GREEN" "$OFF" "$1"; }
bad()   { printf "  %s✗%s %s\n" "$RED" "$OFF" "$1"; FAILURES=$((FAILURES + 1)); }
warn()  { printf "  %s!%s %s\n" "$YELLOW" "$OFF" "$1"; }

# ═══════════════════════════════════════════════════════ 1. static

phase "1. Static checks"

if python3 tools/check-translations.py > /tmp/smm-i18n.txt 2>&1; then
  ok "translation tables ($(grep -c 'translated' /tmp/smm-i18n.txt) languages, no errors)"
else
  bad "translation tables"; sed 's/^/      /' /tmp/smm-i18n.txt
fi

if python3 tools/check-untranslated-ui.py > /tmp/smm-ui.txt 2>&1; then
  ok "no hardcoded UI strings"
else
  bad "hardcoded UI strings"; sed 's/^/      /' /tmp/smm-ui.txt
fi

# The two regressions that cost the most in this project and that no compiler
# catches. Anchored to declarations so they don't fire on the comments that
# explain them — an earlier version of this check failed against its own
# documentation.
if grep -qE '^[[:space:]]*@Published' Sources/Support/Preferences.swift 2>/dev/null; then
  bad "Preferences uses @Published (see CONTRIBUTING: publishing an unchanged value closed a 100%-CPU loop)"
else
  ok "Preferences has no @Published"
fi

if grep -rE '^[[:space:]]*(//|///)' --invert-match Sources/Views/*.swift 2>/dev/null | grep -q 'SMAppService'; then
  bad "SMAppService reached from Sources/Views (blocking XPC on the main thread)"
else
  ok "SMAppService not reached from the view layer"
fi

# Portuguese left in comments. Two hits are expected: the quoted language names
# in the comments explaining why language names aren't translated.
#
# The character class includes UPPERCASE accents, and the word list catches
# Portuguese that carries no accent at all. The first version had only lowercase
# accents and declared the codebase clean while 31 comment lines were still
# Portuguese — "MARK: - Varredura", "tamanho LÓGICO", "Duplicados". Same failure
# as the UI sweep that missed Text("Conquistas"): asking about diacritics when
# the question is about language.
PT=$(grep -rcE '^[[:space:]]*(//|///)([^"]*[çãõáéíóúâêôàÇÃÕÁÉÍÓÚÂÊÔÀ]|.*\b(Varredura|Duplicados|Entrada|Checagens|Limpeza|arquivos?|pastas?|tamanho|agrupa)\b)' \
     Sources/ --include=*.swift 2>/dev/null | awk -F: '{ s += $2 } END { print s+0 }')
if [ "$PT" -le 2 ]; then
  ok "comments in English ($PT expected quotation(s) of language names)"
else
  warn "$PT comment line(s) still in Portuguese"
fi

# ═══════════════════════════════════════════════════════ 2. build

phase "2. Build"

if [ "$QUICK" = "1" ]; then
  BUILD_ARGS=""
  warn "quick mode: native arch only"
else
  BUILD_ARGS="--universal"
fi

if ./build.sh $BUILD_ARGS > /tmp/smm-build.txt 2>&1; then
  ok "compiles"
  # Warnings are worth surfacing without failing: the Swift 6 concurrency ones
  # were how the NSLock-across-suspension bug was found.
  WARNINGS=$(grep -c 'warning:' /tmp/smm-build.txt || true)
  [ "${WARNINGS:-0}" -gt 0 ] && warn "$WARNINGS compiler warning(s) — see /tmp/smm-build.txt"
else
  bad "compilation failed"
  grep -E 'error:' /tmp/smm-build.txt | head -20 | sed 's/^/      /'
  printf "\n%sBuild failed — stopping here.%s\n" "$RED" "$OFF"
  exit 1
fi

APP="build/SaveMyMac.app"
BIN="$APP/Contents/MacOS/SaveMyMac"

[ -x "$BIN" ] && ok "executable present" || bad "executable missing"
[ -f "$APP/Contents/Info.plist" ] && ok "Info.plist present" || bad "Info.plist missing"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] && ok "icon bundled" || bad "icon missing"

FONTS=$(ls "$APP/Contents/Resources/Fonts"/*.ttf 2>/dev/null | wc -l | tr -d ' ')
[ "$FONTS" = "2" ] && ok "2 fonts bundled" || bad "expected 2 fonts, found $FONTS"

ARCHS=$(lipo -archs "$BIN" 2>/dev/null)
if [ "$QUICK" = "0" ]; then
  echo "$ARCHS" | grep -q arm64 && echo "$ARCHS" | grep -q x86_64 \
    && ok "universal ($ARCHS)" || bad "not universal ($ARCHS)"
else
  ok "architecture: $ARCHS"
fi

codesign --verify --deep --strict "$APP" 2>/dev/null \
  && ok "signature valid" || bad "signature invalid"

# ═══════════════════════════════════════════════════════ 3. behaviour

phase "3. Behavioural tests"

# Compiled from the same sources minus the UI layer, so the tests link the real
# implementations rather than copies. `AppState` used to be excluded too, because
# it depended on `AppSection`, which lived in the excluded `SaveMyMacApp.swift`.
# The enum moved to Support/ and the app's central object is now in the target.
TEST_SOURCES=$(find Sources -name '*.swift' \
  ! -path 'Sources/Views/*' \
  ! -name 'SaveMyMacApp.swift' | sort)

mkdir -p build
if swiftc -O -swift-version 5 \
     -target "$(uname -m)-apple-macos13.0" \
     -framework AppKit -framework ServiceManagement -framework IOKit \
     -o build/e2e-tests \
     $TEST_SOURCES tests/E2EMain.swift > /tmp/smm-tests-build.txt 2>&1; then
  ok "test binary compiles"
  if ./build/e2e-tests > /tmp/smm-tests.txt 2>&1; then
    sed 's/^/      /' /tmp/smm-tests.txt
    ok "$(tail -2 /tmp/smm-tests.txt | head -1)"
  else
    bad "behavioural tests failed"
    sed 's/^/      /' /tmp/smm-tests.txt
  fi
else
  bad "test binary did not compile"
  grep -E 'error:' /tmp/smm-tests-build.txt | head -20 | sed 's/^/      /'
fi

# ═══════════════════════════════════════════════════════ 4. runtime

if [ "$QUICK" = "1" ]; then
  phase "4. Runtime — skipped (--quick)"
else
  phase "4. Runtime"

  TRACE="$HOME/Library/Logs/SaveMyMac-trace.log"
  killall SaveMyMac 2>/dev/null; sleep 1

  open "$APP" || bad "could not launch the app"
  echo "      running for 15 s, then sampling CPU for 5 s…"
  sleep 15

  PID=$(pgrep -x SaveMyMac | head -1)
  if [ -z "$PID" ]; then
    bad "the app is not running after 15 s"
  else
    ok "still running (pid $PID)"

    # CPU measured as a delta over a window, not with `ps -o %cpu`.
    #
    # The first version of this check used `%cpu` and reported 42% on a perfectly
    # healthy app. On macOS that column is an average over the process lifetime,
    # so the cost of launching — creating the window, registering the fonts,
    # rendering the first frame — was being amortised over only 15 seconds and
    # counted as if it were steady-state load.
    #
    # It failed in the direction that matters least but hurts most: a false alarm.
    # A check that cries wolf is a check people learn to ignore, and this one sits
    # next to the counters that catch a real 100%-CPU loop.
    #
    # Cumulative CPU seconds sampled twice, five seconds apart, is what
    # steady-state actually means.
    cpu_seconds() {
      ps -o cputime= -p "$1" 2>/dev/null | tr -d ' ' | python3 -c '
import sys
raw = sys.stdin.read().strip()
if not raw:
    print(-1); raise SystemExit
parts = raw.split(":")
seconds = 0.0
for part in parts:
    seconds = seconds * 60 + float(part)
print(f"{seconds:.2f}")
'
    }

    BEFORE=$(cpu_seconds "$PID")
    sleep 5
    AFTER=$(cpu_seconds "$PID")

    if [ "$BEFORE" = "-1" ] || [ "$AFTER" = "-1" ]; then
      warn "could not read CPU time"
    else
      CPU=$(python3 -c "print(f'{($AFTER - $BEFORE) / 5 * 100:.1f}')")
      if python3 -c "import sys; sys.exit(0 if $CPU < 15 else 1)"; then
        ok "CPU steady-state: ${CPU}% (over a 5 s window)"
      else
        bad "CPU steady-state: ${CPU}% — suspected update loop"
      fi
    fi

    if grep -q "MAIN THREAD STALLED" "$TRACE" 2>/dev/null; then
      bad "the trace recorded a main-thread stall"
      grep "MAIN THREAD STALLED" "$TRACE" | head -3 | sed 's/^/      /'
    else
      ok "no main-thread stall"
    fi

    # These counters only print every 200–500 calls. Their presence at all means
    # something is being rebuilt hundreds of times.
    for counter in "Settings scene rebuilt" "menu bar label"; do
      if grep -q "$counter" "$TRACE" 2>/dev/null; then
        bad "counter fired: $counter — $(grep -c "$counter" "$TRACE") report(s)"
      else
        ok "counter silent: $counter"
      fi
    done

    # The HID client must be created exactly once per sensor type. Creating one
    # per read overloaded hidd and froze the whole machine.
    CREATED=$(grep -c "CREATING client" "$TRACE" 2>/dev/null || echo 0)
    if [ "$CREATED" -le 2 ]; then
      ok "HID clients created: $CREATED (expected at most 2)"
    else
      bad "HID clients created: $CREATED — the cache is not holding"
    fi

    # Ticks should be 2 s apart, and heavy work every third tick.
    TICKS=$(grep -c "^ *[0-9.]* \[MAIN\] tick" "$TRACE" 2>/dev/null || echo 0)
    if [ "$TICKS" -ge 5 ] && [ "$TICKS" -le 12 ]; then
      ok "$TICKS metric ticks in 15 s (expected ~7)"
    else
      warn "$TICKS metric ticks in 15 s — expected around 7"
    fi

    if grep -q "icon visible in the menu bar" "$TRACE" 2>/dev/null; then
      ok "menu bar icon visible"
    elif grep -q "ICON HIDDEN" "$TRACE" 2>/dev/null; then
      warn "menu bar icon hidden by preference"
    else
      warn "no menu bar verdict in the trace"
    fi

    RSS=$(ps -o rss= -p "$PID" | tr -d ' ')
    ok "resident memory: $((RSS / 1024)) MB"

    killall SaveMyMac 2>/dev/null
    sleep 1
    pgrep -x SaveMyMac > /dev/null \
      && bad "did not quit on request" || ok "quits cleanly"
  fi
fi

# ═══════════════════════════════════════════════════════ verdict

printf "\n%s────────────────────────────────────────%s\n" "$BOLD" "$OFF"
if [ "$FAILURES" -eq 0 ]; then
  printf "%sAll checks passed.%s\n" "$GREEN" "$OFF"
  exit 0
fi
printf "%s%d check(s) failed.%s\n" "$RED" "$FAILURES" "$OFF"
exit 1
