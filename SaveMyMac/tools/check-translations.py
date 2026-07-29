#!/usr/bin/env python3
"""Check the localization tables against the keys actually used in the source.

Run from the SaveMyMac directory:

    python3 tools/check-translations.py

Exits non-zero if anything is wrong, so CI can use it directly.

Three classes of problem, and the third is the one that actually crashes:

1. Missing translation — the key falls back to English. Reported as a warning,
   not a failure: partial translation is a valid state, and treating it as an
   error would mean nobody could add a language incrementally.

2. Orphan entry — a translation whose key no longer appears in the source,
   usually because the English text was edited. Warning: dead weight, not a bug.

3. Format-marker mismatch — a translation with different `%@`/`%d` placeholders
   than its key. **This is a hard failure.** `String(format:)` reads arguments
   according to the format string, so a translation with an extra `%@` reads a
   pointer that was never passed and crashes the app at runtime, in that language
   only. It is exactly the kind of bug that ships because the author never ran
   the app in the language they were translating into.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources"
TABLE = SOURCES / "Support" / "Strings.swift"

# Keys deliberately absent from a table because the word is spelled the same in
# that language. The lookup already falls through to the key, so an identity
# entry would be dead weight — but without this list the checker reports them as
# untranslated forever.
#
# That matters more than it looks. A checker that always prints the same seven
# warnings teaches people to skim past its output, and then a genuinely missing
# translation scrolls by unnoticed. The list is the price of the tool staying
# worth reading.
#
# Adding an entry here is a claim: "this word is identical in this language."
# If that is wrong, the app shows English and nobody finds out from the tool.
INTENTIONALLY_IDENTICAL = {
    "pt": {
        "Offload",      # kept as the English term in Brazilian tech usage
        "%d volume",     # identical in Portuguese
        "%d volumes",
        "%d item",
        "SaveMyMac — %@",   # brand + already-localized section name
    },
    "es": {
        "Audio",
        "SaveMyMac — %@",
    },
    "fr": {
        "Audio",
        "Navigation",
        "Actions",
        "%d volume",    # identical in French
        "%d volumes",
        "SaveMyMac — %@",
    },
}

KEY_RE = r'"((?:[^"\\]|\\.)*)"'


def keys_used() -> set:
    used = set()
    for path in SOURCES.rglob("*.swift"):
        src = path.read_text(encoding="utf-8")
        used |= set(re.findall(r"\bL\(\s*" + KEY_RE, src))
        for singular, plural in re.findall(
            r"\bLp\(\s*" + KEY_RE + r"\s*,\s*" + KEY_RE, src
        ):
            used |= {singular, plural}
    return used


def table(name: str) -> dict:
    src = TABLE.read_text(encoding="utf-8")
    match = re.search(
        rf"static let {name}: \[String: String\] = \[(.*?)\n    \]", src, re.S
    )
    if not match:
        sys.exit(f"error: table '{name}' not found in {TABLE.name}")

    body = match.group(1)
    # Strip comment lines first: a `//` line mentioning a quoted string would
    # otherwise register as an entry.
    body = "\n".join(l for l in body.split("\n") if not l.strip().startswith("//"))

    entries = {}
    for key, value in re.findall(
        rf"^\s*{KEY_RE}:\s*\n?\s*{KEY_RE}", body, re.M
    ):
        entries[key] = value
    return entries


def markers(text: str) -> list:
    return sorted(re.findall(r"%[@d]", text))


def main() -> int:
    used = keys_used()
    languages = ["pt", "es", "fr"]
    failures = 0
    warnings = 0

    print(f"{len(used)} keys used in source\n")

    for name in languages:
        entries = table(name)
        identical = INTENTIONALLY_IDENTICAL.get(name, set())
        missing = sorted(used - set(entries) - identical)
        orphans = sorted(set(entries) - used)

        # An entry that duplicates its key contradicts the list above, and one
        # of the two is wrong. Worth saying out loud rather than tolerating.
        redundant = sorted(k for k in identical if k in entries)
        for key in redundant:
            print(f"       warn  listed as identical but also translated: {key[:50]}")
            warnings += 1

        bad_format = []
        for key, value in entries.items():
            if markers(key) != markers(value):
                bad_format.append((key, markers(key), markers(value)))

        status = "OK" if not (missing or orphans or bad_format) else "  "
        print(f"[{status}] {name}: {len(entries)} translated")

        for key, want, got in bad_format:
            print(f"       ERROR format markers {want} != {got}: {key[:60]}")
            failures += 1

        for key in missing:
            print(f"       warn  untranslated (falls back to English): {key[:60]}")
            warnings += 1

        for key in orphans:
            print(f"       warn  orphan (key not in source): {key[:60]}")
            warnings += 1

    # Duplicate keys in one table: Swift keeps the last one silently, so an
    # earlier translation is lost with no diagnostic.
    src = TABLE.read_text(encoding="utf-8")
    for name in languages:
        match = re.search(
            rf"static let {name}: \[String: String\] = \[(.*?)\n    \]", src, re.S
        )
        body = "\n".join(
            l for l in match.group(1).split("\n") if not l.strip().startswith("//")
        )
        found = re.findall(rf"^\s*{KEY_RE}:", body, re.M)
        for key in {k for k in found if found.count(k) > 1}:
            print(f"[  ] {name}: ERROR duplicate key: {key[:60]}")
            failures += 1

    print()
    if failures:
        print(f"{failures} error(s), {warnings} warning(s)")
        return 1
    print(f"no errors, {warnings} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
