# Plan 005 (SPIKE): Achievement-reward → zone resolver for `global` mounts

> **Executor instructions**: This is a **spike**, not a build task. The deliverable
> is (a) a written findings report at `context/spike-achievement-resolver.md`,
> (b) a throwaway prototype on a branch, and (c) concrete follow-up plan stubs.
> You are NOT shipping the generator change or regenerating `MountData.lua` in
> this plan. Do not modify any file under `Mount_Tracker_Local_Zones/`. Follow the
> steps, timebox each, and if a STOP condition hits, write up what you found and
> stop.
>
> **Drift check (run first)**:
> `git diff --stat 0878181..HEAD -- tools/ Mount_Tracker_Local_Zones/MountData.lua context/future-features.md`
> If `tools/generate_mount_zones.py` changed since `0878181`, read it fresh before
> starting.

## Status

- **Priority**: P3
- **Effort**: L (spike itself: M — roughly a focused day)
- **Risk**: LOW (spike touches only the generator + a new context doc + a prototype branch)
- **Depends on**: none
- **Category**: direction (design/spike)
- **Planned at**: commit `0878181`, 2026-08-31

## Why this matters

`tools/generate_mount_zones.py` resolves a mount to a zone from its
`Mount.SourceText_lang` structured labels (`Zone:` / `Vendor:` / `Drop:` / …) and
from the instance loot-table join. Everything it can't place lands in the flat
`global` list. **217 mounts** carry an `Achievement:` label in `SourceText_lang`
(confirmed against `.wago-cache/12.1.0.69497/Mount.csv`), e.g.:

```
Achievement: Glory of the Ulduar Raider   Category: Dungeons & Raids
Achievement: What a Long, Strange Trip It's Been   Category: World Events
Achievement: For The Alliance!   Category: Player vs. Player
```

Many of those are genuinely global (`Mountain o' Mounts`, `Leading the Cavalry`).
But the "Glory of the <Instance> Raider/Hero" family — and other
instance-scoped achievement rewards — map cleanly to a raid or dungeon zone. The
sibling repo `achivement-local-tracker` already solved exactly this problem for
achievements, in `tools/generate_zone_achievements.py` (`zones_for_achievement`:
`Achievement.Instance_ID` → `UiMapAssignment` → uiMapID, plus a
"complete quest" criteria-POI path and a category-name fallback).
`context/future-features.md` names this port explicitly and estimates "~60 mounts
sitting in `global`" would move to a real zone.

There is a **second payoff**: the addon's `achievement_gated` obtainability state
is currently **dead**. `MountData.achievementID` ships empty (`render_lua` emits
`achievementID = {}`), `Overrides.lua` doesn't even document an `achievementID`
slot, and `Obtainability.Evaluate` reads `pick("achievementID", mountID)` which
therefore never returns anything. Resolving mount → achievement here would let the
generator emit `achievementID[mountID]`, so a mount you can only get by finishing
an achievement shows "Achievement needed · <name>" instead of a bare
"Not yet collected".

The spike answers: **how does a mount reference its achievement, how many resolve
to a zone, is the quality good enough to ship, and what exactly should the build
plan do.**

## Current state

Files:

- `tools/generate_mount_zones.py` — the mount generator (521 lines). Key pieces:
  - `TABLES` (lines 43–55): the DB2 tables it fetches. **`Achievement` is not in
    the list.** `Map`, `UiMap`, `UiMapAssignment`, `JournalInstance` **are**.
  - `Data.__init__` builds `self.map_zone` (instance `Map.ID` → uiMapID, preferring
    a zone/dungeon-type UI map) — lines 246–261. Reusable as-is for
    `Achievement.Instance_ID`.
  - `Data.mount_by_item` (itemID → mountID via teach-spell) and `item_by_mount`
    — lines 214–231. Relevant if achievements link via `RewardItemID`.
  - `build()` (309–365): per mount, resolves zones; `if not resolved: global_ids.add`
    (lines 344–346). This is where an achievement branch would slot in, next to
    the existing instance-loot-table branch.
  - `render_lua()` (379–430): emits `achievementID = {},` as a hardcoded empty
    stub at line 417. A resolver would fill it.
  - `check_sanity()` (448–464): `MIN_ZONES=40`, `MIN_REFS=250`, `MIN_GLOBAL=150`,
    plus a ±60% swing check vs the previous file. Adding ~60 refs and removing ~60
    globals stays well inside these.
