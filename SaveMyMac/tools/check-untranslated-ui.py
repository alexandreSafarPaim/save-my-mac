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
    "°C", "XP", "Swap", "CPU / SoC", "Score 95+", "OK",
}

# Literals that are only interpolation plus a universal unit or identifier.
# `"pid \(pid)"`, `"\($0) rpm"`, `"+\(xp) XP"` — nothing to translate.
UNIT_ONLY = re.compile(r"^[+\-\s]*(?:\\\([^)]*\)|pid|rpm|XP|%|/|·|—|\s)+$")

# ── The second hole this check had ──────────────────────────────────────────────
#
# The rules above are all *line-local*: a literal counts as UI only if a UI call
# or a labelled parameter sits on the same line. That misses the case where the
# UI position is the **enclosing declaration**:
#
#     var label: String {
#         switch self {
#         case .image: return "Imagens"      ← no UI token on this line
#
# Nine Portuguese strings survived in `FileScanner.swift` this way — `Imagens`,
# `Compactados`, `Outros`, `hoje`, `dias`, `meses`, `anos` — displayed on the
# treemap and in every file row. The check ran clean over that file for weeks.
#
# Same root cause as the accent detector it replaced: the question being asked
# was *near* the question that mattered. So this tracks the declaration a line
# sits inside and treats `return "…"` from anything named like a label as UI.
DECLARATION = re.compile(r"^\s*(?:@\w+\s+)*(?:public\s+|private\s+|static\s+)*"
                         r"(?:var|func|let)\s+(\w+)")
UI_DECLARATION = re.compile(
    r"^(label|title|subtitle|eyebrow|name|text|caption|hint|message|summary"
    r"|description|reason|placeholder|displayName|ageLabel|shortLabel)$"
    r"|Label$|Title$|Text$|Description$|Message$|Name$",
)
RETURNS_LITERAL = re.compile(r'\breturn\s+"')

# ── The third hole ──────────────────────────────────────────────────────────────
#
# `filesStatus = "Preparando…"` is neither a call argument nor a `return`, so both
# rules above walk past it. Three status strings shown in the scan banner survived
# that way. An assignment to a property whose name is a UI role is a UI position.
#
# Deliberately does NOT require the quote right after `=`. Requiring it would
# still miss `filesStatus = flag.isCancelled ? "Cancelada" : L("Done")`, where a
# literal hides in a ternary — the same near-miss shape as every other hole in
# this file's history. Matching the assignment and letting the literal scan below
# handle the rest costs nothing and closes the whole family.
ASSIGNS_LITERAL = re.compile(
    r"\b(?:self\.)?\w*(?:[Ss]tatus|[Mm]essage|[Ll]abel|[Tt]itle|[Nn]ote"
    r"|[Hh]int|[Cc]aption|[Ss]ubtitle|[Ee]rror|[Ss]ummary)\s*=[^=]"
)


def main() -> int:
    findings = []

    for path in sorted(SOURCES.rglob("*.swift")):
        if path.name in EXEMPT_FILES:
            continue

        declaration = ""
        for number, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
            if re.match(r"\s*(//|///)", line):
                continue

            found = DECLARATION.match(line)
            if found:
                declaration = found.group(1)

            # Trace and NSLog are developer diagnostics, not UI.
            if "Trace." in line or "NSLog" in line:
                continue

            in_ui_declaration = (
                bool(UI_DECLARATION.search(declaration))
                and RETURNS_LITERAL.search(line) is not None
            )
            if (not UI_POSITION.search(line)
                    and not in_ui_declaration
                    and not ASSIGNS_LITERAL.search(line)):
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
