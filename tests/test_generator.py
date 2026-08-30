#!/usr/bin/env python3
"""Unit tests for tools/generate_mount_zones.py.

Pure data transforms only -- hand-built fixtures, no network, no wago.tools, no
DB2 download. These pin the behaviour a bad refresh run would silently break:
SourceText cleaning and label parsing, the zone-name -> uiMapID match with its
everywhere-vendor / sub-map caps, region normalisation, the instance loot-table
join, the sanity thresholds, and the Lua rendering.

Run:  python -m unittest discover -s tests -p test_generator.py
"""

import os
import sys
import tempfile
import textwrap
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import generate_mount_zones as gen  # noqa: E402


def make_data(**attrs):
    """A Data instance with __init__ bypassed; set only what a test touches."""
    data = gen.Data.__new__(gen.Data)
    for key, value in attrs.items():
        setattr(data, key, value)
    return data


class TestCleanText(unittest.TestCase):
    def test_strips_colour_and_texture_and_hyperlink_escapes(self):
        raw = "|cFFFFD200Vendor: |rUnger Statforth|n|cFFFFD200Cost: |r5000|Hcurrency:1166|h|h"
        self.assertEqual(gen.clean_text(raw), "Vendor: Unger Statforth Cost: 5000")

    def test_collapses_whitespace_and_handles_none(self):
        self.assertEqual(gen.clean_text("  a   b\t c "), "a b c")
        self.assertEqual(gen.clean_text(None), "")


class TestSourceFromText(unittest.TestCase):
    def test_first_matching_label_wins_in_priority_order(self):
        self.assertEqual(gen.source_from_text("Drop: X Vendor: Y", "0"), "drop")
        self.assertEqual(gen.source_from_text("Vendor: Y Zone: Z", "2"), "vendor")
        self.assertEqual(gen.source_from_text("Quest: Q Zone: Z", "1"), "quest")
        self.assertEqual(gen.source_from_text("Profession: Engineering", "3"), "profession")
        self.assertEqual(gen.source_from_text("World Event: Brewfest", "6"), "worldevent")
        self.assertEqual(gen.source_from_text("Faction: Dragonscale Expedition", "2"), "vendor")

    def test_enum_6_without_a_label_is_world_event(self):
        self.assertEqual(gen.source_from_text("Zone: Everywhere", "6"), "worldevent")

    def test_unlabelled_resolved_mount_falls_back_to_zonedrop(self):
        self.assertEqual(gen.source_from_text("Zone: Azsuna", "10"), "zonedrop")


class TestFactionFromText(unittest.TestCase):
    def test_reads_the_parenthetical_faction_tag(self):
        self.assertEqual(gen.faction_from_text("Vendor: Lovely Merchant (Alliance)"), "1")
        self.assertEqual(gen.faction_from_text("Vendor: Big Love Rocket (Horde)"), "0")
        self.assertIsNone(gen.faction_from_text("Vendor: Neutral Guy"))


class TestIsGlobalText(unittest.TestCase):
    def test_global_source_enums_are_global(self):
        for enum in gen.GLOBAL_SOURCE_ENUMS:
            self.assertTrue(gen.is_global_text("", enum))

    def test_text_patterns_are_global(self):
        self.assertTrue(gen.is_global_text("Class: Warlock", "1"))
        self.assertTrue(gen.is_global_text("Trading Post", "-1"))

    def test_plain_zone_drop_is_not_global(self):
        self.assertFalse(gen.is_global_text("Drop: Some Rare Zone: Azsuna", "0"))


class TestZoneNamesFromText(unittest.TestCase):
    def test_reads_a_single_zone(self):
        self.assertEqual(gen.zone_names_from_text("Vendor: X Zone: Wetlands"), ["wetlands"])

    def test_reads_location_as_an_alias_for_zone(self):
        self.assertEqual(gen.zone_names_from_text("Drop: Boss Location: Stratholme"), ["stratholme"])

    def test_splits_a_comma_list_and_drops_parentheticals(self):
        got = gen.zone_names_from_text("Zone: Durotar, Eversong Woods (Burning Crusade), Mulgore")
        self.assertEqual(got, ["durotar", "eversong woods", "mulgore"])

    def test_stops_at_the_next_label(self):
        self.assertEqual(gen.zone_names_from_text("Zone: Nazjatar Cost: 5000"), ["nazjatar"])


