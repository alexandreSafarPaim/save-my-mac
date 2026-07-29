#!/usr/bin/env python3
"""Find UI string literals that never went through `L()`.

    python3 tools/check-untranslated-ui.py

Exits non-zero if it finds one, so CI can use it directly.

── Why this exists ────────────────────────────────────────────────────────────

The localization migration was declared finished twice, and both times it
wasn't. The reason was the detector, not the work: it looked for **accented
characters** to decide whether a string was Portuguese. That silently missed
every Portuguese string without an accent — `Text("Conquistas")`,
`Text("Duplicados")`, `"Mostrar no Finder"` repeated across four screens,
`"O SaveMyMac vai abrir junto com o Mac."` The sweep reported "clean" and the
real answer was "99 remaining".

This check asks a different question, and it's the right one: **is this literal
in a UI position without having gone through the table?** It doesn't care what
language the text is in — which means it also catches an English string someone
hardcodes in a future PR, something a language-based detector can never do.

A checker that can be fooled by the absence of a cedilla is worse than no
checker, because it grants confidence it hasn't earned.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"

# Files exempt as a whole.
#   Strings.swift      — is the table
#   Localization.swift — language names are deliberately in their own language
#   Trace.swift        — developer diagnostics, deliberately English only
EXEMPT_FILES = {"Strings.swift", "Localization.swift", "Trace.swift"}

# Positions where a bare literal means user-visible text.
UI_POSITION = re.compile(
    r"(?:Text|Button|GhostButton|PrimaryButton|MicroLabel|Label|StatRow"
    r"|action|actionRow|EmptyStateView|ScreenHeader)\s*\("
    r"|(?:title|label|eyebrow|subtitle|hint|message|caption|key|name|reason"
    r"|text|value|placeholder)\s*:"
)

# Literals that are user-visible but must NOT be translated, each with the
# reason. This list is short on purpose: every entry is a small hole in the
# check, so it needs to justify itself.
ALLOWED = {
    # Proper nouns and product names — translating them makes them wrong.
    "SaveMyMac", "Macintosh HD", "iCloud Drive", "Android SDK",
    "Xcode — iOS DeviceSupport", "Xcode — DerivedData",
    "Cache", "Logs", "Container", "Cookies", "Scripts", "Offload",
    # A path through another app's English-only interface. Translating half of
    # it would send the user looking for a menu that doesn't exist.
    "Docker Desktop → Settings → Resources → Disk image location.",
    # Units and symbols, identical in every language we ship.
    "°C", "XP", "Swap", "CPU / SoC", "Score 95+",
}

# Literals that are only interpolation plus a universal unit or identifier.
# `"pid \(pid)"`, `"\($0) rpm"`, `"+\(xp) XP"` — nothing to translate.
UNIT_ONLY = re.compile(r"^[+\-\s]*(?:\\\([^)]*\)|pid|rpm|XP|%|/|·|—|\s)+$")


def main() -> int:
    findings = []

    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name in EXEMPT_FILES:
            continue

        for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
            if re.match(r"\s*(//|///)", line):
                continue
            # Trace and NSLog are developer diagnostics, not UI.
            if "Trace." in line or "NSLog" in line:
                continue
            if not UI_POSITION.search(line):
                continue

            # Blank out anything already inside L(...) / Lp(...) so only bare
            # literals remain.
            bare = re.sub(
                r"\bLp?\(\s*\"(?:[^\"\\]|\\.)*\"(?:\s*,\s*\"(?:[^\"\\]|\\.)*\")?",
                "L(",
                line,
            )

            for match in re.finditer(r'"((?:[^"\\]|\\.){2,})"', bare):
                text = match.group(1)
                if text in ALLOWED:
                    continue
                if UNIT_ONLY.match(text):
                    continue
                # SF Symbol names, UserDefaults keys, dispatch queue labels.
                if re.match(r"^[a-z0-9._-]+$", text):
                    continue
                if text.startswith(("/", "~", "%")):
                    continue
                # Nothing but interpolation and punctuation: no words to translate.
                without_values = re.sub(r"\\\([^)]*\)", "", text)
                if not re.search(r"[A-Za-zÀ-ú]{2}", without_values):
                    continue
                findings.append((path.relative_to(ROOT), number, text))

    if not findings:
        print("no untranslated UI literals")
        return 0

    print(f"{len(findings)} UI literal(s) not going through L():\n")
    for path, number, text in findings:
        print(f"  {path}:{number}")
        print(f"      {text[:100]}")
    print(
        "\nWrap each in L(\"…\") and add the translations to Strings.swift,\n"
        "or add it to ALLOWED in this file with the reason it must stay literal."
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
