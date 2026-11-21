"""Offline tests for Glowey's Recipes: the shop strips and the rules of buying and learning, the
Professionally Lost hand-off, what shows at login and in which order, and the window (its rules, and
its real files run end to end on a strict stand-in for the game).

    python -I Tools/tests/run.py                every Tools/tests/test_*.lua
    python -I Tools/tests/run.py test_buying    one test (name with or without .lua)

Each test runs in a fresh Lua 5.1 state (lupa): Tools/tests/mocks.lua (a strict vendor and trainer,
vendors that close and open under a run, bags that fill late, a read-only stand-in for
Professionally Lost, timers the test plays forward), then the plugin's own files listed in FILES,
unchanged, then the test file. A test made of cases (T.case) runs them all and names every one
that fails, so a run against an older file shows each rule it breaks. A test passes when it returns its "ok, N checks"
line; any Lua error fails it. Needs `pip install lupa`. Left out of the zip players download
(.pkgmeta ignores Tools).
"""
import glob
import os
import sys

import lupa.lua51 as l51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ADDON = "DaylightRecipes"
# The files under test, in the order the .toc loads them. The rest of the plugin is stood in for
# by mocks.lua's Bootstrap.
FILES = ["Locales/Locales.lua", "ProfLost.lua", "Calc.lua", "Prices.lua", "Shop.lua"]


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def toc_order():
    """The FILES as the .toc orders them, so a test run fails when one is dropped from it."""
    listed = []
    for line in read(os.path.join(ROOT, ADDON + ".toc")).splitlines():
        line = line.strip().replace("\\", "/")
        if line and not line.startswith("#"):
            listed.append(line)
    missing = [f for f in FILES if f not in listed]
    if missing:
        raise RuntimeError("not in the .toc: " + ", ".join(missing))
    return sorted(FILES, key=listed.index)


def run(test_path):
    rt = l51.LuaRuntime()
    load = rt.eval("function(src, name) local f, e = loadstring(src, name) if not f then error(e, 0) end return f end")
    load(read(os.path.join(HERE, "mocks.lua")), "@mocks.lua")()
    rt.execute("NS = {} Bootstrap(NS)")
    # For a test that loads a file of the plugin itself (test_window_state.lua: WindowState.lua).
    rt.globals()["ADDON_ROOT"] = ROOT.replace(os.sep, "/")
    call = rt.eval("function(f, addon) return f(addon, NS) end")
    for rel in toc_order():
        call(load(read(os.path.join(ROOT, rel)), "@" + rel), ADDON)
    # (mocks.lua's AfterLoad: the real Calc.lua reads its prices from the tests' world.)
    rt.execute("if AfterLoad then AfterLoad(NS) end")
    return load(read(test_path), "@" + os.path.basename(test_path))()


def main():
    wanted = sys.argv[1:]
    tests = sorted(glob.glob(os.path.join(HERE, "test_*.lua")))
    if wanted:
        names = {w if w.endswith(".lua") else w + ".lua" for w in wanted}
        tests = [t for t in tests if os.path.basename(t) in names]
    failed = 0
    for path in tests:
        name = os.path.basename(path)
        try:
            result = run(path)
            if not (isinstance(result, str) and result.startswith("ok")):
                raise RuntimeError("the test did not return its ok line (got %r)" % (result,))
            print("PASS %-24s %s" % (name, result))
        except Exception as err:  # a Lua error is a failed test, never a crash of the runner
            failed += 1
            print("FAIL %-24s %s" % (name, err))
    print("%d tests, %d failed" % (len(tests), failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
