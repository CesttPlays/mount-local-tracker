#!/usr/bin/env python3
"""SPIKE scratch script (plan 005) -- NOT production code, do not merge.

For every mount that carries an "Achievement: <Title>" label in SourceText and
is currently dumped into the `global` list, work out:
  - which achievement id it refers to (RewardItemID FK, else exact title match)
  - which zone that achievement resolves to (Achievement.Instance_ID -> uiMapID)

Prints a table + the yield counts the findings doc needs.

Usage:  python tools/_spike_ach_resolve.py [--build 12.1.0.69497]
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from generate_mount_zones import Data, build, clean_text  # noqa: E402

ACH_LABEL_RE = re.compile(r"Achievement:\s*(.+?)(?=\s+(?:World Event|[A-Z][a-z]+):|$)")
CRITERIA_COMPLETE_ACHIEVEMENT = "8"


def build_criteria_index(cache, build_id):
    """root Criteria_tree id -> [(type, asset), ...] leaves, like the sibling generator."""
    import collections
    crit = {r["ID"]: r for r in _load(os.path.join(cache, build_id, "Criteria.csv"))}
    tree = {r["ID"]: r for r in _load(os.path.join(cache, build_id, "CriteriaTree.csv"))}
    kids = collections.defaultdict(list)
    for r in tree.values():
        kids[r["Parent"]].append(r["ID"])

    def leaves(root):
        if root in ("0", ""):
            return []
        out, stack, seen = [], [root], set()
        while stack:
            t = stack.pop()
            if t in seen:
                continue
            seen.add(t)
            ch = kids.get(t)
            if ch:
                stack.extend(ch)
                continue
            node = tree.get(t)
            if not node:
                continue
            c = crit.get(node["CriteriaID"])
            if c and node["CriteriaID"] != "0":
                out.append((c["Type"], c["Asset"]))
        return out

    return leaves


def _load(path):
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def load_csv(path):
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def achievement_title(text: str) -> str | None:
    m = ACH_LABEL_RE.search(text)
    if not m:
        return None
    return re.sub(r"\([^)]*\)", "", m.group(1)).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="12.1.0.69497")
    ap.add_argument("--cache", default=".wago-cache")
    args = ap.parse_args()

    data = Data(args.build, args.cache, "enUS")
    zones, source, subcat, expansion, faction, global_ids = build(data)
    global_set = set(global_ids)

    ach_rows = load_csv(os.path.join(args.cache, args.build, "Achievement.csv"))
    ach_by_id = {r["ID"]: r for r in ach_rows}
    leaves = build_criteria_index(args.cache, args.build)

    def resolve_zones(ach_id, depth=2, stack=()):
        """Achievement.Instance_ID -> uiMapID, recursing type-8 (complete
        achievement) criteria for meta achievements like 'Glory of the X Raider'."""
        if ach_id in stack:
            return set()
        row = ach_by_id.get(ach_id)
        if not row:
            return set()
        out = set()
        inst = row.get("Instance_ID", "-1")
        if inst not in ("-1", "0", ""):
            mapped = data.map_zone.get(inst)
            if mapped:
                out.add(mapped)
        if depth > 0:
            for ctype, asset in leaves(row["Criteria_tree"]):
                if ctype == CRITERIA_COMPLETE_ACHIEVEMENT:
                    out |= resolve_zones(asset, depth - 1, stack + (ach_id,))
        return out

    # exact lowercased title -> [achievement ids]
    title_index: dict[str, list[str]] = {}
    for r in ach_rows:
        t = clean_text(r["Title_lang"]).lower()
        if t:
            title_index.setdefault(t, []).append(r["ID"])

    # RewardItemID -> [achievement ids]  (reuse the generator's item->mount map)
    reward_index: dict[str, list[str]] = {}
    for r in ach_rows:
        item = r.get("RewardItemID") or "0"
        if item != "0":
            reward_index.setdefault(item, []).append(r["ID"])

    total_labelled = 0
    labelled_global = 0
    linked = 0
    link_fk = 0
    link_name = 0
    link_ambiguous = 0
    resolved_one = 0
    resolved_many = 0
    stays_global = 0

    rows_out = []

    for mount_id, mrow in data.mounts.items():
        text = clean_text(mrow["SourceText_lang"])
        title = achievement_title(text)
        if not title:
            continue
        total_labelled += 1
        is_global = mount_id in global_set
        if is_global:
            labelled_global += 1

        # --- link ---
        ach_id = None
        how = None
        item_id = data.item_by_mount.get(mount_id)
        fk_hits = reward_index.get(item_id or "", [])
        name_hits = title_index.get(title.lower(), [])
        if len(fk_hits) == 1:
            ach_id, how = fk_hits[0], "fk"
            link_fk += 1
        elif fk_hits:
            # multiple achievements reward the same item -- disambiguate by title
            both = [a for a in fk_hits if a in name_hits]
            if len(both) == 1:
                ach_id, how = both[0], "fk+name"
                link_fk += 1
            else:
                link_ambiguous += 1
        elif len(name_hits) == 1:
            ach_id, how = name_hits[0], "name"
            link_name += 1
        elif name_hits:
            link_ambiguous += 1

        if not ach_id:
            rows_out.append((mount_id, title, "??", "-", "UNLINKED", is_global))
            continue
        linked += 1

        # --- resolve achievement -> zone (Instance_ID + type-8 recursion) ---
        uimap_ids = {u for u in resolve_zones(ach_id) if u in data.uimap}

        names = sorted({clean_text(data.uimap.get(u, {}).get("Name_lang", "")) for u in uimap_ids})
        if len(uimap_ids) == 1:
            resolved_one += 1
            verdict = "1-zone"
        elif len(uimap_ids) > 1:
            resolved_many += 1
            verdict = f"{len(uimap_ids)}-zone"
        else:
            stays_global += 1
            verdict = "stays-global"

        rows_out.append((mount_id, title, ach_id + f"({how})",
                         ", ".join(f"{u}:{n}" for u, n in zip(sorted(uimap_ids), names)) or "-",
                         verdict, is_global))

    print(f"{'mount':>6}  {'achievement title':44}  {'achID':14}  {'zone(s)':34}  verdict  glob")
    print("-" * 130)
    for mid, title, aid, zone, verdict, isg in sorted(rows_out, key=lambda r: (r[4], int(r[0]))):
        print(f"{mid:>6}  {title[:44]:44}  {aid:14}  {zone[:34]:34}  {verdict:12}  {'G' if isg else ''}")

    print()
    print("=== counts ===")
    print(f"mounts with an 'Achievement:' label            : {total_labelled}")
    print(f"  ... of which currently in `global`           : {labelled_global}")
    print(f"linked to an achievement id                    : {linked}"
          f"  (fk={link_fk}, name={link_name}, ambiguous/miss={link_ambiguous})")
    print(f"resolve to exactly one zone (Instance_ID)      : {resolved_one}")
    print(f"resolve to 2+ zones                            : {resolved_many}")
    print(f"linked but Instance_ID gives no zone           : {stays_global}")
    unlinked = total_labelled - linked
    print(f"unlinked (no FK, ambiguous or missing title)   : {unlinked}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
