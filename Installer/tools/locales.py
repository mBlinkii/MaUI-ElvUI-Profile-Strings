"""
Checks the translations in ElvUI_MaUI/locales against the strings the code uses.

    python -I Installer/tools/locales.py

Reports per locale file the missing and unused keys and translations whose format
placeholders (%s, %d, ...) differ from the English key. Exits with 1 on any problem.
"""

import os
import re
import sys

ADDON = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "ElvUI_MaUI"))

# L["..."] with escaped quotes inside the key
KEY = re.compile(r'L\["((?:[^"\\]|\\.)*)"\]')
ENTRY = re.compile(r'^L\["((?:[^"\\]|\\.)*)"\] = "((?:[^"\\]|\\.)*)"', re.M)
PLACEHOLDER = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdif%]")


def code_keys():
    keys = set()
    for folder, _, files in os.walk(ADDON):
        if os.path.basename(folder) in ("locales", "data") or "data" in folder.split(os.sep):
            continue
        for name in files:
            if name.endswith(".lua"):
                with open(os.path.join(folder, name), encoding="utf-8") as f:
                    keys.update(KEY.findall(f.read()))
    return keys


def main():
    used = code_keys()
    problems = 0
    folder = os.path.join(ADDON, "locales")
    for name in sorted(os.listdir(folder)):
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            entries = dict(ENTRY.findall(f.read()))
        missing = sorted(used - entries.keys())
        unused = sorted(entries.keys() - used)
        placeholders = [k for k, v in entries.items() if sorted(PLACEHOLDER.findall(k)) != sorted(PLACEHOLDER.findall(v))]
        status = "ok" if not (missing or unused or placeholders) else "PROBLEMS"
        print("%s: %d strings, %s" % (name, len(entries), status))
        for title, keys in (("missing", missing), ("unused", unused), ("placeholders differ", placeholders)):
            for key in keys:
                print("   %s: %s" % (title, key))
        problems += len(missing) + len(unused) + len(placeholders)
    print("%d strings used in code" % len(used))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
