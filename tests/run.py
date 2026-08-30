#!/usr/bin/env python3
"""Headless smoke-test runner for the Mount Tracker: Local Zones addon.

Loads the addon's Lua files under a minimal WoW API stub (see stub.lua) and
drives its full lifecycle + every slash command, asserting only that nothing
throws and the basic wiring is present. This is NOT an in-game test: the stub is
a stand-in, not a model of Blizzard's APIs, and no frame is really rendered.

Usage:  python tests/run.py
Requires:  pip install lupa
Exit code: 0 = all scenarios passed, 1 = a failure, 2 = harness/setup error.
"""

import os
import sys


def _load_runtime():
    # CI runs LuaJIT; this dev box only ships the 5.x builds. Any of them runs
    # the addon (it stays inside the Lua 5.1 subset it targets for WoW).
    for module in ("luajit21", "lua54", "lua55", "lua53", "lua52", "lua51"):
        try:
            return __import__(f"lupa.{module}", fromlist=["LuaRuntime"]).LuaRuntime
        except ImportError:
            continue
    try:
        import lupa

        return lupa.LuaRuntime
    except ImportError:
        return None


LuaRuntime = _load_runtime()
if LuaRuntime is None:
    sys.stderr.write("lupa is not installed. Run:  python -m pip install --user lupa\n")
    sys.exit(2)

TEST_DIR = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.join(os.path.dirname(TEST_DIR), "Mount_Tracker_Local_Zones")
SCENARIOS = ("cold", "warm")

GREEN, RED, DIM, RESET = "\033[32m", "\033[31m", "\033[2m", "\033[0m"
if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
    GREEN = RED = DIM = RESET = ""


def run_scenario(name):
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.TEST_DIR = TEST_DIR.replace("\\", "/")
    g.ADDON_DIR = ADDON_DIR.replace("\\", "/")
    g.SCENARIO = name
    try:
        with open(os.path.join(TEST_DIR, "init.lua"), "r", encoding="utf-8") as fh:
            lua.execute(fh.read())
    except Exception as exc:  # noqa: BLE001 - report any Lua-side blowup
        return False, [("scenario crashed before it could report", False, str(exc))]

    result = g.RESULT
    if result is None:
        return False, [("scenario produced no result", False, "")]
    checks = [
        (c["name"], bool(c["ok"]), c["detail"])
        for c in result["checks"].values()
    ]
    return bool(result["ok"]), checks


def main():
    all_ok = True
    for name in SCENARIOS:
        ok, checks = run_scenario(name)
        all_ok = all_ok and ok
        passed = sum(1 for _, cok, _ in checks if cok)
        header = f"{GREEN}PASS{RESET}" if ok else f"{RED}FAIL{RESET}"
        print(f"\n[{header}] scenario: {name}  ({passed}/{len(checks)} checks)")
        for cname, cok, detail in checks:
            mark = f"{GREEN}ok{RESET}" if cok else f"{RED}XX{RESET}"
            line = f"  {mark}  {cname}"
            if not cok and detail:
                line += f"\n        {DIM}{detail}{RESET}"
            print(line)

    print()
    if all_ok:
        print(f"{GREEN}All smoke scenarios passed.{RESET}")
        sys.exit(0)
    print(f"{RED}Smoke tests failed.{RESET}")
    sys.exit(1)


if __name__ == "__main__":
    main()
