#!/usr/bin/env python3
"""Structural checks on the generated MountData.lua and hand-kept Overrides.lua.

The generator has its own sanity gate, but a hand-edit, a merge slip or a schema
drift can still land a malformed table in the shipped file. This loads both files
under a bare Lua state (no WoW stub -- they only assign `addon.MountData` /
`addon.MountOverrides`) and asserts the shape every consumer (MountModel,
Obtainability, Map) relies on.

Run:  python -m unittest discover -s tests -p test_mountdata.py
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

# source values the generator / Overrides are allowed to emit.
KNOWN_SOURCES = {
    "instance", "drop", "vendor", "quest",
    "zonedrop", "worldevent", "profession", "achievement",
}

# Thresholds sit well below the current real numbers (293 zones / 1846 refs /
# 988 global on build 12.1.0.69497) so a normal patch refresh never trips them;
# a collapse to a fraction of the data still does.
MIN_ZONES = 120
MIN_REFS = 800
MIN_GLOBAL = 400


def load_addon_tables():
    lua = LuaRuntime(unpack_returned_tuples=True)
    addon = lua.table()
    loader = lua.eval(
        "function(path, addon) return assert(loadfile(path))('Test', addon) end"
    )
    loader(os.path.join(ADDON, "MountData.lua"), addon)
    loader(os.path.join(ADDON, "Overrides.lua"), addon)
    return addon


def to_list(lua_table):
    return list(lua_table.values()) if lua_table is not None else []


@unittest.skipIf(LuaRuntime is None, "lupa not installed")
class TestMountData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.md = load_addon_tables()["MountData"]
        cls.placed = set()
        for ids in cls.md["zones"].values():
            cls.placed.update(to_list(ids))

    def test_build_and_updated_are_well_formed(self):
        self.assertRegex(self.md["build"], r"^\d+\.\d+\.\d+\.\d+$")
        self.assertRegex(self.md["updated"], r"^\d{4}-\d{2}-\d{2}$")

    def test_zones_map_positive_uimap_ids_to_non_empty_mount_lists(self):
        count, refs = 0, 0
        for uimap_id, ids in self.md["zones"].items():
            count += 1
            self.assertIsInstance(uimap_id, int)
            self.assertGreater(uimap_id, 0)
            mounts = to_list(ids)
            self.assertTrue(mounts, f"zone {uimap_id} has an empty list")
            for mount_id in mounts:
                self.assertIsInstance(mount_id, int)
                self.assertGreater(mount_id, 0)
            refs += len(mounts)
        self.assertGreater(count, MIN_ZONES, "far fewer zones than expected")
        self.assertGreater(refs, MIN_REFS, "far fewer mount references than expected")

    def test_zone_mount_lists_have_no_duplicates(self):
        for uimap_id, ids in self.md["zones"].items():
            mounts = to_list(ids)
            self.assertEqual(
                len(mounts), len(set(mounts)),
                f"zone {uimap_id} lists a mount twice",
            )

    def test_source_values_are_from_the_known_set(self):
        for mount_id, source in self.md["source"].items():
            self.assertIsInstance(mount_id, int)
            self.assertIn(source, KNOWN_SOURCES, f"mount {mount_id} has source {source!r}")

    def test_subcat_values_are_non_empty_strings(self):
        for mount_id, subcat in self.md["subcat"].items():
            self.assertIsInstance(subcat, str)
            self.assertTrue(subcat, f"mount {mount_id} has an empty subcat")

    def test_expansion_values_are_integers(self):
        # ItemSparse.ExpansionID is occasionally negative (-3 etc); only the type
        # matters -- MountModel buckets unknowns.
        for mount_id, expansion in self.md["expansion"].items():
            self.assertIsInstance(expansion, int, f"mount {mount_id} expansion {expansion!r}")

    def test_faction_values_are_zero_or_one(self):
        for mount_id, side in self.md["faction"].items():
            self.assertIsInstance(mount_id, int)
            self.assertIn(side, (0, 1), f"mount {mount_id} has faction {side}")

    def test_points_are_uimap_plus_in_range_coordinates(self):
        for mount_id, point in self.md["points"].items():
            coords = to_list(point)
            self.assertEqual(len(coords), 3, f"mount {mount_id} point is not a triple")
            uimap_id, x, y = coords
            self.assertGreater(uimap_id, 0)
            self.assertTrue(0 <= x <= 10000, f"mount {mount_id} x={x} out of range")
            self.assertTrue(0 <= y <= 10000, f"mount {mount_id} y={y} out of range")

    def test_positioned_mounts_are_mapped_to_a_zone(self):
        for mount_id in self.md["points"].keys():
            self.assertIn(
                mount_id, self.placed, f"positioned mount {mount_id} is in no zone"
            )

    def test_global_list_is_positive_ints_without_duplicates(self):
        globals_ = to_list(self.md["global"])
        self.assertGreater(len(globals_), MIN_GLOBAL, "far fewer global mounts than expected")
        self.assertEqual(len(globals_), len(set(globals_)), "global list has a duplicate")
        for mount_id in globals_:
            self.assertIsInstance(mount_id, int)
            self.assertGreater(mount_id, 0)

    def test_global_mounts_are_not_also_in_a_zone(self):
        for mount_id in to_list(self.md["global"]):
            self.assertNotIn(
                mount_id, self.placed, f"global mount {mount_id} is also mapped to a zone"
            )

    def test_optional_input_tables_are_present(self):
        for key in ("points", "achievementID", "repFaction", "vendor"):
            self.assertIsNotNone(self.md[key], f"MountData.{key} missing")

    def test_generated_file_carries_the_do_not_edit_banner(self):
        with open(os.path.join(ADDON, "MountData.lua"), encoding="utf-8") as fh:
            head = fh.read(400)
        self.assertIn("GENERATED by tools/generate_mount_zones.py", head)


@unittest.skipIf(LuaRuntime is None, "lupa not installed")
class TestOverrides(unittest.TestCase):
    EXPECTED_SUB_TABLES = (
        "add", "remove", "source", "subcat", "points", "faction", "expansion",
        "dropChance", "lockout", "lockoutQuest", "vendor", "repFaction", "note",
    )

    @classmethod
    def setUpClass(cls):
        cls.ov = load_addon_tables()["MountOverrides"]

    def test_has_every_expected_sub_table(self):
        for key in self.EXPECTED_SUB_TABLES:
            self.assertIsNotNone(self.ov[key], f"MountOverrides.{key} missing")

    def test_add_and_remove_map_uimap_ids_to_mount_lists(self):
        for section in ("add", "remove"):
            for uimap_id, ids in self.ov[section].items():
                self.assertIsInstance(uimap_id, int)
                for mount_id in to_list(ids):
                    self.assertIsInstance(mount_id, int)

    def test_override_source_values_are_from_the_known_set(self):
        for mount_id, source in self.ov["source"].items():
            self.assertIn(source, KNOWN_SOURCES, f"mount {mount_id} source {source!r}")

    def test_override_points_are_in_range_triples(self):
        for mount_id, point in self.ov["points"].items():
            coords = to_list(point)
            self.assertEqual(len(coords), 3, f"mount {mount_id} point is not a triple")
            uimap_id, x, y = coords
            self.assertGreater(uimap_id, 0)
            self.assertTrue(0 <= x <= 10000, f"mount {mount_id} x={x}")
            self.assertTrue(0 <= y <= 10000, f"mount {mount_id} y={y}")

    def test_override_faction_values_are_zero_or_one(self):
        for _mount_id, side in self.ov["faction"].items():
            self.assertIn(side, (0, 1))

    def test_lockout_values_are_daily_or_weekly(self):
        for mount_id, cadence in self.ov["lockout"].items():
            self.assertIn(cadence, ("daily", "weekly"), f"mount {mount_id} lockout {cadence!r}")

    def test_every_lockout_quest_also_has_a_lockout(self):
        for mount_id in self.ov["lockoutQuest"].keys():
            self.assertIsNotNone(
                self.ov["lockout"][mount_id],
                f"mount {mount_id} has a lockoutQuest but no lockout cadence",
            )

    def test_vendor_entries_have_a_numeric_cost_and_uimap(self):
        for mount_id, entry in self.ov["vendor"].items():
            cost = entry["cost"]
            self.assertIsInstance(cost, (int, float), f"mount {mount_id} vendor cost {cost!r}")
            self.assertGreaterEqual(cost, 0)
            uimap_id = entry["uiMapID"]
            self.assertIsInstance(uimap_id, (int, float), f"mount {mount_id} vendor uiMapID")
            # x / y are optional, but when present they must be an in-range point
            # coordinate (same 0-10000 scale as points) so the vendor map-pin /
            # TomTom-waypoint fallback can use them directly.
            for axis in ("x", "y"):
                if axis in entry:
                    value = entry[axis]
                    self.assertIsInstance(value, (int, float), f"mount {mount_id} vendor {axis} {value!r}")
                    self.assertTrue(0 <= value <= 10000, f"mount {mount_id} vendor {axis}={value}")

    def test_rep_faction_entries_are_number_pairs(self):
        for mount_id, entry in self.ov["repFaction"].items():
            pair = to_list(entry)
            self.assertEqual(len(pair), 2, f"mount {mount_id} repFaction is not a pair")
            for value in pair:
                self.assertIsInstance(value, (int, float), f"mount {mount_id} repFaction {value!r}")

    def test_drop_chance_values_are_non_empty_strings(self):
        for mount_id, text in self.ov["dropChance"].items():
            self.assertIsInstance(text, str)
            self.assertTrue(text, f"mount {mount_id} has an empty dropChance")


if __name__ == "__main__":
    unittest.main()
