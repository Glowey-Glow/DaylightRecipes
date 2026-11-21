"""Checks the six language files against the text the code uses.

    python -I Tools/locales.py            what each language file is missing, and what none of the code uses
    python -I Tools/locales.py --strict   the same, and exit 1 when a language misses a line

Every user-facing string is L["English"] (or one of ns.Plural's two English forms) in a .lua file
of the plugin; each Locales/<language>.lua gives L["English"] = "Translation" (a sorted block, then
dated sections of later additions). A key
whose English is one of the game's own global strings (the GAME table in Locales/Locales.lua) needs
no line: the client's translation stands in. Left out of the zip players download (.pkgmeta).
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LANGS = ["deDE", "frFR", "esES", "ruRU", "koKR", "zhCN"]

STRING = r'"((?:[^"\\]|\\.)*)"'
USED = re.compile(r'\bL\[' + STRING + r'\]')
PLURAL = re.compile(r'\bPlural\(\s*[^,]+,\s*' + STRING + r'\s*,\s*' + STRING)
LINE = re.compile(r'^L\[' + STRING + r'\]\s*=')
GAME = re.compile(r'^\s*\[' + STRING + r'\]\s*=\s*"[A-Z0-9_]+",')


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def used_keys():
    keys = set()
    for path in glob.glob(os.path.join(ROOT, "*.lua")):
        text = read(path)
        keys.update(USED.findall(text))
        for one, many in PLURAL.findall(text):
            keys.add(one)
            keys.add(many)
    return keys


def game_keys():
    keys = set()
    for line in read(os.path.join(ROOT, "Locales", "Locales.lua")).splitlines():
        m = GAME.match(line)
        if m:
            keys.add(m.group(1))
    return keys


def main():
    used = used_keys()
    game = game_keys()
    failed = False
    for lang in LANGS:
        have = []
        for line in read(os.path.join(ROOT, "Locales", lang + ".lua")).splitlines():
            m = LINE.match(line)
            if m:
                have.append(m.group(1))
        missing = sorted(k for k in used if k not in set(have) and k not in game)
        # (Russian's 2-4 plural forms are keyed "<many>|few": used through ns.Plural.)
        unused = sorted(k for k in have if k not in used and not k.endswith("|few"))
        print("%s: %d lines, %d missing, %d unused" % (lang, len(have), len(missing), len(unused)))
        for k in missing:
            print("   missing: " + k)
        for k in unused:
            print("   unused:  " + k)
        if missing:
            failed = True
    sys.exit(1 if failed and "--strict" in sys.argv else 0)


if __name__ == "__main__":
    main()
