# Plan 002: Add a direct unit-test suite for the obtainability engine

> **Executor instructions**: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving on. If anything in the
> "STOP conditions" section occurs, stop and report — do not improvise. When done,
> update the status row for plan 002 in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0878181..HEAD -- Mount_Tracker_Local_Zones/Obtainability.lua tests/ run-tests.ps1 .github/workflows/ci.yml`
> If `Obtainability.lua` changed since `0878181`, re-read it in full and adjust the
> expected states/branches below before writing assertions; on a structural
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `0878181`, 2026-08-31

## Why this matters

`Obtainability.lua` is the addon's differentiator — it turns "here are the zone's
uncollected mounts" into "here's exactly where you stand on each one" (buy it now,
short on renown, weekly farm is up, achievement incomplete). It is a **pure
module**: `Evaluate(mountID, row)` reads curated data (`addon.Curated`) plus a
handful of live player APIs, and returns `{ state, detail, sortRank }`. Pure
modules are the cheapest possible thing to test in isolation.

Today it has **no dedicated test**. The headless smoke suite (`tests/smoke.lua`,
warm scenario) exercises four outcomes — `available` (affordable gold vendor),
`rep_gated` (short on renown), `collected`, and `farmable` (weekly lockout) — as a
side effect of driving the whole addon. Everything else is unverified:

- **currency-priced vendor** affordability (`vendor.currencyID` path,
  `Obtainability.lua:167-172`) and its `"… (currency)"` detail string
- **`achievement_gated`** (`:181-189`) — reads `GetAchievementInfo` return 4 and
  the achievement name for the detail line
- **`reset_locked`** — a `lockout` mount whose `lockoutQuest` is flagged complete
  (`:193-202`); today no override sets `lockoutQuest`, so this branch has *never*
  run, even in-game
- **`quest_gated` → `drop` collapse** (`:211-216`)
- **`ReputationProgress` classic-faction branch** (`:59-66`) — the smoke test only
  hits the `C_MajorFactions` renown branch
- **`FormatGold`** thousands-separator formatting (`:98-104`)
- **`VendorDetail`** assembling `price · npc` with the `\194\183` separator (`:106-130`)
- **rep-met-then-vendor fall-through** (`:146-178`) — a `repFaction` mount that is
  *now* at threshold should fall through to the vendor branch
- **`AddTooltipLines`** — line selection per state, the subcat context line
  (`:262-270`), the "note if different from detail" rule (`:256-259`)

A regression in any of these ships silently. This plan adds `tests/test_obtainability.py`,
a pure-Lua test that loads only `Core.lua` (for the shared helpers) + `Overrides.lua`
+ `Obtainability.lua` under a tiny hand-rolled API stub and asserts each branch.

## Current state

Files:

- `Mount_Tracker_Local_Zones/Obtainability.lua` (271 lines) — the module under
  test. `addon.Obtainability.Evaluate` and `addon.Obtainability.AddTooltipLines`
  are the public surface.
- `Mount_Tracker_Local_Zones/Core.lua` — defines `addon.SafeApiCall`,
  `addon.SafeApiCallMulti`, `addon.Curated`, `addon.Print`, `addon.DebugPrint`.
  `Obtainability.lua` captures `addon.SafeApiCall` / `addon.SafeApiCallMulti` /
  `addon.Curated` as locals **at load time** (`Obtainability.lua:11-15`), so those
  must exist on `addon` before `Obtainability.lua` is loaded.
- `Mount_Tracker_Local_Zones/Overrides.lua` — sets `addon.MountOverrides`; the
  test uses its real seeded entries (mount 236 gold vendor, 168 weekly lockout,
  398 Ramkahen rep, 1615 Dragonscale renown) plus injected test entries.
- `tests/test_mountdata.py` — **the structural pattern to follow.** It picks a
  `lupa` runtime (`_load_runtime()`), makes a bare `lua.table()` as `addon`, and
  `loadfile(...)(addonName, addon)` for each addon file. Copy that runtime-probe
  and loader shape.
- `tests/test_generator.py` — also uses `lupa.LuaRuntime`; another reference.
- `tests/stub.lua` — the *smoke* stub. **Do not** import it here; it installs into
  a live `_G` for the full addon. This suite wants a minimal, explicit,
  per-test stub so each assertion controls exactly the inputs it needs.

`Obtainability.lua:11-15` — what the module captures at load:

```lua
local SafeApiCall = addon.SafeApiCall
local SafeApiCallMulti = addon.SafeApiCallMulti
-- Curated-input lookup: Overrides wins over the generated MountData. See Core.lua.
local pick = addon.Curated
```

`Obtainability.lua:48-68` — `ReputationProgress` (both branches to cover):

```lua
local function ReputationProgress(factionID, threshold)
	threshold = tonumber(threshold) or 0
	if C_MajorFactions and type(C_MajorFactions.GetMajorFactionData) == "function" then
		local data = SafeApiCall(C_MajorFactions.GetMajorFactionData, factionID)
		if type(data) == "table" and data.renownLevel then
			local level = data.renownLevel
			return level, threshold, level >= threshold, ("Renown %d"):format(level)
		end
	end
	if C_Reputation and type(C_Reputation.GetFactionDataByID) == "function" then
		local data = SafeApiCall(C_Reputation.GetFactionDataByID, factionID)
		if type(data) == "table" and data.currentStanding then
			local standing = data.currentStanding
			return standing, threshold, standing >= threshold, nil
		end
	end
	return nil, threshold, nil, nil
