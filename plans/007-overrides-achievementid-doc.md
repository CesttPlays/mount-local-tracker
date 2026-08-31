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
