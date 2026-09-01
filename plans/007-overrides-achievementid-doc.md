# Plan 007 (STUB): Document `Overrides.achievementID` + seed the residual achievement mounts

> Skeleton only — unblocked by spike 005 (`context/spike-achievement-resolver.md`).
> Small; can be done before or after plan 006. Flesh out before executing.

## Status

- **Priority**: P3
- **Effort**: S
- **Depends on**: spike 005 (done); pairs with plan 006
- **Category**: docs + curation

## Goal

1. **Document the `achievementID` slot.** `addon.Curated` is generic so
   `Overrides.achievementID[mountID] = <id>` already works, but the `Overrides.lua` header
   comment (lines ~4-21) doesn't list it, and `tests/test_mountdata.py`'s
   `TestOverrides.EXPECTED_SUB_TABLES` doesn't include it.
2. **Hand-seed the high-value cases the auto-resolver (plan 006) misses** — e.g. a
   "Glory of the <Expansion> Hero" mount the player wants under a specific dungeon, or one
   of the 34 unlinked mounts that does have a clear achievement. Use
   `Overrides.add` (zone) + `Overrides.achievementID` (obtainability).

## Shape

- `Mount_Tracker_Local_Zones/Overrides.lua`: add the `achievementID [mountID] = achID`
  line to the header doc; add a small seeded `achievementID = { ... }` sub-table if any
  hand cases are found worth it (may stay empty if plan 006 covers enough).
- `tests/test_mountdata.py`: add `"achievementID"` to `TestOverrides.EXPECTED_SUB_TABLES`;
  add a `test_override_achievementid_values_are_ints` check.
- If plan 006 has **not** landed: this plan alone still de-dead-codes the
  `achievement_gated` state for whatever mounts get hand-seeded.

## Verification

- `python -m unittest discover -s tests -p "test_mountdata.py" -v` → OK
- `luacheck .` → 0/0
- In-game: right-click / hover a hand-seeded mount → tooltip shows
  "Achievement needed · <name>".

---

## As executed (2026-09-01, branch `worktree-execute-plans-006-010`)

### Deliverable 1 — document the slot (done)

- `Mount_Tracker_Local_Zones/Overrides.lua` header: added the
  `achievementID [mountID] = achievementID` line to the field list.
- `Overrides.lua` body: added `achievementID = {}` as a real sub-table (between
  `expansion` and `dropChance`) with a comment explaining why it is empty.
- `tests/test_mountdata.py`: `"achievementID"` added to
  `TestOverrides.EXPECTED_SUB_TABLES`; new `test_override_achievementid_values_are_ints`
  (positive-int key + value). `addon.Curated` is already generic, so no runtime
  code changed — `Obtainability.Evaluate` picks the slot up as-is.

### Deliverable 2 — hand-seed residual cases (investigated, none seeded)

Enumerated every mount plan 006's linker leaves unlinked (34 on build
12.1.0.69497) and resolved each against the cached `Achievement` / `Achievement_Category`
tables. Every one falls into a bucket that should **not** be seeded:

- **Ambiguous Alliance/Horde title pair** (17): collection metas — "Mountacular"
  (9598/9599), "Lord of the Reins", "We're Going to Need More Saddles", "No Stable
  Big Enough", "A Horde of Hoofbeats", "Advanced Husbandry", "The Stable Master",
  "Thanks for the Carry!", "Insurmountable Collection", … Both achievements reward
  the same item; picking one is a coin-flip and wrong for half of players. These
  are "collect N mounts" metas — Global with no zone is correct.
- **Global-category achievement** (15): "Allied Races: <race>" (category 201
  Reputation), "Alterac Valley of Olde" (PvP), "Conqueror of Azeroth",
  "Let Me Solo Him: …" (feats), "Ahead of the Curve: Garrosh Hellscream" (FoS).
  Plan 006's `_achievement_in_global_category` guard already excludes this class
  structurally; hand-seeding a zone would fight it.
- **No matching achievement / test entry** (2+): the Dragonriding drake
  customisation lines ("Dragon Isles: Highland Drake", …) have no `Achievement.Title_lang`
  match — different unlock system, always available in DF; "Dragon Isles Drake
  Model Test" (1605) is a test mount.

Conclusion: plan 006's generator pass (~183 links) covers every mount with a
clean link. The `Overrides.achievementID` table ships empty — a documented,
ready slot for a future maintainer preference, exactly as the stub's "may stay
empty if plan 006 covers enough" anticipated.

### Verification

- `pwsh -File run-tests.ps1` → `All suites passed.` (luacheck 0/0, smoke
  cold 89 / warm 121, 108 unit tests OK).
- `python -m unittest discover -s tests -p "test_*.py"` → `OK` (108).

### In-game validation step (separate, for the maintainer)

No runtime behaviour changed (empty table). Once `MountData.lua` is regenerated
(plan 006's deferred step), the achievement tooltip validation there also covers
this slot. If a mount is later added to `Overrides.achievementID`, hover it
uncollected and confirm the tooltip reads "Achievement needed · <name>".