end
```

`Obtainability.lua:137-219` — `Evaluate`: the branch order is
(0) collected → (1) `repFaction` gate, *falls through if met* → (2) `vendor`
(affordable → `available`, else `rep_gated`) → (3) `achievementID` → (4) `lockout`
(quest done → `reset_locked`, else `farmable`) → (5) `quest`/`drop` fallback.

Globals `Evaluate` / `AddTooltipLines` may touch (all guarded, so a `nil` global
just degrades to "unknown"): `C_MajorFactions`, `C_Reputation`, `C_CurrencyInfo`,
`C_QuestLog`, `GetMoney`, `GetAchievementInfo`.

Repo conventions:
- Tests are plain `unittest` (`tests/test_*.py`), no pytest-only features.
- Each file starts with a module docstring explaining what it pins and why, and a
  `Run:` line — see the top of `tests/test_mountdata.py`.
- `@unittest.skipIf(LuaRuntime is None, "lupa not installed")` on the test class,
  exactly as `test_mountdata.py` does.
- Lua is Lua 5.1-subset; `lupa` may be backed by any 5.x/LuaJIT build.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Just this suite | `python -m unittest discover -s tests -p "test_obtainability.py" -v` | `OK`, all new tests pass |
| All Python tests | `python -m unittest discover -s tests -p "test_*.py"` | `OK` (was 63; now 63 + N) |
| Headless smoke | `python tests/run.py` | `All smoke scenarios passed.` (unchanged) |
| Lua lint | `luacheck .` | `0 warnings / 0 errors` (unchanged — `.luacheckrc` excludes `tests/`) |
| Full suite | `./run-tests.ps1` | `All suites passed.` |

## Scope

**In scope** (files you may create/modify):
- `tests/test_obtainability.py` (create)
- `run-tests.ps1` — only if the new suite is *not* already picked up (see Step 4;
  it discovers `test_*.py`, so likely no change)
- `.github/workflows/ci.yml` — add the new suite to the `data` job's explicit run
  list (Step 4)

**Out of scope** (do NOT touch):
- Any file under `Mount_Tracker_Local_Zones/` — this plan adds tests only, it does
  not change addon behaviour. If a test reveals a real bug, STOP and report it;
  do not fix it here.
- `tests/stub.lua`, `tests/harness.lua`, `tests/smoke.lua`, `tests/init.lua` — the
  smoke harness is separate; leave it alone.

## Git workflow

- Branch: `advisor/002-obtainability-unit-tests`
- One commit. Subject e.g. `Add unit tests for the obtainability engine`.
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Create the test file with the Lua-loading harness

Create `tests/test_obtainability.py`. Start from `tests/test_mountdata.py`'s
`_load_runtime()` verbatim. Then write a helper that builds a fresh Lua state per
test with an explicit stub:

```python
#!/usr/bin/env python3
"""Unit tests for Mount_Tracker_Local_Zones/Obtainability.lua.

Obtainability is a pure module: Evaluate(mountID, row) -> { state, detail,
sortRank } from curated data + a few guarded live-API reads. The smoke suite only
happens to hit `available` / `rep_gated` / `collected` / `farmable`; this pins
every branch -- currency vendor, achievement gate, reset-locked (lockoutQuest
done), the classic-reputation path, gold formatting, and the tooltip lines.

Run:  python -m unittest discover -s tests -p test_obtainability.py
"""

