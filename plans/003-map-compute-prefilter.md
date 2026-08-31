# Plan 003: Pre-filter `Map.Compute` to positioned mounts only

> **Executor instructions**: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving on. If anything in the
> "STOP conditions" section occurs, stop and report — do not improvise. When done,
> update the status row for plan 003 in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0878181..HEAD -- Mount_Tracker_Local_Zones/Map.lua Mount_Tracker_Local_Zones/MountModel.lua Mount_Tracker_Local_Zones/MountActions.lua tests/smoke.lua`
> If `Map.lua` or `MountModel.lua` changed since `0878181`, compare the "Current
> state" excerpts against the live code first; on a structural mismatch, STOP.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (complements plan 001)
- **Category**: perf
- **Planned at**: commit `0878181`, 2026-08-31

## Why this matters

`Map.Compute` (`Map.lua`) rebuilds the world-map / minimap pin set by calling
`MountModel.BuildRow(mountID)` for **every candidate mount in the game** — the
union of every zone's mount list (`CandidateSet(nil)`) plus every global mount —
then keeping only the ones where `row.point` is set. `BuildRow` is not cheap: it
calls `C_MountJournal.GetMountInfoByID`, resolves faction, and runs
`Obtainability.Evaluate`, which for vendor/reputation/achievement mounts makes
live `GetMoney` / `C_Reputation` / `C_MajorFactions` / `C_CurrencyInfo` calls
(each wrapped in `pcall`).

That is ~1,800–1,900 `BuildRow` calls per `Map.Rebuild()`. But a mount can only
ever produce a pin if it has a position: a curated `points` entry, or — when
`db.showVendorIcons` is on — a vendor entry with coordinates. Today that's **7
mounts** (`Overrides.points`) plus a handful of positioned vendors. `MountData.points`
ships empty. So >99% of the work is thrown away.

`Map.Rebuild()` fires on login, on every mount collected (`NEW_MOUNT_ADDED`,
debounced 1s), and on several options toggles — and, after plan 001, on every
list-filter change. Pre-filtering to the positioned id set turns a ~1,900-call
scan into a ~10-call one.

This is not a hot-path emergency (the scan is maybe 5–15 ms), but it's a clean
~100× reduction with a trivial, well-bounded change, and it removes the main
reason to worry about calling `Map.Rebuild()` more often.

## Current state

Files:

- `Mount_Tracker_Local_Zones/Map.lua` — `Compute` (lines 36–78) does the full
  scan. `Map.Rebuild` / `Map.Refresh` call it.
- `Mount_Tracker_Local_Zones/MountModel.lua` — `BuildRow` (243–302), `CandidateSet`
  (147–191), `GlobalCandidateSet` (196–214). `BuildRow` sets `row.point` from
  `PointFor(mountID)` (curated `points`) and, when `db.showVendorIcons`, falls
  back to `addon.VendorLocation(mountID)` (`MountModel.lua:281-283`).
- `Mount_Tracker_Local_Zones/MountActions.lua` — `addon.VendorLocation(mountID)`
  (123–135) returns `{ uiMapID, x, y }, npc` when the curated `vendor` entry has
  numeric `uiMapID`/`x`/`y`, else `nil`.
- `Mount_Tracker_Local_Zones/Overrides.lua` — `addon.MountOverrides.points` and
  `.vendor` sub-tables (keyed by mountID).
- `Mount_Tracker_Local_Zones/MountData.lua` — `addon.MountData.points` (empty
  today), `.vendor` (empty today).

`Map.lua:36-78` — `Compute` as it exists now:

```lua
local function Compute()
	pins = {}

	local MountModel = addon.MountModel
	if not (MountModel and MountModel.BuildRow and MountModel.CandidateSet) then
		return
	end

	local seen = {}
	local function consider(mountID)
		if seen[mountID] then
			return
		end
		seen[mountID] = true

		local row = MountModel.BuildRow(mountID)
		-- row.include folds in hidden / hiddenSources / unusable / faction /
		-- obtainable-only / show-collected -- Map respects all of them now.
		if not row or not row.include or row.isCollected or not row.point then
			return
		end

		local uiMapID = row.point[1]
		pins[uiMapID] = pins[uiMapID] or {}
		table.insert(pins[uiMapID], {
			id = mountID,
			spellID = row.spellID,
			x = row.point[2] / 10000,
			y = row.point[3] / 10000,
			state = row.state,
			icon = row.icon,
		})
	end

	for _, mountID in ipairs(MountModel.CandidateSet(nil)) do
		consider(mountID)
	end
	if MountModel.GlobalCandidateSet then
		for _, mountID in ipairs(MountModel.GlobalCandidateSet()) do
			consider(mountID)
		end
	end
end
```

`MountModel.lua:230-233` — `PointFor` (the curated-points reader `BuildRow` uses):

```lua
local function PointFor(mountID)
	local point = Curated("points", mountID)
	return type(point) == "table" and point or nil