class TestZonesForNameList(unittest.TestCase):
    def data(self):
        return make_data(uimap_by_name={
            "durotar": ["1"],
            "mulgore": ["7"],
            "eversong woods": ["94", "1267", "2395"],
            "torghast": [str(n) for n in range(100, 140)],  # collides with 40 sub-maps
        })

    def test_returns_every_variant_id_for_each_matched_name(self):
        self.assertEqual(self.data().zones_for_name_list(["eversong woods"]), {"94", "1267", "2395"})

    def test_unknown_names_are_ignored(self):
        self.assertEqual(self.data().zones_for_name_list(["durotar", "nowhere"]), {"1"})

    def test_too_many_distinct_zones_is_an_everywhere_vendor(self):
        many = [f"cap{i}" for i in range(gen.MAX_TEXT_ZONES + 1)]
        data = self.data()
        for i, name in enumerate(many):
            data.uimap_by_name[name] = [str(9000 + i)]
        self.assertEqual(data.zones_for_name_list(many), set())

    def test_a_name_that_explodes_into_many_submaps_is_dropped(self):
        self.assertEqual(self.data().zones_for_name_list(["torghast"]), set())


class TestNormalizeRegion(unittest.TestCase):
    def row(self, **over):
        base = {
            "Region[0]": "0", "Region[1]": "0", "Region[2]": "0",
            "Region[3]": "100", "Region[4]": "100", "Region[5]": "0",
            "UiMin[0]": "0", "UiMin[1]": "0", "UiMax[0]": "1", "UiMax[1]": "1",
        }
        base.update(over)
        return base

    def test_parses_a_well_formed_row(self):
        self.assertEqual(
            gen.normalize_region(self.row()),
            (0.0, 0.0, 100.0, 100.0, 0.0, 0.0, 1.0, 1.0),
        )

    def test_degenerate_box_is_rejected(self):
        self.assertIsNone(gen.normalize_region(self.row(**{"Region[3]": "0"})))

    def test_missing_column_is_rejected(self):
        row = self.row()
        del row["Region[0]"]
        self.assertIsNone(gen.normalize_region(row))


class TestInstanceMounts(unittest.TestCase):
    def data(self):
        return make_data(
            mount_by_item={"item-onyxia": "m1"},
            encounter_items=[
                {"ItemID": "item-onyxia", "JournalEncounterID": "e1"},
                {"ItemID": "item-nomount", "JournalEncounterID": "e1"},
            ],
            encounters={"e1": {"JournalInstanceID": "i1"}},
            instances={"i1": {"MapID": "map-raid"}},
            map_zone={"map-raid": "2437"},
            map_instance_type={"map-raid": "2"},
        )

    def test_joins_loot_item_to_boss_to_instance_zone(self):
        self.assertEqual(self.data().instance_mounts(), {"m1": ("2437", "raid")})

    def test_dungeon_instance_type_yields_dungeon_subcat(self):
        d = self.data()
        d.map_instance_type["map-raid"] = "1"
        self.assertEqual(d.instance_mounts()["m1"], ("2437", "dungeon"))

    def test_instance_with_no_ui_map_is_skipped(self):
        d = self.data()
        d.map_zone = {}
        self.assertEqual(d.instance_mounts(), {})


class TestBuild(unittest.TestCase):
    """End-to-end over the pure build(), with a hand-built Data."""

    def data(self):
        return make_data(
            mounts={
                "10": {
                    "ID": "10", "SourceTypeEnum": "2",
                    "SourceText_lang": "|cFFFFD200Vendor: |rKatie Zone: Stormwind City Cost: 1",
                },
                "11": {
                    "ID": "11", "SourceTypeEnum": "0",
                    "SourceText_lang": "Drop: Attumen Location: Karazhan",
                },
                "12": {
                    "ID": "12", "SourceTypeEnum": "1",
                    "SourceText_lang": "Class: Warlock",
                },
                "13": {
                    "ID": "13", "SourceTypeEnum": "9",
                    "SourceText_lang": "In-Game Shop",
                },
            },
            uimap={"84": {"Type": "6"}, "350": {"Type": "3"}},
            uimap_by_name={"stormwind city": ["84"]},
            item_by_mount={"10": "i_v"},
            item_expansion={"i_v": "8"},
        )

    def build(self):
        d = self.data()
        d.instance_mounts = lambda: {"11": ("350", "raid")}
        return d, gen.build(d)

    def test_vendor_mount_lands_in_its_named_zone(self):
        _, (zones, source, subcat, expansion, faction, global_ids) = self.build()
        self.assertIn("10", zones["84"])
        self.assertEqual(source["10"], "vendor")
        self.assertEqual(expansion["10"], "8")

    def test_instance_mount_uses_the_loot_table_zone_not_the_text(self):
        _, (zones, source, subcat, *_rest) = self.build()
        self.assertIn("11", zones["350"])
        self.assertEqual(source["11"], "instance")
        self.assertEqual(subcat["11"], "raid")

    def test_class_and_shop_mounts_go_global(self):
        _, (zones, source, subcat, expansion, faction, global_ids) = self.build()
        self.assertIn("12", global_ids)
        self.assertIn("13", global_ids)
        for zone_ids in zones.values():
            self.assertNotIn("12", zone_ids)

    def test_global_list_is_sorted(self):
        _, (*_head, global_ids) = self.build()
        self.assertEqual(global_ids, sorted(global_ids, key=int))


