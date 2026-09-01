#!/usr/bin/env python3
"""Generate Mount_Tracker_Local_Zones/MountData.lua from datamined game data.

No WoW API maps a collectable mount to the zone you get it in, so this builds the
mapping offline from wago.tools DB2 exports:

  1. Instance drops  - JournalEncounterItem.ItemID -> the item's teach-spell
     (ItemXItemEffect -> ItemEffect.SpellID) -> Mount.SourceSpellID; then
     JournalEncounter.JournalInstanceID -> JournalInstance.MapID -> UiMapAssignment
     -> uiMapID. source = "instance", subcat "dungeon" / "raid" from Map.InstanceType.
  2. SourceText parse - Mount.SourceText_lang carries structured labels
     ("Zone: X", "Location: X", "Vendor: N", "Drop: M", "Quest: Q", "Faction: F",
     "Profession: P", "World Event: E"). The zone name(s) after Zone:/Location: are
     matched against zone-type UiMap.Name_lang; the label words pick the source.
  3. Expansion - from the teaching item's ItemSparse.ExpansionID.
  4. Faction - an "(Alliance)" / "(Horde)" tag in SourceText.
  5. Everything still unresolved, plus class / racial / PvP / trading-card /
     promotion / shop / trading-post patterns -> the flat `global` list, which the
     addon shows under a "Global" divider when the option is on.

Hand-tuning goes in Overrides.lua (merged at runtime); this file is never edited
by hand. Writes nothing if a sanity check fails.

Usage:
  python tools/generate_mount_zones.py [--build 12.1.0.xxxxx] [--major 12]
                                       [--cache DIR] [--out PATH] [--locale enUS]
"""

from __future__ import annotations

import argparse
import csv
import datetime
import html
import json
import os
import re
import sys
import urllib.request

WAGO = "https://wago.tools"
USER_AGENT = "mount-local-tracker generator (github.com/CesttPlays/mount-local-tracker)"
TABLES = [
    "Mount",
    "SpellName",
    "ItemEffect",
    "ItemXItemEffect",
    "ItemSparse",
    "JournalEncounterItem",
    "JournalEncounter",
    "JournalInstance",
    "Map",
    "UiMap",
    "UiMapAssignment",
    "Achievement",
    "Achievement_Category",
    "Criteria",
    "CriteriaTree",
]

# UiMap.Type: 2 Continent, 3 Zone, 4 Dungeon, 5 Micro, 6 Orphan (cities / BGs).
# "Zone: X" text is matched against real zones + cities + battlegrounds only;
# dungeons and raids come from the instance loot-table pass, not by name.
UIMAP_NAME_TYPES = {"3", "6"}
# Preferred when an instance MapID resolves to several UI maps.
UIMAP_ZONE_TYPES = {"3", "4", "6"}

# Map.InstanceType -> mount subcategory for the instance pass (1 party, 2 raid).
INSTANCE_SUBCAT = {"1": "dungeon", "2": "raid"}

# Achievement.Criteria "Type" 8 = "complete another achievement" (meta rollup).
CRITERIA_COMPLETE_ACHIEVEMENT = "8"
# How deep to follow type-8 meta criteria. Classic "Glory of the <Raid> Raider"
# is meta -> per-boss feat (depth 2); modern raid metas carry Instance_ID direct.
ACHIEVEMENT_META_DEPTH = 2
# An achievement whose category chain reaches one of these roots is never
# zone-local, even when it resolves to a single instance: 1 Statistics,
# 81 Feats of Strength, 95 Player vs. Player, 155 World Events, 201 Reputation.
ACHIEVEMENT_GLOBAL_CATEGORY_ROOTS = {"1", "81", "95", "155", "201"}

# A SourceText that names more than this many distinct zones is an
# everywhere-vendor (holiday merchants in every capital) -> treat as global.
MAX_TEXT_ZONES = 6
# ... or that resolves to more UI-map ids than this: a name like "Torghast"
# collides with dozens of per-wing sub-maps. Real zones top out around 9 variants.
MAX_TEXT_ZONE_IDS = 15