end
```

`Curated` (`Core.lua:146-153`, exported as `addon.Curated`) checks
`addon.MountOverrides[field][id]` then `addon.MountData[field][id]`.

Repo conventions:
- `Map.lua` keeps its own small helpers; adding a local `PositionedCandidates()`
  function is in keeping with the file's style.
- Iterate tables with `pairs`/`ipairs`, dedupe with a `seen` set — see
  `CandidateSet` in `MountModel.lua` for the exact idiom.
- Guard optional `addon.*` reads (`addon.MountData and addon.MountData.points`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Lua lint | `luacheck .` | `0 warnings / 0 errors in 12 files` |
| Headless smoke | `python tests/run.py` | `All smoke scenarios passed.` |
| Python unit tests | `python -m unittest discover -s tests -p "test_*.py"` | `OK` (63) |
| Full suite | `./run-tests.ps1` | `All suites passed.` |

## Scope

**In scope**:
- `Mount_Tracker_Local_Zones/Map.lua`
- `tests/smoke.lua` — add/adjust an assertion (Step 3)

**Out of scope** (do NOT touch):
- `Mount_Tracker_Local_Zones/MountModel.lua` — `BuildRow` stays exactly as is;
  this plan only changes *which ids* Map feeds it.
- `Mount_Tracker_Local_Zones/MountActions.lua` — `VendorLocation` is reused as-is.
- The pin-pool / `DressPin` / `Refresh` machinery in `Map.lua` (lines 80+) — not
  touched.

## Git workflow

- Branch: `advisor/003-map-compute-prefilter`
- One commit. Subject e.g. `Perf: only evaluate positioned mounts when building map pins`.
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Add a `PositionedCandidates()` helper in `Map.lua`

Above `Compute`, add a local function that returns a deduped array of the mount
ids that could possibly have a pin: the keys of `MountData.points` +
`MountOverrides.points`, plus — only when `db.showVendorIcons` is on — the keys of
`MountData.vendor` + `MountOverrides.vendor`.

```lua
-- Only mounts with a curated position can ever produce a pin: a `points` entry,
-- or (when db.showVendorIcons) a `vendor` entry that carries coordinates.
-- BuildRow still does the real filtering (row.include / collected / point); this
-- just spares it ~1800 calls for mounts that could never be pinned anyway.
local function PositionedCandidates()
	local ids, seen = {}, {}
	local function add(tbl)
		if type(tbl) ~= "table" then
			return
		end
		for mountID in pairs(tbl) do
			if not seen[mountID] then
				seen[mountID] = true
				ids[#ids + 1] = mountID
			end
		end
	end

	local md = addon.MountData or {}
	local ov = addon.MountOverrides or {}
	add(md.points)
	add(ov.points)
	if addon.db and addon.db.showVendorIcons then
		add(md.vendor)
		add(ov.vendor)
	end
	return ids
end
```

**Verify**: `luacheck .` → `0 warnings / 0 errors in 12 files`

### Step 2: Use it in `Compute`

Replace the two candidate loops at the bottom of `Compute` (the
`for ... MountModel.CandidateSet(nil)` loop and the
`if MountModel.GlobalCandidateSet then ...` loop) with a single loop over
`PositionedCandidates()`:

```lua
	for _, mountID in ipairs(PositionedCandidates()) do
		consider(mountID)
	end
```

Leave `consider` unchanged — it still calls `MountModel.BuildRow(mountID)` and
still drops anything where `not row or not row.include or row.isCollected or not
row.point`. A vendor mount only gets `row.point` when `db.showVendorIcons` is on
(that logic lives in `BuildRow`), which matches the guard in
`PositionedCandidates`, so the behaviour is identical.

The `MountModel and MountModel.BuildRow and MountModel.CandidateSet` guard at the
top of `Compute` can stay as-is (harmless) or drop the `MountModel.CandidateSet`
part since it's no longer used — either is fine; prefer leaving it to minimise the
diff.

**Behaviour delta (small, intended)**: today a mount with a curated `points` entry
that is somehow *not* in any zone's list and *not* global would never be
considered. After this change it is. This is more correct (if you curated a
position you want the pin) and, given all 7 current `points` entries are on mounts
that resolve to a zone, has zero observable effect now. Note it in the commit
message.

**Verify**: `python tests/run.py` → `All smoke scenarios passed.`

### Step 3: Confirm the smoke coverage still holds and tighten it

The warm scenario in `tests/smoke.lua` already asserts:
- `"warm: a curated point places a world + minimap pin"` — mount 8 has
  `Stub.data.overrides.points = { [8] = { 84, 5000, 5000 } }` (see
  `tests/init.lua`), so `PositionedCandidates` must return it.
- `"warm: showVendorIcons adds a map pin for the positioned vendor mount"` —
  mount 11 has a positioned `vendor` entry; toggling `showVendorIcons` changes the
  pin count.

Both should still pass unchanged. If either fails, `PositionedCandidates` is not
picking up the overrides seed — STOP and report.

Add one assertion to the existing `"warm: a curated point places a world +
minimap pin"` step (or a new step right after it): a mount with **no** point and
**no** positioned vendor entry never reaches `DressPin`. Simplest check —
`Stub.data.worldPins` after a rebuild equals the number of positioned mounts in
the fixture (mount 8 always; mount 11 only when `showVendorIcons`), not the total
mount count:

```lua
step("warm: Compute only pins positioned mounts, not the whole journal", function()
	addon.db.showVendorIcons = false
	addon.db.showMapIcons = true
	addon.MountModel.InvalidateCache()
	addon.Map.Rebuild()
	-- Fixture positioned mounts with showVendorIcons off: just mount 8 (points).
	check("exactly one world pin (the single positioned fixture mount)",
		Stub.data.worldPins == 1, Stub.data.worldPins)
	addon.db.showVendorIcons = false
	addon.MountModel.InvalidateCache()
	addon.Map.Rebuild()
end)
```

If the fixture has more than one positioned non-vendor mount, adjust the expected
count to match `tests/init.lua`'s `D.overrides.points` — read it and count.

**Verify**: `python tests/run.py` → `All smoke scenarios passed.`; the new check
passes; warm count goes 86 → 87 (or 86 → 88 if plan 001 also landed a check —
that's fine, they're independent).

### Step 4: Full suite

**Verify**: `./run-tests.ps1` → `All suites passed.`

## Test plan

- Existing warm assertions (`"a curated point places a world + minimap pin"`,
  `"showVendorIcons adds a map pin"`) must stay green — they are the regression
  guard that `PositionedCandidates` finds the right ids.
- One new warm assertion: pin count after a rebuild equals the positioned-fixture
  count, proving Compute no longer walks the whole candidate set.
- Structural pattern: the existing `"warm:"` `Map` steps in `tests/smoke.lua`.

## Done criteria

ALL must hold:

- [ ] `Map.lua` `Compute` iterates `PositionedCandidates()` and no longer calls
      `MountModel.CandidateSet(nil)` or `MountModel.GlobalCandidateSet()`
      (`grep -n "CandidateSet" Mount_Tracker_Local_Zones/Map.lua` → no matches, or
      only in a leftover top-of-function guard you chose to keep)
- [ ] `luacheck .` → `0 warnings / 0 errors in 12 files`
- [ ] `python tests/run.py` → `All smoke scenarios passed.`; both existing
      curated-point / vendor-pin warm checks still pass; new "only positioned
      mounts" check passes
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK` (63)
- [ ] `./run-tests.ps1` → `All suites passed.`
- [ ] Only `Map.lua` and `tests/smoke.lua` modified (`git status`)
- [ ] `plans/README.md` status row for 003 updated

## STOP conditions

Stop and report back (do not improvise) if:

- `BuildRow` in `MountModel.lua` no longer reads `Curated("points", ...)` /
  `addon.VendorLocation` to set `row.point`, or `Compute` no longer keys pins off
  `row.point` — the premise (position = pin) has changed.
- Either existing warm `Map` assertion fails after the change — `PositionedCandidates`
  is missing ids the fixture expects; report exactly which mount id and which
  sub-table it should have come from.
- `MountData.points` or `MountData.vendor` is found to be non-empty in the shipped
  file (`grep -A2 "points = {" Mount_Tracker_Local_Zones/MountData.lua`) — that's
  fine functionally, but confirm `PositionedCandidates` picks those up too before
  proceeding.
- Any verification fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns this next:

- If a future change makes `BuildRow` set `row.point` from a **new** source (not
  `points` and not `vendor`), `PositionedCandidates` must be extended to include
  that source's ids — otherwise those mounts silently stop getting pins. Keep the
  helper's id sources in sync with `BuildRow`'s `row.point` logic. Add a code
  comment in `BuildRow` near the `row.point` assignment pointing at
  `Map.PositionedCandidates`.
- Plan 005 (achievement→zone resolver) may add an `achievementID`-driven or
  instance-entrance `points` source — that would flow through `md.points`
  automatically, no change needed, as long as it lands in `MountData.points` /
  `Overrides.points`.
- In-game check (deploy via `deploy-addon`, then `/reload`): `/mtlz debug` on,
  then `/mtlz map` — it prints `Map: N mount pins across M zones`. N/M should be
  unchanged from before this plan (7 curated rares + any positioned vendors with
  `showVendorIcons` on). Fly to The Storm Peaks / Deepholm / Azsuna and confirm
  the seeded rare pins are still there. Re-run `context/phase8-ingame-checklist.md`
  section E.
