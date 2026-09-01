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

---

## As executed (2026-09-01, branch `worktree-execute-plans-006-010`)

### Approach fleshed out from the stub + spike

**Linking (`Data.achievement_for_mount`)** — scoped to mounts carrying an
`Achievement: <Title>` label in `SourceText_lang`:

1. `Achievement.RewardItemID` → the mount's teaching item (`item_by_mount`). If
   exactly one achievement rewards that item, that's the link.
2. If several achievements reward the item, intersect with the normalized-title
   matches and take it only if exactly one survives.
3. Otherwise, a normalized exact `Title_lang` match — used only when exactly one
   achievement has that title.
4. Anything else → `None` (mount is untouched).

`normalize_achievement_title` lowercases, turns every non-alphanumeric run into a
space and collapses whitespace. That makes `"For The Horde!"` match
`"For the Horde"` while keeping a difficulty suffix (`"... (25 player)"`) a
*distinct* string so it can't create a false ambiguity.

**Zone (`Data.zones_for_achievement`)** — `Achievement.Instance_ID` → the
generator's existing `map_zone`, recursing type-8 ("complete achievement")
criteria to depth 2 via a ported `_criteria_leaves` (minimal slice of the
sibling's `criteria_leaves`, bracket column form). Returns `uiMapID → instance
Map.ID` so the instance's `Map.InstanceType` still drives `subcat`.
The quest-POI path and the category-name fallback were **not** ported (no
labelled mount uses type-27 criteria; category-name match only adds noise).

**Global-category guard (`_achievement_in_global_category`)** — the spike's
"drop the 2 borderline metas" (`For The Horde!` → Eversong Woods,
`Fates of the Shadowlands Raids` → Sanctum of Domination) is implemented
structurally, not by hand: an achievement whose `Achievement_Category` chain
reaches a root in `{1 Statistics, 81 Feats of Strength, 95 PvP, 155 World
Events, 201 Reputation}` never contributes a zone, even on a single-instance
resolution. This is the sibling generator's `SKIP_CATEGORY_ROOTS ∪
GLOBAL_CATEGORY_ROOTS` idea. `achievementID` is still recorded for those mounts.

**`build()` wiring** — after the instance-loot / SourceText passes, before the
`global` fallthrough: record `achievementID` for every linked mount; then, only
if the mount is still unplaced and the achievement is not global-category,
resolve zones — exactly one → assign it with `source = "achievement"`; two or
more → leave `global`.

**`render_lua()`** — `achievementID` is now a populated `[mountID] = achID`
map (int→int), pulled out of the "leave for Overrides" stub block.

### Numbers (build 12.1.0.69497, generator run, not shipped)

| metric | before | after |
|---|---|---|
| zones | 293 | 298 |
| zone mount-references | 1846 | 1870 (+24) |
| `global` mounts | 988 | 964 (−24) |
| `achievementID` links | 0 | 183 |

The 24 moved mounts are the "Glory of the <Raid> Raider" family (Ulduar →
Manaforge Omega, incl. two Ulduar mounts) plus two Timewalking "Sanctum of
Chronology" metas. Zero mounts became newly-global (no regressions). `272`
(`For The Horde!`) and `1576` (`Fates of the Shadowlands Raids`) correctly
stayed `global`. Sanity gate passes.

### Deviations from the stub

- **`MountData.lua` was NOT regenerated** and `tests/test_mountdata.py:151-153`
  was **not** bumped to assert a non-empty `achievementID`. The stub's "Out of
  scope" says regen + ship is a separate, in-game-validated step, and that
  assertion can only pass once the file is regenerated. The
  `test_optional_input_tables_are_present` key-presence check still passes as-is.
  Bump it together with the regen (pairs with plan 007's
  `EXPECTED_SUB_TABLES` change).
- Files changed: `tools/generate_mount_zones.py`, `tests/test_generator.py`
  (+17 tests, 35 → 52). Generator-tables cache gained `Achievement`,
  `Achievement_Category`, `Criteria`, `CriteriaTree` (`.wago-cache/`, gitignored;
  the weekly `refresh-mount-data.yml` will fetch them — ~17 MB total, acceptable).

### In-game validation step (separate, for the maintainer)

Regenerate `MountData.lua` (`python tools/generate_mount_zones.py --build <latest>`),
`/reload`, then: (a) stand in Ulduar / Icecrown Citadel and confirm the Glory
mounts show under the raid header; (b) hover an uncollected achievement-reward
mount and confirm the tooltip reads "Achievement needed · <name>" instead of a
bare "Not yet collected"; (c) confirm `Mountain o' Mounts` / `Leading the
Cavalry` / keystone / Gladiator mounts are still under Global.
