# Plan 006 (STUB): Add the achievement→zone + `achievementID` branch to the mount generator

> Skeleton only — unblocked by spike 005 (`context/spike-achievement-resolver.md`).
> A later `improve` run or the maintainer fleshes this out into a full plan before
> execution. Read the spike doc first.

## Status

- **Priority**: P3
- **Effort**: M
- **Depends on**: spike 005 (done)
- **Category**: data / generator

## Goal

Two independent deliverables (can ship separately):

1. **`MountData.achievementID` for confidently-linked mounts (~180).** Lights up the
   currently-dead `achievement_gated` obtainability state. Low risk — a wrong id only
   mislabels a tooltip.
2. **Zone assignment for single-`Instance_ID` resolutions (~24).** Moves the
   "Glory of the <Raid> Raider" mounts under their raid zone header. Multi-zone metas
   stay `global`.

## Shape

- `tools/generate_mount_zones.py`:
  - add `Achievement`, `Achievement_Category`, `Criteria`, `CriteriaTree` to `TABLES`.
  - `Data.achievement_for_mount`: RewardItemID FK first (via existing `item_by_mount`);
    exact `Title_lang` match **only when unambiguous** as fallback. Normalise punctuation
    / case. Explicit "ambiguous → skip". This is the main risk area — fixture-test it.
  - `Data.zones_for_achievement`: `Achievement.Instance_ID` → `self.map_zone` (already
    built), recursing type-8 (complete achievement) criteria at depth 2. Port the minimal
    slice of the sibling's `zones_for_achievement` + `criteria_leaves`. Bracket column
    form (`Region[0]`), not the sibling's underscore form — use the existing (currently
    unused) `normalize_region` helper if the quest-POI path is ever added (it is not
    needed now: no labelled mount uses type-27 criteria).
  - wire into `build()` next to the instance-loot branch, before the `global` fallthrough:
    single resolved zone → assign it; 2+ → leave `global`; always record `achievementID`
    when linked.
  - `render_lua()`: fill `achievementID = { ... }` (int→int) instead of the `{}` stub.
- `tests/test_generator.py`: fixtures — RewardItemID link resolves; ambiguous title →
  skip; `Instance_ID` resolves; type-8 recursion resolves a classic Glory meta; multi-zone
  meta stays global; keystone/Gladiator mount stays global.
- `tests/test_mountdata.py:151-153`: assert `MountData.achievementID` is now non-empty and
  int→int.

## Out of scope

- Regenerating + shipping `MountData.lua` — that is a **separate** step, and it must be
  in-game validated (never ship generated data unverified — `context/` working rule).
- Instance-entrance map pins (`JournalInstanceEntrance`) — separate `future-features.md`
  item; the newly-zoned mounts get no pin until it lands.
- The ~137 "linked, no Instance_ID" and the 20 multi-zone metas — hand-curate via plan 007
  if any are wanted.

## Verification (once built)

- `python -m unittest discover -s tests -p "test_generator.py" -v` → OK
- `python tools/generate_mount_zones.py --build 12.1.0.69497 --out /tmp/x.lua` prints
  ~24 more zone refs, ~180 `achievementID` entries, ~24 fewer globals; sanity gate passes.
- `./run-tests.ps1` → all green after the `test_mountdata.py` assertion bump.
