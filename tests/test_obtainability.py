#!/usr/bin/env python3
"""Unit tests for Mount_Tracker_Local_Zones/Obtainability.lua.

Obtainability is a pure module: Evaluate(mountID, row) -> { state, detail,
sortRank } from curated data (MountData + Overrides) plus a few guarded live-API
reads. The smoke suite only happens to hit `available` / `rep_gated` /
`collected` / `farmable`; this pins every branch -- currency vendor, achievement
gate, reset-locked (lockoutQuest done), the classic-reputation path, gold
formatting, the rep-met fall-through, and the tooltip lines.

Loading strategy: the fallback path from plans/002 -- Core.lua is NOT loaded.
The five helpers Obtainability.lua captures at load (SafeApiCall,
SafeApiCallMulti, Curated, Print, DebugPrint) plus a MountInfo stub are
hand-defined in Lua; then the real MountData.lua + Overrides.lua + Obtainability.lua
are loaded so the "shipped seed" cases exercise real curated data.

Run:  python -m unittest discover -s tests -p test_obtainability.py
"""

import os
import unittest


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

# Injected test-mount ids live well above the real range (max real id ~3119) so
# they never collide with a shipped MountData / Overrides entry.
BASE = 90000

# The Lua-side stub: the addon.* helpers Obtainability captures at load, a
# MountInfo stub, and the guarded live APIs it reads (each a real Lua function so
# `type(x) == "function"` guards in the module pass). Data comes in as a Lua
# table `opts`.
STUB = r"""
local opts = ...
local addon = {}

_G.GetMoney = function() return opts.money end

_G.C_MajorFactions = {
    GetMajorFactionData = function(id)
        local f = opts.factions[id]
        if f and f.renownLevel ~= nil then
            return { renownLevel = f.renownLevel }
        end
        return nil
    end,
}
_G.C_Reputation = {
    GetFactionDataByID = function(id)
        local f = opts.factions[id]
        if f and f.currentStanding ~= nil then
            return { currentStanding = f.currentStanding }
        end
        return nil
    end,
}
if opts.currencyApi then
    _G.C_CurrencyInfo = {
        GetCurrencyInfo = function(id)
            local c = opts.currencies[id]
            if c == nil then return nil end
            return { quantity = c.quantity }
        end,
    }
else
    _G.C_CurrencyInfo = nil
end
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return opts.quests[id] == true end,
}
_G.GetAchievementInfo = function(id)
    local a = opts.achievements[id]
    if a == nil then return id, "Achievement " .. tostring(id), 10, false end
    return id, a.name or ("Achievement " .. tostring(id)), 10, a.completed == true
end

-- addon.* helpers, copied semantics from Core.lua:69-153.
addon.SafeApiCall = function(func, ...)
    if type(func) ~= "function" then return nil end
    local ok, res = pcall(func, ...)
    if not ok then return nil end
    return res
end
local function ForwardIfOk(ok, ...)
    if ok then return ... end
end
addon.SafeApiCallMulti = function(func, ...)
    if type(func) ~= "function" then return end
    return ForwardIfOk(pcall(func, ...))
end
addon.Print = function() end
addon.DebugPrint = function() end

-- Localization: Core.lua sets addon.L (an AceLocale table). Not loaded here, so
-- stand in a silent-default table: every key resolves to itself (English text).
addon.L = setmetatable({}, { __index = function(_, k) return k end })

addon.Curated = function(field, id)
    local ov = addon.MountOverrides and addon.MountOverrides[field]
    if ov and ov[id] ~= nil then
        return ov[id]
    end
    local md = addon.MountData and addon.MountData[field]
    return md and md[id]
end

-- Only tuple slot 11 (isCollected) matters to Obtainability.AddTooltipLines.
addon.MountInfo = function(id)
    return "Mount " .. tostring(id), id * 10, "icon", false, true, 1, false,
        false, nil, false, opts.collected[id] == true, id
end

return addon
"""


