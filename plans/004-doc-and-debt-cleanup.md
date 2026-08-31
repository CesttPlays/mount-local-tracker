# Plan 004: Doc + small-debt cleanup — phase-9 status, `GetCurrentMapID` dup, account-count scan

> **Executor instructions**: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving on. If anything in the
> "STOP conditions" section occurs, stop and report — do not improvise. When done,
> update the status row for plan 004 in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0878181..HEAD -- Mount_Tracker_Local_Zones/ context/ .claude/skills/wow-addon-companion/`
> If any of these changed since `0878181`, re-read the affected file before
> editing; on a structural mismatch in the Lua excerpts, STOP.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs + tech-debt
- **Planned at**: commit `0878181`, 2026-08-31

## Why this matters

Three small, unrelated items, bundled because each is a few lines:

1. **Stale phase-9 doc.** `context/phase9-code-quality-refactor.md` header says
   *"Status: proposed, not started"*, but commit `0878181` ("Phase 9: code-quality
   refactor (#3)") landed every workstream WS1–WS10. The code shows it: `addon.Curated`
   (Core), `MountActions.lua` exists, `Obtainability.IsDimmed`, single-pass
   `BuildRow` with `row.include`, `CACHE_KEYS` including `showVendorIcons`,
   `RequestMembershipRefresh` split from `RequestStateRefresh`, named `repFaction`
   (`{ factionID, standing }`), the subcat tooltip line. Two other context files
   still say "phases 1-8 done". A maintainer (or an agent) picking up this repo
   will think a large refactor is pending and re-plan it.

2. **`GetCurrentMapID` duplicated.** `Core.lua:225` defines it and exports
   `addon.GetCurrentMapID`; `MountModel.lua:114` re-declares an identical local.
   Phase 9 consolidated "curated lookup", "state→colour" and "source list" into
   one home each; this one slipped. Two copies of a `C_Map` call that could drift.

3. **`RefreshAccountCounts` full-journal scan on the wrong event.**
   `MountModel.RefreshCachedStates` (`MountModel.lua:555`) calls
   `RefreshAccountCounts()` first thing. `RefreshCachedStates` runs on
   `MOUNT_JOURNAL_USABILITY_CHANGED` (mount up/down, entering a no-fly zone,
   riding-skill change). `RefreshAccountCounts` iterates **every mount id in the
   journal** (`~1,900` `GetMountInfoByID` calls) to recount account collected/total
   — numbers that can only change on `NEW_MOUNT_ADDED`, never on a usability event.
   The scan is pure waste on that path. It belongs on the membership path (and the
   post-login `Warm`), where it currently is **not** wired at all — so after
   collecting a mount, the summary's "N / M account" count is stale until the next
   usability event happens to refresh it.

## Current state

### Item 1 — docs

- `context/phase9-code-quality-refactor.md:3` —
  `Status: **proposed, not started**`
- `context/context-cache.md:17` (approx) —
  `- Status: **phases 1-8 done, merged to \`main\`** (PR #1 ... PR #2 ...)`
  and it references stale branch state.
- `context/immediate-next-steps.md:4` —
  `- **Phases 1-8 done. Merged to \`main\`.** PR #1 (vendor waypoints) and PR #2 ...`
  Also line ~1-16 describe "Current state (2026-08-31)".
- `.claude/skills/wow-addon-companion/SKILL.md` — this repo's own committed skill
  (not a junction; see `.gitignore` — `!.claude/skills/wow-addon-companion/`).
  Line ~25: `tuple order is load-bearing, still unverified in-game`. Line ~66:
  `Everything is still unvalidated in the live client — see context/phase8-ingame-checklist.md.`
  Both contradicted by the phase-8 validation recorded 2026-08-31 in
  `context/phase8-ingame-checklist.md` and `context/wow-api-reference-cache.md`.

Convention for these files (from the repo's working rules in
`context/context-cache.md`): context docs are updated to match reality *before*
committing; convert relative dates to absolute; keep them terse. Phase 8's doc
shows the house style for recording an in-game pass ("**PASSED 2026-08-31.**").

### Item 2 — `GetCurrentMapID`

`Core.lua:225-231`:

```lua
local function GetCurrentMapID()
	if C_Map and type(C_Map.GetBestMapForUnit) == "function" then
		return SafeApiCall(C_Map.GetBestMapForUnit, "player")
	end
end

addon.GetCurrentMapID = GetCurrentMapID
```

`MountModel.lua:114-119` (the duplicate):

```lua
local function GetCurrentMapID()
	if type(C_Map) ~= "table" then
		return nil
	end
	return SafeApiCall(C_Map.GetBestMapForUnit, "player")
end
```

`MountModel.lua:10-13` — where MountModel caches `addon.*` helpers as locals:

```lua
local SafeApiCall = addon.SafeApiCall
local Obtainability = addon.Obtainability

local Curated = addon.Curated -- Overrides wins over generated MountData; see Core.lua
```

`MountModel.lua:483` — the only call site of the local `GetCurrentMapID`:

```lua
	local mapID = GetCurrentMapID()
```

Load order (from the TOC): `Core.lua` → ... → `MountModel.lua`, so
`addon.GetCurrentMapID` is defined before `MountModel.lua` runs. The two
implementations are behaviourally identical (both guard `C_Map`, both call
`SafeApiCall(C_Map.GetBestMapForUnit, "player")`, both return `nil` otherwise).

### Item 3 — `RefreshAccountCounts`

`MountModel.lua:392-411`:

```lua
local accountCache = { total = nil, collected = nil }

local function RefreshAccountCounts()
	if not (C_MountJournal and type(C_MountJournal.GetMountIDs) == "function") then
		accountCache.total, accountCache.collected = nil, nil
		return
	end
	local all = SafeApiCall(C_MountJournal.GetMountIDs)
	if type(all) ~= "table" then
		return
	end
	local total, collected = 0, 0
	for _, mountID in ipairs(all) do
		total = total + 1
		if select(11, addon.MountInfo(mountID)) then
			collected = collected + 1
		end
	end
	accountCache.total, accountCache.collected = total, collected
end
```

`MountModel.lua:555-557` — the wasteful call:

```lua
function MountModel.RefreshCachedStates()
	RefreshAccountCounts()

	if not cache.groups then
```

`MountModel.lua:591-593` — `Warm` (keep this call):

```lua
function MountModel.Warm()
	RefreshAccountCounts()
end
```

`Core.lua:284-291` — `RequestMembershipRefresh` (the `NEW_MOUNT_ADDED` path,
where the account recount *should* happen):

```lua
local RequestMembershipRefresh = Debounced(0.5, function()
	if addon.MountModel then
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
end)
```

`Core.lua:432-440` — event routing (unchanged by this plan, shown for context):

```lua
	if mountEvents[event] then
		if event == "NEW_MOUNT_ADDED" then
			RequestMembershipRefresh()
			RequestMapRefresh()
		else
			RequestStateRefresh()
		end
		return
	end
```

`RequestStateRefresh` (`Core.lua:271-278`) is the `MOUNT_JOURNAL_USABILITY_CHANGED`
path — it calls `MountModel.RefreshCachedStates()`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Lua lint | `luacheck .` | `0 warnings / 0 errors in 12 files` |
| Headless smoke | `python tests/run.py` | `All smoke scenarios passed.` |
| Python unit tests | `python -m unittest discover -s tests -p "test_*.py"` | `OK` (63) |
| Full suite | `./run-tests.ps1` | `All suites passed.` |

## Scope

**In scope**:
- `context/phase9-code-quality-refactor.md`
- `context/context-cache.md`
- `context/immediate-next-steps.md`
- `.claude/skills/wow-addon-companion/SKILL.md`
- `Mount_Tracker_Local_Zones/MountModel.lua`
- `Mount_Tracker_Local_Zones/Core.lua`
- `tests/smoke.lua` — one new assertion for item 3

**Out of scope** (do NOT touch):
- `Mount_Tracker_Local_Zones/Window.lua` — `SummaryText` reads
  `addon.MountModel.Summary()`; its behaviour must not change (the counts it shows
  are the same, just refreshed on the right event).
- Any other `context/` file (e.g. `phase8-ingame-checklist.md`,
  `wow-api-reference-cache.md` — those already record the validation correctly).
- `defaults.version` in `Core.lua` — no SavedVariables shape change here; leave it 1.

## Git workflow

- Branch: `advisor/004-doc-and-debt-cleanup`
- One commit is fine (or three — `docs:`, then `Dedup GetCurrentMapID`, then
  `Move account recount off the usability event`). Match `git log` subject style.
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Update the phase-9 doc

In `context/phase9-code-quality-refactor.md`, change the header block. Replace:

```
Status: **proposed, not started**
Author: thermo-nuclear code-quality review, 2026-08-31
```

with something like:

```
Status: **SHIPPED 2026-08-31** — all workstreams WS1–WS10 landed in commit
`0878181` ("Phase 9: code-quality refactor (#3)"). Kept as the record of what
changed and the in-game checklist for future regressions.
Author: thermo-nuclear code-quality review, 2026-08-31
```

Do not rewrite the body — the workstream descriptions and the section-4 in-game
checklist stay useful. If you can confirm from `context/` that the section-4
in-game checks were run (check `context/context-cache.md` /
`immediate-next-steps.md` for a phase-9 validation note — there may not be one),
add one line under the status noting whether they were. If there's no record, add:
`In-game checklist (section 4): not separately recorded — re-run after the next
deploy.`

