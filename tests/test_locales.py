#!/usr/bin/env python3
"""Shape checks on the AceLocale-3.0 `Locales/` tree.

Plan 008 adds the localization scaffolding: `addon.L`, the vendored
AceLocale-3.0, `Locales/enUS.lua` (the source of truth) plus 10 stub locale
files. Nothing displayed changes yet -- plan 009 moves the call sites onto the
keys defined here. This suite pins:

  * the locale-file set and their `.toc` wiring + load order,
  * `enUS.lua` executes and every key is a non-empty string whose value == key
    (the `L["English"] = true` idiom),
  * no duplicate keys within a file (Lua would silently dedupe),
  * each translation file only defines keys that also exist in enUS,
  * `%s` / `%d` placeholder parity between a translation and its enUS key.

Run:  python -m unittest discover -s tests -p test_locales.py
"""

import os
import re
import unittest

from test_toc import toc_referenced_files


def _load_runtime():
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

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Mount_Tracker_Local_Zones")
LOCALES = os.path.join(ADDON, "Locales")
APP = "Mount_Tracker_Local_Zones"

BASE = "enUS"
TRANSLATIONS = ["deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]
EXPECTED_FILES = {BASE, *TRANSLATIONS}

ACE_LIB_LINE = "Libs/AceLocale-3.0/AceLocale-3.0.lua"

# A tiny AceLocale-3.0 stand-in so the locale files execute in a bare Lua state.
LUA_SHIM = r"""
local apps = {}
LibStub = setmetatable({}, { __call = function(_, name)
  if name ~= "AceLocale-3.0" then return nil end
  return {
    NewLocale = function(_, app, locale, isDefault)
      apps[app] = apps[app] or {}
      if locale ~= (GAME_LOCALE or "enUS") and not isDefault then return nil end
      local t = apps[app]
      return setmetatable({}, { __newindex = function(_, k, v)
        t[k] = (v == true) and k or v end })
    end,
    GetLocale = function(_, app) return apps[app] end,
  }
end })
function GetLocale() return GAME_LOCALE or "enUS" end
return apps
"""

# Lua format directives: positional (%1$s) or a plain %-spec, plus %% escape.
FORMAT_SPEC = re.compile(r"%\d+\$s|%[-+ #0-9.]*[sdfxXqg%]")
# Raw-text key extraction: greedy to the last ] on the line so keys that
# themselves contain ] (e.g. the "/mtlz [show ...]" help line) capture whole.
KEY_LINE = re.compile(r"^L(\[.+\])\s*=", re.M)
# A translation entry: L["key"] = "value"  (string value, not `= true`).
STRING_ENTRY = re.compile(
    r"""^L\[\s*(?P<qk>['"])(?P<key>.*?)(?P=qk)\s*\]\s*=\s*"""
    r"""(?P<qv>['"])(?P<val>.*)(?P=qv)\s*$""",
    re.M,
)


def locale_path(code):
    return os.path.join(LOCALES, f"{code}.lua")


def read_locale(code):
    with open(locale_path(code), encoding="utf-8") as fh:
        return fh.read()


def load_locale_table(codes, game_locale=None):
    """Execute the shim + each named locale file; return the resolved L table."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    if game_locale is not None:
        lua.execute(f'GAME_LOCALE = {game_locale!r}')
    apps = lua.execute(LUA_SHIM)
    loader = lua.eval("function(path, name) return assert(loadfile(path))(name) end")
    for code in codes:
        loader(locale_path(code), APP)
    return apps[APP]


def string_entries(code):
    return {m.group("key"): m.group("val") for m in STRING_ENTRY.finditer(read_locale(code))}


class TestLocaleFileSet(unittest.TestCase):
    def test_locale_dir_holds_exactly_the_expected_files(self):
        found = {
            os.path.splitext(f)[0]
            for f in os.listdir(LOCALES)
            if f.endswith(".lua")
        }
        self.assertEqual(found, EXPECTED_FILES)

    def test_toc_references_the_ace_lib_and_every_locale_file(self):
        referenced = set(toc_referenced_files())
        self.assertIn(ACE_LIB_LINE, referenced)
        for code in EXPECTED_FILES:
            self.assertIn(f"Locales/{code}.lua", referenced)

    def test_toc_load_order(self):
        files = toc_referenced_files()
        idx = {name: i for i, name in enumerate(files)}
        ace = idx[ACE_LIB_LINE]
        base = idx[f"Locales/{BASE}.lua"]
        core = idx["Core.lua"]
        for code in EXPECTED_FILES:
            pos = idx[f"Locales/{code}.lua"]
            self.assertLess(ace, pos, "AceLocale lib must load before the Locales block")
            self.assertLess(pos, core, f"Locales/{code}.lua must load before Core.lua")
            if code != BASE:
                self.assertLess(base, pos, "enUS.lua must register before other locales")


class TestRawText(unittest.TestCase):
    def test_no_duplicate_keys_within_a_file(self):
        for code in EXPECTED_FILES:
            keys = KEY_LINE.findall(read_locale(code))
            dupes = {k for k in keys if keys.count(k) > 1}
            self.assertFalse(dupes, f"{code}.lua repeats keys: {sorted(dupes)}")

    def test_translation_files_carry_their_newlocale_guard(self):
        for code in TRANSLATIONS:
            self.assertIn(
                f'NewLocale(addonName, "{code}")',
                read_locale(code),
                f"{code}.lua is missing its NewLocale(addonName, \"{code}\") guard",
            )

    def test_enus_is_the_default_silent_locale(self):
        self.assertIn(
            'NewLocale(addonName, "enUS", true, true)',
            read_locale(BASE),
        )


@unittest.skipIf(LuaRuntime is None, "lupa not installed")
class TestLocaleExecution(unittest.TestCase):
    def test_every_locale_file_loads_without_error(self):
        for code in EXPECTED_FILES:
            with self.subTest(code=code):
                load_locale_table([code], game_locale=code)

    def test_enus_keys_are_nonempty_strings_that_resolve_to_themselves(self):
        table = load_locale_table([BASE])
        items = list(table.items())
        self.assertTrue(items, "enUS.lua registered no keys")
        for key, value in items:
            self.assertIsInstance(key, str)
            self.assertTrue(key, "enUS.lua has an empty key")
            self.assertEqual(value, key, f"enUS[{key!r}] should equal its key")

    def test_translations_only_define_keys_that_exist_in_enus(self):
        base_keys = set(load_locale_table([BASE]).keys())
        for code in TRANSLATIONS:
            table = load_locale_table([BASE, code], game_locale=code)
            # Only the keys this file added on top of enUS.
            added = set(table.keys()) - base_keys
            for key in string_entries(code):
                self.assertIn(
                    key, base_keys,
                    f"{code}.lua translates {key!r}, which is not a key in enUS.lua",
                )
            self.assertFalse(
                added - base_keys,
                f"{code}.lua introduced keys absent from enUS: {sorted(added - base_keys)}",
            )

    def test_placeholder_parity_between_translation_and_enus(self):
        # In enUS the key IS the English string, so the key is the reference.
        for code in TRANSLATIONS:
            for key, value in string_entries(code).items():
                self.assertEqual(
                    sorted(FORMAT_SPEC.findall(value)),
                    sorted(FORMAT_SPEC.findall(key)),
                    f"{code}.lua {key!r}: format specifiers differ from the enUS key",
                )


if __name__ == "__main__":
    unittest.main()