class Env:
    """A loaded Lua state: real MountData + Overrides + Obtainability under the stub."""

    def __init__(self, *, overrides=None, money=0, factions=None, currencies=None,
                 quests=None, achievements=None, collected=None, currency_api=True):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        opts = self.lua.table_from({
            "money": money,
            "factions": factions or {},
            "currencies": currencies or {},
            "quests": quests or {},
            "achievements": achievements or {},
            "collected": collected or {},
            "currencyApi": currency_api,
        }, recursive=True)
        self.addon = self.lua.execute(STUB, opts)

        for rel in ("MountData.lua", "Overrides.lua", "Obtainability.lua"):
            path = os.path.join(ADDON, rel).replace("\\", "/")
            self.lua.eval("function(p) return assert(loadfile(p)) end")(path)(
                "Mount_Tracker_Local_Zones", self.addon)

        for field, entries in (overrides or {}).items():
            sub = self.addon["MountOverrides"][field]
            if sub is None:
                sub = self.lua.table()
                self.addon["MountOverrides"][field] = sub
            for k, v in entries.items():
                sub[k] = (self.lua.table_from(v, recursive=True)
                          if isinstance(v, (dict, list)) else v)

    @property
    def ob(self):
        return self.addon["Obtainability"]

    def evaluate(self, mount_id, **row):
        # Pass row as a real Lua table so a missing key reads as nil (a Python
        # dict proxy raises KeyError when Lua indexes an absent field).
        return self.ob["Evaluate"](mount_id, self.lua.table_from(row))

    def rank(self, state):
        return self.ob["STATE"][state]["rank"]

    def tooltip_lines(self, mount_id):
        captured = []
        tip = self.lua.eval("""
            function(sink)
                return { AddLine = function(_, text) sink(tostring(text)) end }
            end
        """)(lambda text: captured.append(text))
        self.ob["AddTooltipLines"](tip, mount_id)
        return captured


