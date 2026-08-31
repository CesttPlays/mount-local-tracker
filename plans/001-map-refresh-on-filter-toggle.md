# Plan 001: Map/minimap pins rebuild immediately when a list-filter option changes

> **Executor instructions**: Follow this plan step by step. Run every verification
> command and confirm the expected result before moving on. If anything in the
> "STOP conditions" section occurs, stop and report — do not improvise. When done,
> update the status row for plan 001 in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 0878181..HEAD -- Mount_Tracker_Local_Zones/Config.lua Mount_Tracker_Local_Zones/Map.lua Mount_Tracker_Local_Zones/MountModel.lua tests/smoke.lua`
> If any of those files changed since this plan was written, compare the "Current
> state" excerpts below against the live code before proceeding; on a mismatch,
> treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0878181`, 2026-08-31

## Why this matters

The world-map and minimap pins are drawn by `Map.Compute` (`Map.lua`), which — as
of the phase-9 refactor — filters candidate mounts on `row.include`. `row.include`
folds in the user's list filters: `showCollected`, `showObtainableOnly`,
`showUnusable`, `showGlobal`, and the per-source "Filter by source" checkboxes
(`db.hiddenSources`).

But the options panel's change handler, `Config.lua`'s `OnSettingChanged`, only
calls `addon.Map.Rebuild()` for the three *icon* toggles (`showMapIcons`,
`showMinimapIcons`, `showVendorIcons`). For every other list-filter change it
invalidates the tracker-window model cache and refreshes the window — but leaves
the map pin set untouched. So after a player turns on "Only show obtainable
mounts" (or hides a source, or turns off "Show unusable"), the tracker list
updates but the map keeps showing pins for mounts that are now filtered out,
until the next zone change or unrelated rebuild happens to recompute them.

After this plan, toggling any list filter updates the map and the window together.

## Current state

Files:

- `Mount_Tracker_Local_Zones/Config.lua` — the Settings-API options panel. The
  change router `OnSettingChanged` (lines 29–67) decides which surfaces to refresh
  per setting key. Contains the bug.
- `Mount_Tracker_Local_Zones/Map.lua` — pin computation. `Compute` (lines 36–78)
  builds a row per candidate mount and keeps only `row.include and not
  row.isCollected and row.point`. Already correct; no change needed here — read it
  only to confirm `row.include` is respected.
- `Mount_Tracker_Local_Zones/MountModel.lua` — defines `CACHE_KEYS` (lines 30–38),
  the list of `db` fields that change tracker-list content. `Config.lua` derives
  its `CACHE_AFFECTING` set from this.
- `tests/smoke.lua` — the headless scenario script; you will add one assertion.

`Config.lua:20-27` — the helper the filter branch calls today:

```lua
local function InvalidateAndRefresh()
	if addon.MountModel then
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
end
```

`Config.lua:29-67` — the router as it exists now:

```lua
-- React only to what each setting actually affects.
local function OnSettingChanged(key)
	if key == "showMinimapButton" then
		if addon.ApplyMinimapButton then
			addon.ApplyMinimapButton()
		end
		return
	end

	if key == "windowStyle" then
		if addon.NotifyWindowStyleChanged then
			addon.NotifyWindowStyleChanged()
		end
		return
	end

	-- Map-only toggles: they change world/minimap icon rendering, nothing in the
	-- tracker list.
	if key == "showMapIcons" or key == "showMinimapIcons" then
		if addon.Map then
			addon.Map.Rebuild()
		end
		return
	end

	-- showVendorIcons feeds row.point for vendor mounts (part of the model cache
	-- key now) *and* drives the map pins, so it needs both a rebuild and a
	-- cache invalidation. It falls through to the CACHE_AFFECTING check below.
	if key == "showVendorIcons" and addon.Map then
		addon.Map.Rebuild()
	end

	-- groupBy / showCollected / showObtainableOnly / showUnusable / showGlobal /
	-- showVendorIcons or a hiddenSources toggle: the list content changes, so
	-- drop the model cache and refresh the window.
	if key == "hiddenSources" or CACHE_AFFECTING[key] then
		InvalidateAndRefresh()
	end
end
```

`Config.lua:14-18` — how `CACHE_AFFECTING` is built (unchanged by this plan):

```lua
local CACHE_AFFECTING = {}
for _, key in ipairs((addon.MountModel and addon.MountModel.CACHE_KEYS) or {}) do
	CACHE_AFFECTING[key] = true
end
```

`MountModel.lua:30-38` — `CACHE_KEYS` contents:

