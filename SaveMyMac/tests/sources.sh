#!/bin/bash
# The single definition of which sources the behavioural tests compile.
#
# This list existed twice — in tools/e2e.sh and in .github/workflows/build.yml —
# and the copies drifted within a day: one started including AppState.swift, the
# other kept excluding it, so CI quietly tested less than the local run while
# reporting the same green. A test-scope definition that can disagree with
# itself is the "measured something near the thing" failure this project keeps
# relearning; now there is one definition and two consumers.
#
# Everything except the UI layer: views can't be exercised from a CLI binary,
# and SaveMyMacApp.swift carries @main, which the test target provides itself.
cd "$(dirname "$0")/.." || exit 1
find Sources -name '*.swift' \
  ! -path 'Sources/Views/*' \
  ! -name 'SaveMyMacApp.swift' | sort