**Verify**: `grep -n "proposed, not started" context/phase9-code-quality-refactor.md`
→ no matches.

### Step 2: Update the two "phases 1-8" references

- `context/context-cache.md`: change the `Status:` line so it reads "phases 1-9
  done" and mentions PR #3 (Phase 9) alongside #1/#2. Keep the rest of the status
  line (in-game validation 2026-08-31, not released, TOC at 0.1.0) intact.
- `context/immediate-next-steps.md`: change `**Phases 1-8 done. Merged to \`main\`.**`
  to `**Phases 1-9 done. Merged to \`main\`.**` and add PR #3 to the PR list. If
  the file has an "All green offline" block with test counts, update the smoke
  count only if it actually changed (it did not for phase 9 — leave it).

Do **not** invent new status claims — only correct the phase number and PR list.

**Verify**: `grep -rn "phases 1-8\|Phases 1-8" context/` → no matches.

### Step 3: De-stale the committed skill

In `.claude/skills/wow-addon-companion/SKILL.md`:

- The C_MountJournal bullet: change `**tuple order is load-bearing**, still
  unverified in-game (see context/wow-api-reference-cache.md).` to
  `**tuple order is load-bearing**; validated in-game 2026-08-31 (see
  context/wow-api-reference-cache.md).`
- The "In-game checks" section: change `Everything is still unvalidated in the
  live client — see context/phase8-ingame-checklist.md.` to
  `Validated in-game 2026-08-31 (phase-8 checklist A–G passed); re-run
  context/phase8-ingame-checklist.md after any behavioural change.`

**Verify**: `grep -n "still unverified\|still unvalidated" .claude/skills/wow-addon-companion/SKILL.md`
→ no matches.

### Step 4: De-duplicate `GetCurrentMapID`

In `MountModel.lua`:

- Delete the local `function GetCurrentMapID()` block (lines 114–119 in the
  excerpt above — the whole 6-line function).
- Add, in the `local X = addon.X` block near the top (after
  `local Curated = addon.Curated`):
  ```lua
  local GetCurrentMapID = addon.GetCurrentMapID -- defined in Core.lua
  ```
- The call site at `MountModel.lua:483` (`local mapID = GetCurrentMapID()`) is
  unchanged — it now resolves to the captured `addon.GetCurrentMapID`.

Leave `Core.lua`'s `GetCurrentMapID` and its `addon.GetCurrentMapID` export
exactly as they are.

**Verify**:
- `grep -n "function GetCurrentMapID\|local GetCurrentMapID\|addon.GetCurrentMapID" Mount_Tracker_Local_Zones/`
  → exactly three hits: the `function` + `addon.` export in `Core.lua`, and the
  new `local ... = addon.GetCurrentMapID` in `MountModel.lua`. No `function
  GetCurrentMapID` in `MountModel.lua`.
- `luacheck .` → `0 warnings / 0 errors in 12 files`
- `python tests/run.py` → `All smoke scenarios passed.` (the warm scenario drives
  `GetZoneMounts`, which calls this).

### Step 5: Move the account recount off the usability event

In `MountModel.lua`:

- Export `RefreshAccountCounts` so `Core.lua` can call it. After the function
  definition (around line 411), add:
  ```lua
  MountModel.RefreshAccountCounts = RefreshAccountCounts
  ```
- Remove the `RefreshAccountCounts()` call from the top of
  `MountModel.RefreshCachedStates` (line 556). Add a one-line comment in its place:
  ```lua
  -- Account collected/total only move on NEW_MOUNT_ADDED, not on a usability
  -- event; the membership-refresh path (Core.lua) recounts them.
  ```
- Keep the `RefreshAccountCounts()` call in `MountModel.Warm` (line 592) as-is.

In `Core.lua`, in the `RequestMembershipRefresh` debounced body (lines 284–291),
add a recount alongside the invalidate + refresh:

```lua
local RequestMembershipRefresh = Debounced(0.5, function()
	if addon.MountModel then
		addon.MountModel.RefreshAccountCounts()
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
end)
```

**Verify**:
- `grep -n "RefreshAccountCounts" Mount_Tracker_Local_Zones/` → four hits: the
  `local function`, the new `MountModel.RefreshAccountCounts =` export, the call
  in `Warm`, and the new call in `Core.lua`'s `RequestMembershipRefresh`. **No**
  call inside `RefreshCachedStates`.
- `luacheck .` → `0 warnings / 0 errors in 12 files`

### Step 6: Smoke assertion for item 3

`tests/smoke.lua` already has (warm scenario) a step
`"stale rows: collecting a listed mount removes it on NEW_MOUNT_ADDED"` that fires
`Harness.collectMount(18)` then `Harness.runTimers()`. Right after that step, add:

```lua
if SCENARIO == "warm" then
	step("account count refreshes on NEW_MOUNT_ADDED, not only on usability", function()
		local model = addon.MountModel
		Stub.data.zone, Stub.data.mapID = "Stormwind City", 84
		model.InvalidateCache()
		model.GetZoneMounts()

		-- Prime with the current account count, then collect a fresh mount and
		-- fire ONLY NEW_MOUNT_ADDED (collectMount does exactly that). The summary
		-- account total must go up without any usability event.
		model.RefreshAccountCounts()
		local before = model.Summary().accountCollected or 0

		Stub.data.mountInfo[9999] = { name = "Test Steed", spellID = 1, isCollected = false }
		Stub.data.mountIDs[#Stub.data.mountIDs + 1] = 9999
		Stub.data.mountInfo[9999].isCollected = true
		Harness.collectMount(9999)
		Harness.runTimers()

		local after = model.Summary().accountCollected or 0
		check(("account collected rose on NEW_MOUNT_ADDED (before=%s after=%s)")
			:format(tostring(before), tostring(after)), after == before + 1)
	end)
end
```

Check `tests/harness.lua`'s `collectMount` — it sets `isCollected = true` on the
stub then fires `NEW_MOUNT_ADDED`; the manual `mountInfo[9999].isCollected = true`
above is belt-and-braces. If `collectMount` already handles a not-previously-known
id cleanly, simplify accordingly.

**Verify**: `python tests/run.py` → `All smoke scenarios passed.`; the new check
passes.

### Step 7: Full suite

**Verify**: `./run-tests.ps1` → `All suites passed.`

## Test plan

- Item 1/2/3 docs + `GetCurrentMapID`: covered by the existing smoke warm
  scenario (`GetZoneMounts` path) staying green — no new assertion needed for the
  dedup.
- Item 3 (`RefreshAccountCounts` move): one new warm assertion that the account
  count updates on `NEW_MOUNT_ADDED`. Pattern: the adjacent
  `"stale rows: ..."` step.

## Done criteria

ALL must hold:

- [ ] `grep -rn "proposed, not started\|phases 1-8\|Phases 1-8\|still unverified\|still unvalidated" context/ .claude/skills/wow-addon-companion/`
      → no matches
- [ ] `grep -n "function GetCurrentMapID" Mount_Tracker_Local_Zones/MountModel.lua`
      → no matches; `grep -n "addon.GetCurrentMapID" Mount_Tracker_Local_Zones/MountModel.lua`
      → one match (the new `local` capture)
- [ ] `grep -n "RefreshAccountCounts" Mount_Tracker_Local_Zones/MountModel.lua`
      → the `local function`, the export, and the `Warm` call — **not** inside
      `RefreshCachedStates`
- [ ] `grep -n "RefreshAccountCounts" Mount_Tracker_Local_Zones/Core.lua` → one
      match, inside `RequestMembershipRefresh`
- [ ] `luacheck .` → `0 warnings / 0 errors in 12 files`
- [ ] `python tests/run.py` → `All smoke scenarios passed.`; new account-count
      check passes
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK` (63)
- [ ] `./run-tests.ps1` → `All suites passed.`
- [ ] Only the in-scope files are modified (`git status`)
- [ ] `plans/README.md` status row for 004 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The `GetCurrentMapID` implementations in `Core.lua` and `MountModel.lua` are
  **not** behaviourally identical (e.g. one has extra logic) — do not collapse
  them; report the difference.
- `RefreshCachedStates` or `RequestMembershipRefresh` no longer matches the
  "Current state" excerpts (drift since `0878181`).
- The context docs already say "phases 1-9" / record the phase-9 validation (an
  earlier reconcile happened) — skip the doc steps that are already done and note
  it.
- Any verification fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns this next:

- Item 3: the account recount now happens on `NEW_MOUNT_ADDED` (debounced 0.5s)
  and at login (`Warm`, +5s). If a future feature needs the account total fresh at
  some other moment, call `addon.MountModel.RefreshAccountCounts()` explicitly
  there rather than re-adding it to `RefreshCachedStates`.
- In-game check (deploy via `deploy-addon`, `/reload`): open the tracker; note the
  `· a / b account` figure in the summary line (appears ~5s after login). Collect
  a mount (or a GM/test char) → within ~1s the `a` should tick up by one. Trigger
  a usability change (mount up/down, enter a no-fly area) → the account figure
  should **not** flicker or recompute visibly. Then `/mtlz` in a couple of zones
  to confirm the list still populates (the `GetCurrentMapID` dedup). Re-run
  `context/phase9-code-quality-refactor.md` checklist 4.6 / 4.8.