class TestSanity(unittest.TestCase):
    HEALTHY_GLOBALS = [str(n) for n in range(gen.MIN_GLOBAL + 50)]

    def healthy_zones(self):
        return {str(i): [str(n) for n in range(6)] for i in range(gen.MIN_ZONES + 20)}

    def test_healthy_dataset_has_no_problems(self):
        self.assertEqual(
            gen.check_sanity(self.healthy_zones(), self.HEALTHY_GLOBALS, "/no/such/file"), []
        )

    def test_too_few_zones_is_flagged(self):
        problems = gen.check_sanity({"1": ["1"]}, self.HEALTHY_GLOBALS, "/no/such/file")
        self.assertTrue(any("zones mapped" in p for p in problems))

    def test_too_few_references_is_flagged(self):
        zones = {str(i): ["1"] for i in range(gen.MIN_ZONES + 20)}
        problems = gen.check_sanity(zones, self.HEALTHY_GLOBALS, "/no/such/file")
        self.assertTrue(any("mount references" in p for p in problems))

    def test_too_few_globals_is_flagged(self):
        problems = gen.check_sanity(self.healthy_zones(), ["1", "2"], "/no/such/file")
        self.assertTrue(any("global mounts" in p for p in problems))

    def test_reference_count_swing_versus_previous_file_is_flagged(self):
        with tempfile.NamedTemporaryFile("w", suffix=".lua", delete=False, encoding="utf-8") as handle:
            handle.write(gen.render_lua(
                {str(i): [str(n) for n in range(20)] for i in range(gen.MIN_ZONES + 20)},
                {}, {}, {}, {}, self.HEALTHY_GLOBALS, "12.1.0.1",
            ))
            path = handle.name
        try:
            problems = gen.check_sanity(self.healthy_zones(), self.HEALTHY_GLOBALS, path)
            self.assertTrue(any("far from the previous file" in p for p in problems))
        finally:
            os.unlink(path)


class TestRenderLua(unittest.TestCase):
    def rendered(self):
        return gen.render_lua(
            zones={"1970": ["100", "101"], "2022": ["101"]},
            source={"100": "vendor", "101": "instance"},
            subcat={"101": "raid"},
            expansion={"100": "9"},
            faction={"101": "1"},
            global_ids=["500", "501"],
            build_id="12.1.0.69497",
        )

    def test_previous_ref_count_reads_the_zones_block(self):
        self.assertEqual(gen._previous_ref_count(self.rendered()), 3)

    def test_output_parses_as_lua_with_the_expected_shape(self):
        try:
            import lupa
        except ImportError:
            self.skipTest("lupa not installed")
        lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        addon = lua.table()
        lua.eval("function(s, a) return assert(load(s))('T', a) end")(self.rendered(), addon)
        md = addon["MountData"]
        self.assertEqual(md["build"], "12.1.0.69497")
        self.assertEqual(list(md["zones"][1970].values()), [100, 101])
        self.assertEqual(md["source"][101], "instance")
        self.assertEqual(md["subcat"][101], "raid")
        self.assertEqual(md["expansion"][100], 9)
        self.assertEqual(md["faction"][101], 1)
        self.assertEqual(list(md["global"].values()), [500, 501])