```lua
local CACHE_KEYS = {
	"groupBy",
	"showCollected",
	"showObtainableOnly",
	"showGlobal",
	"showUnusable",
	"showVendorIcons",
}
```

Repo conventions to match:
- Small, commented, boring Lua. Guard every optional `addon.X` before calling it
  (`if addon.Map then ... end`) — see the existing branches in this same function.
- One canonical list drives behaviour; don't add a second hand-kept list. Reuse
  `CACHE_AFFECTING` / the `key == "hiddenSources"` condition that already gates
  the window refresh.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Lua lint | `luacheck .` | `0 warnings / 0 errors in 12 files` |
| Headless smoke | `python tests/run.py` | `All smoke scenarios passed.` |
| Python unit tests | `python -m unittest discover -s tests -p "test_*.py"` | `OK` (63 tests) |
| Full suite | `./run-tests.ps1` | `All suites passed.` |

## Scope

**In scope** (the only files you may modify):
- `Mount_Tracker_Local_Zones/Config.lua`
- `tests/smoke.lua`

**Out of scope** (do NOT touch):
- `Mount_Tracker_Local_Zones/Map.lua` — `Compute` already filters on
  `row.include` correctly; changing it is not needed and risks the pin math.
- `Mount_Tracker_Local_Zones/MountModel.lua` — `CACHE_KEYS` is the right list
  already; do not add or remove entries.
- The `showMapIcons` / `showMinimapIcons` early-return branch — it is correct
  (those are map-only and already call `Map.Rebuild()`).

## Git workflow

- Branch: `advisor/001-map-refresh-on-filter-toggle`
- One commit. Message style matches `git log` (short imperative subject, e.g.
  `Fix: map pins now rebuild when a list filter changes`).
- Do NOT push or open a PR unless the operator asks.

## Steps

### Step 1: Make the filter branch also rebuild the map

In `Config.lua`, change the final branch of `OnSettingChanged` so that when a
cache-affecting key (or `hiddenSources`) changes, the map is rebuilt alongside the
window. The cleanest form — fold the map rebuild into `InvalidateAndRefresh` so
there is one "the list content changed" path:

```lua
local function InvalidateAndRefresh()
	if addon.MountModel then
		addon.MountModel.InvalidateCache()
	end
	if addon.RefreshWindow then
		addon.RefreshWindow()
	end
	-- Map.Compute filters pins on row.include, which folds in every list filter
	-- (showCollected / showObtainableOnly / showUnusable / hiddenSources /
	-- showVendorIcons). Any change that invalidates the window model also changes
	-- which mounts should be pinned, so rebuild the pin set too.
	if addon.Map then
		addon.Map.Rebuild()
	end
end
```

Then delete the now-redundant special case for `showVendorIcons` (the block at
`Config.lua:54-59` in the excerpt above — the comment plus the
`if key == "showVendorIcons" and addon.Map then addon.Map.Rebuild() end`),
because `showVendorIcons` is in `CACHE_KEYS`, so it reaches
`InvalidateAndRefresh()` which now rebuilds the map. Update the trailing comment
on the final `if` so it reads roughly:

```lua
	-- groupBy / showCollected / showObtainableOnly / showUnusable / showGlobal /
	-- showVendorIcons or a hiddenSources toggle: the list content — and therefore
	-- the map pin set — changes, so invalidate the model cache and refresh both.
	if key == "hiddenSources" or CACHE_AFFECTING[key] then
		InvalidateAndRefresh()
	end
```

Note: `groupBy` is in `CACHE_KEYS` and does not affect the map; it will now
trigger a harmless `Map.Rebuild()` (recomputes the same pin set). That is
acceptable — keep the logic simple rather than special-casing `groupBy` out.

**Verify**: `luacheck .` → `0 warnings / 0 errors in 12 files`

### Step 2: Add a smoke assertion that a filter toggle rebuilds the map

The warm scenario in `tests/smoke.lua` already drives the options panel and the
map. Find the existing step near the end of the file titled
`"Filter by source: unchecking 'Show Vendor' hides vendor mounts"` (it toggles
`Stub.data.settings.show_vendor`). Immediately after that `step(...)` block, add a
new warm-only step that asserts a filter toggle goes through `Map.Rebuild`.

The stub counts pin placements in `Stub.data.worldPins` / `Stub.data.minimapPins`
and resets them to 0 on `RemoveAllWorldMapIcons` (which `Map.Refresh` calls at the
top of every rebuild). Use that: toggle a cache-affecting setting through the
panel binding and assert the map was recomputed. Model the structure on the
existing `"warm: showVendorIcons adds a map pin for the positioned vendor mount"`
step earlier in the file.