import os
import unittest

# ... _load_runtime() copied from tests/test_mountdata.py ...

LuaRuntime = _load_runtime()
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Mount_Tracker_Local_Zones")


def make_env(*, overrides=None, money=0, factions=None, currencies=None,
             quests_completed=None, achievements=None):
    """A Lua state with Core + Overrides + Obtainability loaded under a minimal
    WoW-API stub. Returns (lua, addon). `overrides` is a dict of
    MountOverrides sub-tables to merge on top of the shipped Overrides.lua."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()

    # --- minimal, explicit API stub (only what Obtainability.lua reads) ---
    factions = factions or {}
    currencies = currencies or {}
    quests_completed = quests_completed or {}
    achievements = achievements or {}

    g.GetMoney = lambda: money
    # C_MajorFactions.GetMajorFactionData -> { renownLevel = } or nil
    # C_Reputation.GetFactionDataByID   -> { currentStanding = } or nil
    # C_CurrencyInfo.GetCurrencyInfo    -> { quantity = } or nil
    # C_QuestLog.IsQuestFlaggedCompleted(q) -> bool
    # GetAchievementInfo(a) -> id, name, points, completed
    # Build these as Lua tables/functions via lua.eval / lua.table.
    # (Implementation detail left to the executor; keep each a few lines.
    #  Pattern: g.C_Reputation = lua.eval("{ GetFactionDataByID = function(id) ... end }")
    #  with the Python dicts closed over -- or set fields on lua.table()s.)

    def loadfile(rel):
        chunk = lua.eval('function(p) return assert(loadfile(p)) end')(
            os.path.join(ADDON, rel).replace("\\", "/"))
        return chunk

    addon = lua.table()
    for rel in ("Core.lua", "Overrides.lua", "Obtainability.lua"):
        loadfile(rel)("Mount_Tracker_Local_Zones", addon)

    # Core.lua registers an event frame + slash command on load; the stub must
    # provide CreateFrame / C_Timer / SlashCmdList etc. as no-ops so Core loads.
    # (If loading Core.lua pulls in too much, see the STOP condition below and
    #  instead hand-define addon.SafeApiCall / SafeApiCallMulti / Curated /
    #  Print / DebugPrint in ~15 lines and load only Overrides + Obtainability.)

    if overrides:
        for field, entries in overrides.items():
            sub = addon["MountOverrides"][field] or lua.table()
            addon["MountOverrides"][field] = sub
            for k, v in entries.items():
                sub[k] = v
    return lua, addon
```

**Important**: loading `Core.lua` runs its top-level `CreateFrame("Frame")`,
`SlashCmdList["MTLZ"] = ...`, etc. If stubbing all of that is more than ~20 lines,
**prefer the fallback**: skip `Core.lua` entirely and define the five helpers
`addon.SafeApiCall`, `addon.SafeApiCallMulti`, `addon.Curated`, `addon.Print`,
`addon.DebugPrint` directly in Lua from Python (copy their bodies out of
`Core.lua:69-153`), then load only `Overrides.lua` + `Obtainability.lua`. This is
cleaner and is the recommended path — `Obtainability.lua` only needs those five
names on `addon`. Decide during Step 1 and note which you chose in the docstring.

**Verify**: `python -c "import tests.test_obtainability"` from the repo root does
not raise (or `python tests/test_obtainability.py` with no tests yet exits 0/skips).

### Step 2: Write the `Evaluate` branch tests

Add a `TestEvaluate(unittest.TestCase)` class. One test per branch. For each,
build an env, call `addon.Obtainability.Evaluate(mountID, lua_row)` where
`lua_row` is a `lua.table()` with `isCollected` / `source`, and assert on
`result.state`, `result.detail`, `result.sortRank`.

Cover at minimum:

| Test | Setup | Assert |
|---|---|---|
| collected short-circuits | `row.isCollected = True` | `state == "collected"`, `detail is None` |
| gold vendor, affordable | override `vendor = {[900]={cost=1000000, npc="X"}}`, `money=2000000` | `state == "available"`, detail contains `"100g"` and `"X"` |
| gold vendor, too poor | same, `money=5` | `state == "rep_gated"` (the "can't afford" state), detail still shows the price |
| currency vendor, enough | `vendor={[901]={cost=50, currencyID=2032}}`, `currencies={2032:{quantity:99}}` | `state == "available"`, detail contains `"(currency)"` |
| currency vendor, short | same, `currencies={2032:{quantity:10}}` | `state == "rep_gated"` |
| currency vendor, API missing | same but no `C_CurrencyInfo` | `state == "available"` (optimistic per `owned == nil` branch) |
| renown gate, short | `repFaction={[902]={factionID=2507, standing=25}}`, `factions={2507:{renownLevel:5}}` | `state == "rep_gated"`, detail contains `"Renown 5"` and `"25"` |
| renown gate, met → falls through | same, `renownLevel:30`, **and** a `vendor` entry for 902 | `state == "available"` (fell through to vendor) |
| classic rep gate, short | `repFaction={[903]={factionID=1173, standing=42000}}`, no `C_MajorFactions`, `C_Reputation` returns `{currentStanding=21000}` | `state == "rep_gated"`, detail contains `"21000"` and `"42000"` |
| achievement gate | `achievementID` override `{[904]=12345}`, `GetAchievementInfo(12345)` → completed `False`, name `"Glory of the Raider"` | `state == "achievement_gated"`, detail == `"Glory of the Raider"` |
| achievement earned → not gated | same but completed `True`, mount also has no other gate | `state == "drop"` |
| weekly lockout, not done | `lockout={[905]="weekly"}`, no `lockoutQuest` | `state == "farmable"`, detail contains `"weekly"` |
| weekly lockout + dropChance | add `dropChance={[905]="~1%"}` | detail contains both `"weekly"` and `"~1%"` |
| lockout done this reset | `lockout={[906]="daily"}`, `lockoutQuest={[906]=555}`, `quests_completed={555:True}` | `state == "reset_locked"`, detail contains `"done this reset"` |
| plain drop | no curated gate, `row.source="drop"`, `dropChance={[907]="~2%"}` | `state == "drop"`, detail == `"~2%"` |
| quest source collapses to drop | `row.source="quest"`, no note | `state == "drop"` (see `:211-216`) |
| shipped seed: mount 168 | real `Overrides.lua` — `lockout="weekly"` | `state == "farmable"` |
| shipped seed: mount 236, rich | real Overrides gold vendor, `money=5000*10000*100` | `state == "available"` |

`sortRank` assertion: for at least the `available` / `farmable` / `rep_gated`
cases, assert `result.sortRank == addon.Obtainability.STATE[<state>].rank`.

**Verify**: `python -m unittest discover -s tests -p "test_obtainability.py" -v`
→ `OK`, every `TestEvaluate` test passes.

### Step 3: Write the helper + tooltip tests

Add `TestFormatting` and `TestTooltip` classes.

`TestFormatting`:
- `FormatGold` is a local, not exported. Test it indirectly through a gold-vendor
  `Evaluate` `detail` string: `cost = 1234567800` copper → detail contains
  `"123,456g"` (floor of copper/10000, comma-grouped). Add cases for `0` → `"0g"`
  and `999900` (99g, no comma) → `"99g"`.

`TestTooltip` — call `addon.Obtainability.AddTooltipLines(tip, mountID)` where
`tip` is a `lua.table()` with an `AddLine` function that appends
`tostring(text)` to a Python list (pattern: `tests/smoke.lua` lines ~207-219
build exactly this fake tip). Assert:
- collected mount → **no** lines added (early return at `:234`)
- `achievement_gated` mount → a line `"Achievement needed"` and a line with the
  achievement name
- `rep_gated` renown mount → `"Reputation needed"` + a `"Renown N / need M"` line
- instance mount with `subcat="raid"` (use shipped mount 168) → a dim `"Raid drop"`
  line appears; a `subcat="dungeon"` mount → `"Dungeon drop"`
- a mount whose `note` equals its `detail` → the note line is **not** duplicated
  (`:256-259`); a mount whose `note` differs → the note line **is** added

**Verify**: `python -m unittest discover -s tests -p "test_obtainability.py" -v`
→ `OK`.

### Step 4: Wire the suite into `run-tests.ps1` and CI

- `run-tests.ps1:46` runs `python -m unittest discover -s tests -p "test_*.py"` —
  `test_obtainability.py` matches, so **no change needed**. Confirm by running
  `./run-tests.ps1` and checking the new tests appear in the count.
- `.github/workflows/ci.yml` — the `data` job (lines ~61-79) runs `test_mountdata.py`
  and `test_toc.py` by explicit `-p`. The `generator` job runs `test_generator.py`.
  Add a step to the `data` job (or the `generator` job — `data` is the better fit
  since it also loads addon Lua):

  ```yaml
      - name: Check obtainability engine
        run: python -m unittest discover -s tests -p "test_obtainability.py" -v
  ```

  Place it after the existing "Check MountData.lua / Overrides.lua structure"
  step. It needs `lupa`, already installed by that job.

**Verify**:
- `./run-tests.ps1` → `All suites passed.`, and the `generator + mount-data + TOC`
  section total went up by N (your new test count).
- `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"`
  → no error (valid YAML).

### Step 5: Full suite

**Verify**: `./run-tests.ps1` → `All suites passed.`; `python tests/run.py` still
`All smoke scenarios passed.`; `luacheck .` still `0 warnings / 0 errors`.

## Test plan

This plan *is* the test plan. New file `tests/test_obtainability.py` with ~20–25
assertions across `TestEvaluate`, `TestFormatting`, `TestTooltip`. Structural
pattern: `tests/test_mountdata.py` (runtime probe, skipIf, Lua loading) and
`tests/smoke.lua:207-219` (fake tooltip). No existing test changes.

## Done criteria

ALL must hold:

- [ ] `tests/test_obtainability.py` exists and every branch in the Step 2 table has
      at least one assertion
- [ ] `python -m unittest discover -s tests -p "test_obtainability.py" -v` → `OK`
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK`, total = 63 + N
- [ ] `python tests/run.py` → `All smoke scenarios passed.` (unchanged: cold 73 / warm 86)
- [ ] `luacheck .` → `0 warnings / 0 errors in 12 files`
- [ ] `./run-tests.ps1` → `All suites passed.`
- [ ] `.github/workflows/ci.yml` runs the new suite; file is valid YAML
- [ ] No file under `Mount_Tracker_Local_Zones/` is modified (`git status`)
- [ ] `plans/README.md` status row for 002 updated

## STOP conditions

Stop and report back (do not improvise) if:

- Loading `Core.lua` under a stub needs more than ~20 lines of `_G` scaffolding
  **and** the fallback (hand-define the five helpers, load only Overrides +
  Obtainability) also fails — report the specific load error.
- `Obtainability.lua`'s branch order or state names differ from the "Current
  state" section (the file drifted since `0878181`).
- **A test exposes a real behaviour bug** (e.g. a state that should be
  `reset_locked` comes back `farmable`, or `FormatGold` mis-groups digits). Do
  **not** fix `Obtainability.lua` — record the failing case, mark that test
  `@unittest.expectedFailure` with a comment pointing here, and report it as a
  new finding for a separate plan.
- Any verification fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns this next:

- When a new obtainability `state` or gate is added to `Obtainability.lua`, add a
  `TestEvaluate` case for it here — this suite should stay a complete branch map.
- The `reset_locked` branch is exercised for the first time by this suite;
  in-game, it still cannot trigger until `Overrides.lockoutQuest` has real quest
  ids (a known deferred item in `context/future-features.md`). The test proves the
  *code path* works; it is not an in-game validation.
- No in-game check is strictly required for this plan (tests only), but after it
  lands the maintainer may want to spot-check one currency-priced vendor mount and
  one achievement-gated mount in the live client, since those states were
  previously unverified anywhere — see `context/phase8-ingame-checklist.md` §F.