# SourceText label -> source type. First hit wins, in this order.
SOURCE_LABELS = [
    ("Drop:", "drop"),
    ("World Event:", "worldevent"),
    ("Event:", "worldevent"),
    ("Profession:", "profession"),
    ("Quest:", "quest"),
    ("Vendor:", "vendor"),
    ("Faction:", "vendor"),
]

# Mount.SourceTypeEnum values that are never zone-local (class, PvP, TCG,
# promotion, trading post / shop). Used only to route leftovers to `global`.
GLOBAL_SOURCE_ENUMS = {"5", "7", "8", "9", "11"}

# SourceText fragments that mean "not a zone drop" even without an enum.
GLOBAL_TEXT_PATTERNS = [
    "Class:", "Trading Post", "In-Game Shop", "Trading Card Game", "Recruit-a-Friend",
    "Promotion:", "Gladiator:", "Remix", "Feature:", "Shop",
]

MONEY_ICON = "UI-GOLDICON"


# --------------------------------------------------------------------------- io

def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=300) as response:
        return response.read()


def discover_build(major: str) -> str:
    page = fetch(f"{WAGO}/db2").decode("utf-8", "replace")
    match = re.search(r'data-page="([^"]+)"', page)
    if not match:
        raise RuntimeError("could not find the build list on wago.tools")
    payload = json.loads(html.unescape(match.group(1)))
    for version in payload["props"]["versions"]:  # newest first
        if version.split(".")[0] == major:
            return version
    raise RuntimeError(f"no {major}.x build found on wago.tools")