```lua
if SCENARIO == "warm" then
	step("filter toggle through the panel rebuilds the map pins", function()
		local s = Stub.data.settings
		Stub.data.zone, Stub.data.mapID = "Stormwind City", 84
		addon.db.showObtainableOnly = false
		addon.MountModel.InvalidateCache()
		addon.Map.Rebuild()

		-- A rebuild calls RemoveAllWorldMapIcons (resets the counter) then
		-- re-places pins. Flip a cache-affecting setting via its panel binding
		-- and confirm the pin set was recomputed, not left stale.
		local seenRebuild = false
		local realRemove = _G.LibStub("HereBeDragons-Pins-2.0").RemoveAllWorldMapIcons
		_G.LibStub("HereBeDragons-Pins-2.0").RemoveAllWorldMapIcons = function(...)
			seenRebuild = true
			return realRemove(...)
		end
		if s.showObtainableOnly then s.showObtainableOnly.set(true) end
		_G.LibStub("HereBeDragons-Pins-2.0").RemoveAllWorldMapIcons = realRemove

		check("toggling showObtainableOnly triggered a map rebuild", seenRebuild,
			"Map.Rebuild was not called from OnSettingChanged")
		if s.showObtainableOnly then s.showObtainableOnly.set(false) end
	end)
end
```

If the `s.showObtainableOnly` binding is nil in the stub (it is registered by
`Config.AddCheckbox`, so it should exist), the `check` for `seenRebuild` will
fail loudly — that itself is a useful signal. Do not add a nil-guard that skips
the assertion.

**Verify**: `python tests/run.py` → `All smoke scenarios passed.` and the new
check appears in the warm output as `ok  toggling showObtainableOnly triggered a
map rebuild`. Warm check count goes from 86 to 87.

### Step 3: Run the full suite

**Verify**: `./run-tests.ps1` → `All suites passed.`

## Test plan

- One new assertion in `tests/smoke.lua` (warm scenario): flipping a
  cache-affecting setting via its panel binding causes `Map.Rebuild` →
  `RemoveAllWorldMapIcons` to run. Structural pattern: the existing
  `"warm: showVendorIcons adds a map pin for the positioned vendor mount"` step.
- No Python test changes (Config/Map behaviour is not covered there).
- Verification: `python tests/run.py` → all pass, warm now 87 checks.

## Done criteria

ALL must hold:

- [ ] `luacheck .` → `0 warnings / 0 errors in 12 files`
- [ ] `python tests/run.py` → `All smoke scenarios passed.`; warm scenario shows
      87 checks and the new `toggling showObtainableOnly triggered a map rebuild`
      check passes
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK` (63)
- [ ] `./run-tests.ps1` → `All suites passed.`
- [ ] `grep -n "showVendorIcons" Mount_Tracker_Local_Zones/Config.lua` shows
      `showVendorIcons` is no longer given its own `Map.Rebuild()` call — only
      referenced in the trailing comment / reached via `CACHE_AFFECTING`
- [ ] Only `Config.lua` and `tests/smoke.lua` are modified (`git status`)
- [ ] `plans/README.md` status row for 001 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The `OnSettingChanged` function in `Config.lua` does not match the "Current
  state" excerpt (the file drifted since `0878181`).
- `Map.Compute` in `Map.lua` no longer checks `row.include` (the phase-9 model
  contract changed — this plan's premise is void).
- The smoke stub has no `RemoveAllWorldMapIcons` on the `HereBeDragons-Pins-2.0`
  library table, or no `Stub.data.settings.showObtainableOnly` binding after the
  options panel is set up — the test approach needs rethinking; report what you
  found.
- Any verification fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns this next:

- After this lands, **every** `CACHE_KEYS` entry triggers a `Map.Rebuild()` on
  change. If `Map.Rebuild` is ever made expensive again, revisit — or land plan
  003 first, which makes each rebuild cheap.
- If a new list filter is added, put its `db` key in `MountModel.CACHE_KEYS` and
  it will automatically drive both the window and the map. Do not add a second
  list.
- In-game check for the maintainer (deploy via the `deploy-addon` skill, then
  `/reload`): open the tracker in a zone with a mix of pinned mounts (e.g. The
  Storm Peaks). Open `/mtlz config`, toggle "Only show obtainable mounts" and a
  "Filter by source" checkbox. The world-map and minimap pins should update in
  lock-step with the tracker list — no zone change required. Then re-run the
  phase-9 checklist section 4.6 / 4.7 in `context/phase9-code-quality-refactor.md`.