@unittest.skipIf(LuaRuntime is None, "lupa not installed")
class TestEvaluate(unittest.TestCase):
    def test_collected_short_circuits(self):
        e = Env()
        r = e.evaluate(BASE + 1, isCollected=True, source="vendor")
        self.assertEqual(r["state"], "collected")
        self.assertIsNone(r["detail"])
        self.assertEqual(r["sortRank"], e.rank("collected"))

    def test_gold_vendor_affordable(self):
        mid = BASE + 2
        e = Env(money=2_000_000,
                overrides={"vendor": {mid: {"cost": 1_000_000, "npc": "Gnimo"}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "available")
        self.assertIn("100g", r["detail"])
        self.assertIn("Gnimo", r["detail"])
        self.assertEqual(r["sortRank"], e.rank("available"))

    def test_gold_vendor_too_poor(self):
        mid = BASE + 3
        e = Env(money=5,
                overrides={"vendor": {mid: {"cost": 1_000_000, "npc": "Gnimo"}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "rep_gated")
        self.assertIn("100g", r["detail"])

    def test_currency_vendor_enough(self):
        mid = BASE + 4
        e = Env(currencies={2032: {"quantity": 99}},
                overrides={"vendor": {mid: {"cost": 50, "currencyID": 2032}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "available")
        self.assertIn("(currency)", r["detail"])

    def test_currency_vendor_short(self):
        mid = BASE + 5
        e = Env(currencies={2032: {"quantity": 10}},
                overrides={"vendor": {mid: {"cost": 50, "currencyID": 2032}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "rep_gated")

    def test_currency_vendor_api_missing_is_optimistic(self):
        mid = BASE + 6
        e = Env(currency_api=False,
                overrides={"vendor": {mid: {"cost": 50, "currencyID": 2032}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "available")

    def test_renown_gate_short(self):
        mid = BASE + 7
        e = Env(factions={2507: {"renownLevel": 5}},
                overrides={"repFaction": {mid: {"factionID": 2507, "standing": 25}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "rep_gated")
        self.assertIn("Renown 5", r["detail"])
        self.assertIn("25", r["detail"])
        self.assertEqual(r["sortRank"], e.rank("rep_gated"))

    def test_renown_met_falls_through_to_vendor(self):
        mid = BASE + 8
        e = Env(factions={2507: {"renownLevel": 30}},
                overrides={
                    "repFaction": {mid: {"factionID": 2507, "standing": 25}},
                    "vendor": {mid: {"npc": "Granpap"}},
                })
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "available")

    def test_classic_rep_gate_short(self):
        mid = BASE + 9
        e = Env(factions={1173: {"currentStanding": 21000}},
                overrides={"repFaction": {mid: {"factionID": 1173, "standing": 42000}}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "rep_gated")
        self.assertIn("21000", r["detail"])
        self.assertIn("42000", r["detail"])

    def test_achievement_gate(self):
        mid = BASE + 10
        e = Env(achievements={12345: {"name": "Glory of the Raider", "completed": False}},
                overrides={"achievementID": {mid: 12345}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "achievement_gated")
        self.assertEqual(r["detail"], "Glory of the Raider")
        self.assertEqual(r["sortRank"], e.rank("achievement_gated"))

    def test_achievement_earned_is_not_gated(self):
        mid = BASE + 11
        e = Env(achievements={12345: {"name": "Glory of the Raider", "completed": True}},
                overrides={"achievementID": {mid: 12345}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "drop")

    def test_weekly_lockout_not_done(self):
        mid = BASE + 12
        e = Env(overrides={"lockout": {mid: "weekly"}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "farmable")
        self.assertIn("weekly", r["detail"])
        self.assertEqual(r["sortRank"], e.rank("farmable"))

    def test_weekly_lockout_with_drop_chance(self):
        mid = BASE + 13
        e = Env(overrides={"lockout": {mid: "weekly"}, "dropChance": {mid: "~1%"}})
        r = e.evaluate(mid, isCollected=False)
        self.assertIn("weekly", r["detail"])
        self.assertIn("~1%", r["detail"])

    def test_lockout_done_this_reset(self):
        mid = BASE + 14
        e = Env(quests={555: True},
                overrides={"lockout": {mid: "daily"}, "lockoutQuest": {mid: 555}})
        r = e.evaluate(mid, isCollected=False)
        self.assertEqual(r["state"], "reset_locked")
        self.assertIn("done this reset", r["detail"])

    def test_plain_drop(self):
        mid = BASE + 15
        e = Env(overrides={"dropChance": {mid: "~2%"}})
        r = e.evaluate(mid, isCollected=False, source="drop")
        self.assertEqual(r["state"], "drop")
        self.assertEqual(r["detail"], "~2%")

    def test_quest_source_collapses_to_drop(self):
        mid = BASE + 16
        e = Env()
        r = e.evaluate(mid, isCollected=False, source="quest")
        self.assertEqual(r["state"], "drop")

    def test_shipped_seed_mount_168_is_farmable(self):
        e = Env()
        r = e.evaluate(168, isCollected=False, source="instance")
        self.assertEqual(r["state"], "farmable")

    def test_shipped_seed_mount_236_rich_is_available(self):
        e = Env(money=5000 * 10000 * 100)
        r = e.evaluate(236, isCollected=False, source="vendor")
        self.assertEqual(r["state"], "available")


@unittest.skipIf(LuaRuntime is None, "lupa not installed")
class TestFormatting(unittest.TestCase):
    """FormatGold is a local; exercise it through a gold-vendor detail string."""

    def _detail(self, cost):
        mid = BASE + 20
        e = Env(money=10 ** 15, overrides={"vendor": {mid: {"cost": cost}}})
        return e.evaluate(mid, isCollected=False)["detail"]

    def test_thousands_separated(self):
        self.assertIn("123,456g", self._detail(1_234_567_800))

    def test_zero_gold(self):
        self.assertIn("0g", self._detail(0))

    def test_two_digit_gold_has_no_comma(self):
        detail = self._detail(999_900)  # 99g
        self.assertIn("99g", detail)
        self.assertNotIn(",", detail)


@unittest.skipIf(LuaRuntime is None, "lupa not installed")
class TestTooltip(unittest.TestCase):
    def test_collected_mount_gets_no_lines(self):
        e = Env(collected={BASE + 30: True})
        self.assertEqual(e.tooltip_lines(BASE + 30), [])

    def test_achievement_gated_lines(self):
        mid = BASE + 31
        e = Env(achievements={999: {"name": "Glory of the Hero", "completed": False}},
                overrides={"achievementID": {mid: 999}})
        lines = e.tooltip_lines(mid)
        self.assertTrue(any("Achievement needed" in ln for ln in lines))
        self.assertTrue(any("Glory of the Hero" in ln for ln in lines))

    def test_rep_gated_renown_lines(self):
        mid = BASE + 32
        e = Env(factions={2507: {"renownLevel": 3}},
                overrides={"repFaction": {mid: {"factionID": 2507, "standing": 20}}})
        lines = e.tooltip_lines(mid)
        self.assertTrue(any("Reputation needed" in ln for ln in lines))
        self.assertTrue(any("Renown 3" in ln and "20" in ln for ln in lines))

    def test_subcat_context_line_for_instance_mount(self):
        # Shipped mount 168: MountData source = instance, subcat = raid.
        e = Env()
        lines = e.tooltip_lines(168)
        self.assertTrue(any("Raid drop" in ln for ln in lines))

    def test_note_not_duplicated_when_equal_to_detail(self):
        mid = BASE + 34
        e = Env(overrides={"dropChance": {mid: "~2%"}, "note": {mid: "~2%"}})
        lines = e.tooltip_lines(mid)
        self.assertEqual(sum(1 for ln in lines if ln == "~2%"), 1)

    def test_note_added_when_different_from_detail(self):
        mid = BASE + 35
        e = Env(overrides={
            "dropChance": {mid: "~2%"},
            "note": {mid: "Only during the Love festival."},
        })
        lines = e.tooltip_lines(mid)
        self.assertTrue(any("Love festival" in ln for ln in lines))


if __name__ == "__main__":
    unittest.main()