class TestFullGeneratorFixture(unittest.TestCase):
    """Data.__init__ + build + render against a tiny on-disk CSV cache."""

    CSVS = {
        "Mount": "Name_lang,SourceText_lang,ID,MountTypeID,Flags,SourceTypeEnum,SourceSpellID\n"
                 "Swift Stallion,Vendor: Bob Zone: Elwynn Forest Cost: 1,10,230,0,2,900\n"
                 "Raid Drake,Drop: Big Boss,11,230,0,1,901\n"
                 "Warlock Steed,Class: Warlock,12,230,0,1,902\n",
        "SpellName": "ID,Name_lang\n900,Swift Stallion\n901,Raid Drake\n902,Warlock Steed\n",
        "ItemEffect": "ID,LegacySlotIndex,TriggerType,Charges,CoolDownMSec,CategoryCoolDownMSec,"
                      "SpellCategoryID,SpellID,ChrSpecializationID,PlayerConditionID\n"
                      "70,0,6,0,0,0,0,900,0,0\n71,0,6,0,0,0,0,901,0,0\n",
        "ItemXItemEffect": "ID,ItemEffectID,ItemID\n1,70,500\n2,71,501\n",
        "ItemSparse": "ID,Description_lang,Display_lang,ExpansionID\n500,,Swift Stallion,9\n501,,Raid Drake,8\n",
        "JournalEncounterItem": "ID,JournalEncounterID,ItemID,FactionMask,Flags,DifficultyMask\n"
                                "1,900,501,0,0,0\n",
        "JournalEncounter": "Name_lang,Description_lang,Map[0],Map[1],ID,JournalInstanceID,"
                            "DungeonEncounterID,OrderIndex,FirstSectionID,UiMapID,MapDisplayConditionID,Flags,DifficultyMask\n"
                            "Big Boss,,0,0,900,800,0,0,0,0,0,0,0\n",
        "JournalInstance": "ID,Name_lang,Description_lang,MapID,BackgroundFileDataID,ButtonFileDataID,"
                           "ButtonSmallFileDataID,LoreFileDataID,Flags,AreaID,CovenantID\n"
                           "800,Test Raid,,700,0,0,0,0,0,0,0\n",
        "Map": "ID,Directory,MapName_lang,MapDescription0_lang,MapDescription1_lang,PvpShortDescription_lang,"
               "PvpLongDescription_lang,Corpse[0],Corpse[1],MapType,InstanceType,ExpansionID,AreaTableID\n"
               "700,TestRaid,Test Raid,,,,,0,0,3,2,9,0\n",
        "UiMap": "Name_lang,ID,ParentUiMapID,Flags,System,Type\n"
                 "Elwynn Forest,37,13,0,0,3\nTest Raid,2000,0,0,0,4\n",
        "UiMapAssignment": "UiMin[0],UiMin[1],UiMax[0],UiMax[1],Region[0],Region[1],Region[2],Region[3],"
                           "Region[4],Region[5],ID,UiMapID,OrderIndex,MapID,AreaID\n"
                           "0,0,1,1,0,0,0,100,100,0,1,2000,0,700,0\n",
    }

    def test_builds_and_renders_from_csv(self):
        with tempfile.TemporaryDirectory() as tmp:
            build_dir = os.path.join(tmp, "12.1.0.1")
            os.makedirs(build_dir)
            for name, body in self.CSVS.items():
                with open(os.path.join(build_dir, f"{name}.csv"), "w", encoding="utf-8", newline="") as fh:
                    fh.write(body)
            data = gen.Data("12.1.0.1", tmp, "enUS")
            zones, source, subcat, expansion, faction, global_ids = gen.build(data)

        self.assertIn("37", zones)               # Elwynn Forest, from the vendor text
        self.assertIn("10", zones["37"])
        self.assertEqual(source["10"], "vendor")
        self.assertEqual(source["11"], "instance")   # Raid Drake, from the loot table
        self.assertEqual(subcat["11"], "raid")
        self.assertIn("2000", zones)                 # the raid's UI map
        self.assertIn("12", global_ids)              # the class mount
        self.assertEqual(expansion["10"], "9")

        text = gen.render_lua(zones, source, subcat, expansion, faction, global_ids, "12.1.0.1")
        self.assertIn("addon.MountData", text)
        self.assertIn(textwrap.dedent("    global = {").strip(), text)


if __name__ == "__main__":
    unittest.main()