- `../achivement-local-tracker/tools/generate_zone_achievements.py` — **the
  reference implementation.** Read `zones_for_achievement` (308–342),
  `Data.map_zone` (230–244), `Data.category_chain` / `in_global_roots`
  (259–277), `criteria_leaves` (283–305), and `point_for_achievement` (348–368).
  Note it fetches `Achievement`, `Achievement_Category`, `Criteria`,
  `CriteriaTree`, `QuestPOIBlob`, `QuestPOIPoint`.
  **Column-name caveat**: this generator reads `Region_0` / `UiMin_0` (underscore),
  while the mount generator reads `Region[0]` / `UiMin[0]` (brackets) — wago.tools
  CSV export uses **brackets**; the sibling's underscore form is from a different
  export era. Any code ported over must use the bracket form to match
  `tools/generate_mount_zones.py`'s existing `normalize_region` (lines 184–195,
  currently **unused** — it was added as scaffolding for exactly this work).
- `Mount_Tracker_Local_Zones/MountData.lua` — generated; do not touch in this spike.
- `Mount_Tracker_Local_Zones/Obtainability.lua:181-189` — the `achievement_gated`
  branch that would finally get data:
  ```lua
  local achievementID = pick("achievementID", mountID)
  if achievementID and not AchievementEarned(achievementID) then
      local _, achName = SafeApiCallMulti(GetAchievementInfo, achievementID)
      return { state = "achievement_gated", detail = ... , sortRank = ... }
  end
  ```
- `Mount_Tracker_Local_Zones/Overrides.lua` — the hand-tuning file. Its header
  comment (lines 4–21) lists every supported sub-table but **omits `achievementID`**
  — `addon.Curated` is generic so `Overrides.achievementID` would work, it's just
  undocumented. A follow-up plan should add it to the doc.
- `tests/test_generator.py` — 35 tests over the pure transforms; a new resolver
  needs matching fixture tests here.
- `tests/test_mountdata.py:151-153` — asserts `MountData.achievementID` key
  exists (empty stub OK today; would assert non-empty / int-keyed after the build).
- `.github/workflows/refresh-mount-data.yml` — runs the generator weekly and opens
  a PR. New tables → longer fetch, but no structural change.

Cached DB2 for offline work: `.wago-cache/12.1.0.69497/` (gitignored) has
`Mount.csv`, `Map.csv`, `UiMap.csv`, `UiMapAssignment.csv`, `JournalInstance.csv`
already. You will need to add `Achievement.csv` (and possibly `Criteria.csv` /
`CriteriaTree.csv` / `QuestPOIBlob.csv` / `QuestPOIPoint.csv`). Fetch via the
generator's own `load_table` helper or:
`curl -sL "https://wago.tools/db2/Achievement/csv?build=12.1.0.69497&locale=enUS" -o .wago-cache/12.1.0.69497/Achievement.csv`
(`wago.tools` may be down — see `context/context-cache.md` "DB2 access" for the
`wow.tools.local` offline fallback against the local CASC install).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Generator unit tests | `python -m unittest discover -s tests -p "test_generator.py" -v` | `OK` (35 baseline) |
| Prototype a run (offline, cached build) | `python tools/generate_mount_zones.py --build 12.1.0.69497` | prints zone/ref/global counts; writes `MountData.lua` **only if you let it** — for the spike, run a modified copy or `--out /tmp/spike.lua` |
| Inspect current globals | `python3 -c "..."` ad-hoc against `.wago-cache/.../Mount.csv` | — |
| Full suite (after any test change) | `./run-tests.ps1` | `All suites passed.` |

## Scope

**In scope** (spike deliverables only):
- `context/spike-achievement-resolver.md` (create — the findings report)
- A prototype branch `advisor/005-spike-achievement-resolver` containing
  throwaway generator edits + a scratch script. This branch is **not** meant to
  merge; it's evidence.
- Appending follow-up plan stubs to `plans/README.md` (or new `plans/00N-*.md`
  skeletons) for the actual build work.

**Out of scope** (do NOT do in this spike):
- Modifying `Mount_Tracker_Local_Zones/MountData.lua` or any addon Lua.
- Landing the generator change on `main` or in a mergeable state.
- Regenerating and shipping data.
- The instance-*entrance*-coordinates work (`JournalInstanceEntrance` → map pins) —
  that's a separate future-features item; note it as adjacent but don't scope it in.