def load_table(table: str, build: str, cache_dir: str, locale: str) -> list[dict]:
    path = os.path.join(cache_dir, build, f"{table}.csv")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        data = fetch(f"{WAGO}/db2/{table}/csv?build={build}&locale={locale}")
        with open(path, "wb") as handle:
            handle.write(data)
    with open(path, encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


# --------------------------------------------------------------- pure transforms

_ESCAPE_RE = re.compile(r"\|c[0-9A-Fa-f]{8}|\|r|\|T.*?\|t|\|H.*?\|h|\|h")


def clean_text(text: str) -> str:
    """Strip WoW colour / texture / hyperlink escapes and collapse whitespace."""
    text = _ESCAPE_RE.sub("", text or "")
    text = text.replace("|n", " ")
    return re.sub(r"\s+", " ", text).strip()


def source_from_text(text: str, enum: str) -> str:
    for needle, source in SOURCE_LABELS:
        if needle in text:
            return source
    if enum == "6":
        return "worldevent"
    return "zonedrop"


def faction_from_text(text: str) -> str | None:
    low = text.lower()
    if "(alliance)" in low:
        return "1"
    if "(horde)" in low:
        return "0"
    return None


def is_global_text(text: str, enum: str) -> bool:
    if enum in GLOBAL_SOURCE_ENUMS:
        return True
    return any(p in text for p in GLOBAL_TEXT_PATTERNS)


def zone_names_from_text(text: str) -> list[str]:
    """The zone name(s) after a 'Zone:' or 'Location:' label, lowercased.

    The value runs to the next 'Label:' token or end of string, and may be a
    comma-separated list ('Durotar, Mulgore, Tirisfal Glades'). A parenthetical
    like '(Burning Crusade)' is dropped.
    """
    names: list[str] = []
    # The value runs until the next "<Label>:" token -- a single capitalised
    # word (Cost, Drop, Vendor, ...) or the two-word "World Event".
    for match in re.finditer(r"(?:Zone|Location):\s*(.+?)(?=\s+(?:World Event|[A-Z][a-z]+):|$)", text):
        chunk = re.sub(r"\([^)]*\)", "", match.group(1))
        for part in chunk.split(","):
            name = part.strip().lower()
            if name:
                names.append(name)
    return names


_ACHIEVEMENT_LABEL_RE = re.compile(
    r"Achievement:\s*(.+?)(?=\s+(?:World Event|[A-Z][a-z]+):|$)"
)


def normalize_achievement_title(text: str) -> str:
    """Lowercase, fold every non-alphanumeric run to a space, collapse whitespace.

    Lets the lightly-mangled SourceText label ("For The Horde!") match the real
    Achievement.Title_lang ("For the Horde!") without a false match on case or a
    stray "!". Applied to both sides of the name-fallback link, so a difficulty
    suffix ("... (25 player)") still reads as a distinct title and cannot
    collapse into an ambiguous match.
    """
    text = re.sub(r"[^a-z0-9 ]+", " ", clean_text(text).lower())
    return re.sub(r"\s+", " ", text).strip()


def achievement_title_from_text(text: str) -> str | None:
    """The normalized achievement name after an 'Achievement:' label, or None."""
    match = _ACHIEVEMENT_LABEL_RE.search(text)
    if not match:
        return None
    return normalize_achievement_title(match.group(1)) or None


def normalize_region(row: dict) -> tuple[float, ...] | None:
    try:
        min_x, min_y, _, max_x, max_y, _ = (float(row[f"Region[{i}]"]) for i in range(6))
    except (KeyError, ValueError):
        return None
    if max_x == min_x or max_y == min_y:
        return None
    return (
        min_x, min_y, max_x, max_y,
        float(row["UiMin[0]"]), float(row["UiMin[1]"]),
        float(row["UiMax[0]"]), float(row["UiMax[1]"]),
    )


# ------------------------------------------------------------------- data model

class Data:
    def __init__(self, build: str, cache_dir: str, locale: str):
        self.build = build
        tables = {name: load_table(name, build, cache_dir, locale) for name in TABLES}

        self.mounts = {row["ID"]: row for row in tables["Mount"]}

        # SourceSpellID -> mountID  (the aura spell a mount item teaches)
        self.mount_by_spell = {
            row["SourceSpellID"]: row["ID"]
            for row in tables["Mount"]
            if row["SourceSpellID"] not in ("0", "")
        }

        spell_by_effect = {row["ID"]: row["SpellID"] for row in tables["ItemEffect"]}
        # itemID -> mountID, via any of the item's teach-spells
        self.mount_by_item: dict[str, str] = {}
        for row in tables["ItemXItemEffect"]:
            spell = spell_by_effect.get(row["ItemEffectID"])
            mount_id = self.mount_by_spell.get(spell) if spell else None
            if mount_id:
                self.mount_by_item.setdefault(row["ItemID"], mount_id)

        self.item_expansion = {
            row["ID"]: row["ExpansionID"]
            for row in tables["ItemSparse"]
            if row.get("ExpansionID") not in (None, "", "0")
        }
        # mountID -> teaching itemID (first seen), for the expansion lookup
        self.item_by_mount: dict[str, str] = {}
        for item_id, mount_id in self.mount_by_item.items():
            self.item_by_mount.setdefault(mount_id, item_id)

        self.uimap = {row["ID"]: row for row in tables["UiMap"]}
        # name -> every zone/city/BG UI-map id with that name. WoW keeps a fresh
        # UI map per expansion / phase ("Eversong Woods" is 5 ids); carrying all
        # of them means the lookup hits whichever variant the player is on.
        self.uimap_by_name: dict[str, list[str]] = {}
        for row in tables["UiMap"]:
            if row["Type"] in UIMAP_NAME_TYPES:
                name = clean_text(row["Name_lang"]).lower()
                if name:
                    self.uimap_by_name.setdefault(name, []).append(row["ID"])

        self.map_instance_type = {row["ID"]: row["InstanceType"] for row in tables["Map"]}
        self.map_expansion = {row["ID"]: row["ExpansionID"] for row in tables["Map"]}

        # instance Map.ID -> uiMapID (prefer a zone/dungeon-type UI map, low OrderIndex)
        map_assign: dict[str, list[tuple[str, int]]] = {}
        for row in tables["UiMapAssignment"]:
            if row["MapID"] in ("0", ""):
                continue
            map_assign.setdefault(row["MapID"], []).append(
                (row["UiMapID"], int(row["OrderIndex"] or "0"))
            )
        self.map_zone: dict[str, str] = {}
        for map_id, entries in map_assign.items():
            entries.sort(key=lambda e: (
                self.uimap.get(e[0], {}).get("Type") not in UIMAP_ZONE_TYPES,
                e[1],
            ))
            self.map_zone[map_id] = entries[0][0]

        self.encounters = {row["ID"]: row for row in tables["JournalEncounter"]}
        self.instances = {row["ID"]: row for row in tables["JournalInstance"]}
        self.encounter_items = tables["JournalEncounterItem"]

        # -- achievement-reward resolution ------------------------------------
        self.achievements = {row["ID"]: row for row in tables["Achievement"]}
        self.ach_categories = {row["ID"]: row for row in tables["Achievement_Category"]}
        self.criteria = {row["ID"]: row for row in tables["Criteria"]}
        self.criteria_tree: dict[str, dict] = {}
        self.criteria_tree_children: dict[str, list[str]] = {}
        for row in tables["CriteriaTree"]:
            self.criteria_tree[row["ID"]] = row
            self.criteria_tree_children.setdefault(row["Parent"], []).append(row["ID"])

        # normalized title -> {achievementID}  and  reward itemID -> {achievementID}
        self.achievement_by_title: dict[str, set[str]] = {}
        self.achievement_by_reward_item: dict[str, set[str]] = {}
        for row in tables["Achievement"]:
            title = normalize_achievement_title(row["Title_lang"])
            if title:
                self.achievement_by_title.setdefault(title, set()).add(row["ID"])
            reward_item = row.get("RewardItemID") or "0"
            if reward_item != "0":
                self.achievement_by_reward_item.setdefault(reward_item, set()).add(row["ID"])

    # -- instance pass --------------------------------------------------------

    def instance_mounts(self) -> dict[str, tuple[str, str]]:
        """mountID -> (uiMapID, subcat) for mounts that drop from a journal boss."""
        out: dict[str, tuple[str, str]] = {}
        for row in self.encounter_items:
            mount_id = self.mount_by_item.get(row["ItemID"])
            if not mount_id:
                continue
            encounter = self.encounters.get(row["JournalEncounterID"])
            if not encounter:
                continue
            instance = self.instances.get(encounter["JournalInstanceID"])
            if not instance:
                continue
            uimap_id = self.map_zone.get(instance["MapID"])
            if not uimap_id:
                continue
            subcat = INSTANCE_SUBCAT.get(self.map_instance_type.get(instance["MapID"], ""), "dungeon")
            out.setdefault(mount_id, (uimap_id, subcat))
        return out

    # -- helpers ------------------------------------------------------------

    def expansion_for(self, mount_id: str) -> str | None:
        item_id = self.item_by_mount.get(mount_id)
        return self.item_expansion.get(item_id) if item_id else None

    def zones_for_name_list(self, names: list[str]) -> set[str]:
        matched = {name: self.uimap_by_name[name] for name in names if name in self.uimap_by_name}
        if len(matched) > MAX_TEXT_ZONES:
            return set()  # everywhere-vendor -> not zone-local
        zones: set[str] = set()
        for ids in matched.values():
            zones.update(ids)
        if len(zones) > MAX_TEXT_ZONE_IDS:
            return set()  # name collided with many sub-maps ("Torghast")
        return zones

    # -- achievement pass -------------------------------------------------

    def _achievement_in_global_category(self, category_id: str) -> bool:
        """True if the achievement's category chain hits a never-zone-local root."""
        seen: set[str] = set()
        current = category_id
        while current and current not in ("-1", "") and current not in seen:
            if current in ACHIEVEMENT_GLOBAL_CATEGORY_ROOTS:
                return True
            seen.add(current)
            node = self.ach_categories.get(current)
            if not node:
                return False
            current = node["Parent"]
        return False

    def _criteria_leaves(self, root_tree_id: str) -> list[tuple[str, str]]:
        """[(criteriaType, asset), ...] for the leaves under a criteria tree."""
        if root_tree_id in ("0", ""):
            return []  # no tree -- "0" is not the forest root
        out: list[tuple[str, str]] = []
        stack = [root_tree_id]
        seen: set[str] = set()
        while stack:
            tree_id = stack.pop()
            if tree_id in seen:
                continue
            seen.add(tree_id)
            children = self.criteria_tree_children.get(tree_id)
            if children:
                stack.extend(children)
                continue
            node = self.criteria_tree.get(tree_id)
            if not node:
                continue
            criterion = self.criteria.get(node["CriteriaID"])
            if criterion and node["CriteriaID"] != "0":
                out.append((criterion["Type"], criterion["Asset"]))
        return out

    def achievement_for_mount(self, mount_id: str) -> str | None:
        """The achievement id a mount's 'Achievement:' label refers to, or None.

        RewardItemID FK first (via the teaching item); an exact
        normalized-title match is the fallback, used only when unambiguous.
        Anything ambiguous or unlabelled -> None (the mount stays as it was).
        """
        row = self.mounts.get(mount_id)
        if not row:
            return None
        title = achievement_title_from_text(clean_text(row["SourceText_lang"]))
        if title is None:
            return None
        item_id = self.item_by_mount.get(mount_id)
        fk_hits = self.achievement_by_reward_item.get(item_id or "", set())
        name_hits = self.achievement_by_title.get(title, set())
        if len(fk_hits) == 1:
            return next(iter(fk_hits))
        if len(fk_hits) > 1:
            both = fk_hits & name_hits
            return next(iter(both)) if len(both) == 1 else None
        if len(name_hits) == 1:
            return next(iter(name_hits))
        return None

    def zones_for_achievement(
        self, achievement_id: str, depth: int = ACHIEVEMENT_META_DEPTH,
        stack: tuple[str, ...] = (),
    ) -> dict[str, str]:
        """uiMapID -> the instance Map.ID that resolved it.

        Achievement.Instance_ID -> map_zone, recursing type-8 (complete
        achievement) meta criteria so classic "Glory of the <Raid> Raider"
        metas resolve through their per-boss feat achievements.
        """
        if achievement_id in stack:
            return {}
        row = self.achievements.get(achievement_id)
        if not row:
            return {}
        out: dict[str, str] = {}
        instance_id = row.get("Instance_ID", "-1")
        if instance_id not in ("-1", "0", ""):
            mapped = self.map_zone.get(instance_id)
            if mapped:
                out.setdefault(mapped, instance_id)
        if depth > 0:
            for criteria_type, asset in self._criteria_leaves(row.get("Criteria_tree", "")):
                if criteria_type == CRITERIA_COMPLETE_ACHIEVEMENT:
                    for zone, map_id in self.zones_for_achievement(
                        asset, depth - 1, stack + (achievement_id,)
                    ).items():
                        out.setdefault(zone, map_id)
        return out


# ------------------------------------------------------------------- the build

def build(data: Data):
    zones: dict[str, set[str]] = {}
    source: dict[str, str] = {}
    subcat: dict[str, str] = {}
    expansion: dict[str, str] = {}
    faction: dict[str, str] = {}
    achievement_ids: dict[str, str] = {}
    global_ids: set[str] = set()

    instance_map = data.instance_mounts()

    for mount_id, row in data.mounts.items():
        text = clean_text(row["SourceText_lang"])
        enum = row["SourceTypeEnum"]

        expac = data.expansion_for(mount_id)
        if expac:
            expansion[mount_id] = expac
        fac = faction_from_text(text)
        if fac:
            faction[mount_id] = fac

        # Record the achievement link for every confidently-linked mount, zoned
        # or not -- it lights up the addon's `achievement_gated` obtainability
        # state ("Achievement needed - <name>").
        achievement_id = data.achievement_for_mount(mount_id)
        if achievement_id:
            achievement_ids[mount_id] = achievement_id

        resolved: set[str] = set()

        if mount_id in instance_map:
            # A journal boss drop is precise; don't dilute it with a loose
            # SourceText name match ("Location: Karazhan" hits many sub-maps).
            uimap_id, sub = instance_map[mount_id]
            resolved.add(uimap_id)
            source[mount_id] = "instance"
            subcat[mount_id] = sub
        else:
            resolved |= data.zones_for_name_list(zone_names_from_text(text))

        resolved = {z for z in resolved if z in data.uimap}

        # Achievement -> zone, for a labelled mount that text / loot left flat.
        # Only a single-instance resolution is trusted; multi-zone metas ("Glory
        # of the <Expansion> Hero") and global-category achievements (PvP /
        # world-event / feats of strength) stay global.
        if not resolved and achievement_id and not data._achievement_in_global_category(
            data.achievements[achievement_id].get("Category", "")
        ):
            ach_zones = {
                zone: map_id
                for zone, map_id in data.zones_for_achievement(achievement_id).items()
                if zone in data.uimap
            }
            if len(ach_zones) == 1:
                zone_id, map_id = next(iter(ach_zones.items()))
                resolved.add(zone_id)
                source[mount_id] = "achievement"
                subcat[mount_id] = INSTANCE_SUBCAT.get(
                    data.map_instance_type.get(map_id, ""), "raid"
                )

        if not resolved:
            global_ids.add(mount_id)
            continue

        if mount_id not in source:
            source[mount_id] = source_from_text(text, enum)
        for zone in resolved:
            zones.setdefault(zone, set()).add(mount_id)

    # Prefer a real home zone: a mount that resolved to a zone is not also global.
    sorted_zones = {
        zone: sorted(ids, key=int)
        for zone, ids in sorted(zones.items(), key=lambda kv: int(kv[0]))
    }
    return (
        sorted_zones,
        source,
        subcat,
        expansion,
        faction,
        achievement_ids,
        sorted(global_ids, key=int),
    )


# ---------------------------------------------------------------- lua rendering

def _lua_map(name: str, comment: str, pairs, fmt) -> list[str]:
    lines = [f"    -- {comment}", f"    {name} = {{"]
    for key in pairs:
        lines.append(f"        {fmt(key)}")
    lines.append("    },")
    lines.append("")
    return lines


def render_lua(zones, source, subcat, expansion, faction, achievement_ids, global_ids, build_id: str) -> str:
    lines = [
        "local _, addon = ...",
        "",
        "-- GENERATED by tools/generate_mount_zones.py -- do not edit by hand.",
        "-- Hand-tuning goes in Overrides.lua (merged at runtime).",
        "",
        "addon.MountData = {",
        f'    build = "{build_id}",',
        f'    updated = "{datetime.date.today().isoformat()}",',
        "",
        "    -- [uiMapID] = { mountID, ... }",
        "    zones = {",
    ]
    for zone, ids in zones.items():
        lines.append(f"        [{zone}] = {{ {', '.join(ids)} }},")
    lines.append("    },")
    lines.append("")

    lines += _lua_map(
        "source", '[mountID] = "instance"|"drop"|"vendor"|"quest"|"zonedrop"|"worldevent"|"profession"|"achievement"',
        sorted(source, key=int), lambda m: f'[{m}] = "{source[m]}",',
    )
    lines += _lua_map(
        "subcat", '[mountID] = "dungeon" | "raid" | "rare" | ...',
        sorted(subcat, key=int), lambda m: f'[{m}] = "{subcat[m]}",',
    )
    lines += _lua_map(
        "expansion", "[mountID] = expansionID",
        sorted(expansion, key=int), lambda m: f"[{m}] = {expansion[m]},",
    )
    lines += _lua_map(
        "faction", "[mountID] = 0 (Horde) | 1 (Alliance)",
        sorted(faction, key=int), lambda m: f"[{m}] = {faction[m]},",
    )

    lines += _lua_map(
        "achievementID",
        "[mountID] = achievementID  (mount is a reward for finishing that achievement)",
        sorted(achievement_ids, key=int),
        lambda m: f"[{m}] = {achievement_ids[m]},",
    )

    lines.append("    -- optional / obtainability inputs -- generator leaves these for Overrides.lua")
    lines.append("    points = {},")
    lines.append("    repFaction = {},")
    lines.append("    vendor = {},")
    lines.append("")

    lines.append("    -- mounts with no single home zone (class / racial / PvP / TCG / shop / promo)")
    lines.append("    global = {")
    for start in range(0, len(global_ids), 15):
        chunk = global_ids[start:start + 15]
        lines.append("        " + ", ".join(str(i) for i in chunk) + ",")
    lines.append("    },")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


# --------------------------------------------------------------------- sanity

MIN_ZONES = 40
MIN_REFS = 250
MIN_GLOBAL = 150


def _previous_ref_count(text: str) -> int:
    match = re.search(r"\n    zones = \{\n(.*?)\n    \},\n", text, flags=re.S)
    if not match:
        return 0
    body = match.group(1)
    return len(re.findall(r"\d+", body)) - len(re.findall(r"\[\d+\]", body))


def check_sanity(zones: dict[str, list[str]], global_ids, out_path: str) -> list[str]:
    problems: list[str] = []
    ref_count = sum(len(ids) for ids in zones.values())

    if len(zones) < MIN_ZONES:
        problems.append(f"only {len(zones)} zones mapped (expected {MIN_ZONES}+)")
    if ref_count < MIN_REFS:
        problems.append(f"only {ref_count} mount references (expected {MIN_REFS}+)")
    if len(global_ids) < MIN_GLOBAL:
        problems.append(f"only {len(global_ids)} global mounts (expected {MIN_GLOBAL}+)")

    if os.path.exists(out_path):
        with open(out_path, encoding="utf-8") as handle:
            prev = _previous_ref_count(handle.read())
        if prev > 100 and not (0.6 * prev <= ref_count <= 1.6 * prev):
            problems.append(f"reference count {ref_count} is far from the previous file (~{prev})")
    return problems


# ------------------------------------------------------------------------ main

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", help="exact wago.tools build; default: latest --major")
    parser.add_argument("--major", default="12", help="game major version (default 12)")
    parser.add_argument("--cache", default=".wago-cache", help="DB2 CSV cache directory")
    parser.add_argument("--locale", default="enUS", help="export locale (default enUS)")
    parser.add_argument(
        "--out",
        default=os.path.join(
            os.path.dirname(__file__), "..",
            "Mount_Tracker_Local_Zones", "MountData.lua",
        ),
    )
    args = parser.parse_args()

    build_id = args.build or discover_build(args.major)
    print(f"build: {build_id}")

    data = Data(build_id, args.cache, args.locale)
    zones, source, subcat, expansion, faction, achievement_ids, global_ids = build(data)

    ref_count = sum(len(ids) for ids in zones.values())
    print(
        f"mapped {len(zones)} zones, {ref_count} mount references, "
        f"{len(source)} classified, {len(subcat)} sub-categorised, "
        f"{len(expansion)} with expansion, {len(faction)} faction-specific, "
        f"{len(achievement_ids)} achievement-linked, {len(global_ids)} global"
    )

    out_path = os.path.abspath(args.out)
    problems = check_sanity(zones, global_ids, out_path)
    if problems:
        for problem in problems:
            print(f"SANITY: {problem}", file=sys.stderr)
        return 1

    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(render_lua(
            zones, source, subcat, expansion, faction, achievement_ids, global_ids, build_id,
        ))
    print(f"wrote {out_path}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(
                f"- build `{build_id}`\n"
                f"- {len(zones)} zones, {ref_count} references, {len(global_ids)} global mounts\n"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