## Git workflow

- Branch: `advisor/005-spike-achievement-resolver`
- Commit prototype code + the findings doc. Subject: `Spike: achievement→zone resolver for mounts (prototype, do not merge)`.
- Do NOT push or open a PR unless the operator asks. The branch is a workspace.

## Steps

### Step 1: Establish the linking mechanism (timebox ~1h)

Determine how a mount row points at its achievement. Check, in order:

1. **`Achievement.RewardItemID`** — does the `Achievement` table have a column
   whose value is the mount's teaching item id (joinable via the generator's
   existing `mount_by_item` / `item_by_mount`)? This is the clean FK if present.
   Dump `Achievement.csv` columns and spot-check a known case: "Leading the
   Cavalry" (mount 268) or a "Glory of the … Raider".
2. **Name match** — `SourceText_lang` "Achievement: <Title>" (strip with the
   generator's existing `clean_text`, then a regex like the sibling's
   `zone_names_from_text` but for `Achievement:`) matched against
   `Achievement.Title_lang` (enUS, lowercased, exact). Count collisions (same
   title, multiple achievement ids — Alliance/Horde variants, re-issued
   achievements).
3. **`Achievement.IconFileID` == `Mount` / spell icon** — weakest, only as a
   tiebreaker.

Record which mechanism(s) work, the match rate, and the ambiguity rate.

**Deliverable**: section "Linking" in the findings doc, with the chosen mechanism
and its numbers.

### Step 2: Resolve achievement → zone, measure yield (timebox ~2h)

Port the minimal slice of `zones_for_achievement` needed:

- **`Achievement.Instance_ID`** (≠ `-1`/`0`/``) → `self.map_zone[instance_id]`
  (the generator already builds `map_zone`). This alone should cover the "Glory of
  the <Raid> Raider" family.
- Optionally the **criteria-quest POI** path (needs `Criteria` + `CriteriaTree` +
  `QuestPOIBlob` + `QuestPOIPoint`, and the `normalize_region` helper the
  generator already has) — only add it if Instance_ID alone yields materially
  fewer than the "~60" the future-features doc predicts.
- The **category-name fallback** (`Achievement_Category` name → `UiMap` of the
  same name) — the sibling gates this to PvP/World-Events/Reputation roots. For
  mounts it's probably not worth it; note the decision.

Write a scratch script (`tools/_spike_ach_resolve.py`, on the branch) that, for
every mount currently in `global` with an `Achievement:` label, prints
`mountID | achievement title | resolved uiMapID(s) | uiMap name(s)`.

**Deliverable**: the script output (paste into the findings doc), plus counts:
- N mounts with an `Achievement:` label that are currently `global`
- N that resolve to exactly one zone
- N that resolve to 2+ zones (and how you'd disambiguate — e.g. prefer the
  dungeon/raid-type map, like `map_zone` already does)
- N that stay `global` (correctly — meta achievements)

### Step 3: Spot-check quality (timebox ~1h)

For 10–15 resolved mounts, verify the zone against Wowhead / your own knowledge:
- "Glory of the Ulduar Raider" reward → should land in Ulduar's uiMapID
- "Leading the Cavalry" (100 mounts) → genuinely global, must **not** resolve
- Alliance/Horde PvP mounts ("For The Alliance!"/"For The Horde!") → these reward
  in the enemy capital raid; decide whether that's a useful "zone" or should stay
  global. Note the call.

**Deliverable**: a table in the findings doc — mount, resolved zone, correct?,
notes. Compute an accuracy rate. **Ship bar: ≥90% of resolved mounts land in a
zone a player would agree with, and zero false positives on the obviously-global
metas.** If below bar, the recommendation is "don't ship the auto-resolver; add
the ~10 clean cases to `Overrides.add` + `Overrides.achievementID` by hand
instead" — write that up as the follow-up instead of the generator plan.

### Step 4: Define the follow-up build plan(s) (timebox ~1h)

Based on Steps 1–3, write plan stub(s) into `plans/` (skeletons, not full plans —
a later `improve` run or the maintainer fleshes them out). Likely shape:

- **Plan 00N — "Add the achievement→zone branch to the mount generator"**: add
  `Achievement` (+ any criteria tables) to `TABLES`; add
  `Data.achievement_for_mount` and `Data.zones_for_achievement`; wire into
  `build()` next to the instance-loot branch (before the `global` fallthrough);
  fill `achievementID` in `render_lua`; add `tests/test_generator.py` fixtures
  (achievement with Instance_ID resolves; meta achievement stays global; the
  linking mechanism); bump `tests/test_mountdata.py` to assert `achievementID` is
  now non-empty and int→int. In-scope: `tools/generate_mount_zones.py`,
  `tests/test_generator.py`, `tests/test_mountdata.py`. Regenerate + in-game
  validate as a **separate** step (never ship generated data unverified —
  `context/` working rule).
- **Plan 00N+1 — "Document `Overrides.achievementID` + seed the residual cases"**:
  add the slot to the `Overrides.lua` header doc; hand-add any high-value mounts
  the auto-resolver misses.
- If Step 3 fails the ship bar: a single **"Hand-curate achievement mounts into
  Overrides"** plan instead.

**Deliverable**: the stub file(s) under `plans/`, and rows added to
`plans/README.md`'s table with status `TODO` and a note "unblocked by spike 005".

### Step 5: Write the findings report

Create `context/spike-achievement-resolver.md` consolidating Steps 1–4:
identity of the problem, the linking mechanism + numbers, the yield, the quality
spot-check + accuracy rate, the ship/no-ship recommendation, the follow-up plan
list, and any open questions (localization beyond enUS, the weekly refresh
workflow's extra fetch time, whether `MountData` size growth matters). Match the
terse house style of the other `context/` docs; convert dates to absolute.

**Verify**: `python -m unittest discover -s tests -p "test_generator.py" -v` still
`OK` (35) — you didn't break the real generator. `git status` shows only:
`context/spike-achievement-resolver.md`, `plans/*`, and (on the branch)
`tools/_spike_*.py` + any throwaway generator edits.

## Done criteria

ALL must hold:

- [ ] `context/spike-achievement-resolver.md` exists and covers: linking
      mechanism + match/ambiguity numbers, resolved-vs-stays-global counts, a
      ≥10-row quality spot-check with an accuracy rate, and a clear
      ship / don't-ship recommendation with reasoning
- [ ] Branch `advisor/005-spike-achievement-resolver` has the scratch resolver
      script and its output is quoted in the findings doc
- [ ] `plans/README.md` has ≥1 follow-up plan row (status TODO, "unblocked by
      spike 005"), and at least a skeleton `plans/00N-*.md` for it
- [ ] `python -m unittest discover -s tests -p "test_generator.py" -v` → `OK` (35)
- [ ] No file under `Mount_Tracker_Local_Zones/` is modified (`git status`)
- [ ] `plans/README.md` status row for 005 updated to DONE
- [ ] `.wago-cache/` additions are not staged for commit (it's gitignored — confirm)

## STOP conditions

Write up what you have and stop if:

- **No reliable linking mechanism exists** — `Achievement.RewardItemID` is absent
  and name-matching has >20% ambiguity/misses. Recommendation becomes: hand-curate
  only. Still write the findings doc.
- `wago.tools` is unreachable **and** the `wow.tools.local` CASC fallback
  (`context/context-cache.md`) also can't produce `Achievement.csv` — you can't do
  Step 2. Report the blocker; do not guess at yield numbers.
- The `Achievement` DB2 schema on build 12.1.0.69497 has no `Instance_ID` column
  (renamed / removed) and the criteria-POI path is also unavailable — note it,
  recommend hand-curation.
- Step 3 accuracy is below the ship bar — that's a valid result; document it and
  write the hand-curation follow-up instead of the generator follow-up.

## Maintenance notes

- This spike deliberately does **not** touch instance-entrance map coordinates
  (`JournalInstanceEntrance` → pins), a separate `future-features.md` item. If the
  achievement resolver lands, instance-sourced mounts (including the newly-resolved
  achievement ones) still get no map pin until that work is done — note it as the
  natural next step.
- The weekly `refresh-mount-data.yml` run will fetch the new tables every time;
  `Achievement` is a few MB. If that's a concern, the follow-up plan can cache
  more aggressively or gate the achievement pass behind a flag.
- Keep the sibling repo (`achivement-local-tracker`) in mind but do **not**
  refactor it here — the family convention is "land in one repo, backport later if
  it earns its keep".
