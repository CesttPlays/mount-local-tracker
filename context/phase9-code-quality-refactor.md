# Phase 9 — Code-quality refactor plan

Status: **SHIPPED 2026-08-31** — all workstreams WS1–WS10 landed in commit
`0878181` ("Phase 9: code-quality refactor (#3)"). Kept as the record of what
changed and the in-game checklist for future regressions.
In-game checklist (section 4): not separately recorded — re-run after the next
deploy.
Author: thermo-nuclear code-quality review, 2026-08-31
Scope: `Mount_Tracker_Local_Zones/` Lua modules (+ generator/tests where noted).
All changes are **behaviour-preserving** unless a workstream explicitly flags a
visible delta (WS2 rep number, WS3 drop-pin colour, WS4 source list).

---

## 0. Why

The addon works and the module split is sound, but three concepts are each
implemented 2–4 times and are already drifting:

| Concept | Copies today |
|---|---|
| "override wins over generated data" lookup | `MountModel.Curated`, `Obtainability.pick`/`.Input`, inline in `Core.VendorLocation`, inline in `Core.ShowMountMenu` |
| state → colour / "is this dimmed" | `Obtainability.STATE[*].color` + `Obtainability.Color`, **and** `Map` re-declares `COLOR_*` + `GATED_STATE` + hand mapping in `DressPin` |
| source-type order + labels | `MountModel.SOURCE_ORDER/LABEL/RANK`, `Config.SOURCE_FILTERS` (already diverged: no `rare`) |

Plus: one redundant full traversal of the candidate list per window rebuild
(`ZoneTally`), a fragile hand-maintained cache key, a stale-row bug in
`RefreshCachedStates`, a 653-line junk-drawer `Core.lua`, and dead `subcat`
plumbing.

Goal: fewer concepts, one home per concept, no new branches.

---

## 1. Constraints / working rules

- **Plan-before-code still applies per workstream.** This doc is the plan; each
  WS below is small enough to review as its own change.
- After **every** WS that touches addon Lua:
  1. `python tests/run.py` (smoke) — must stay green.
  2. `python -m pytest tests/` / `run-tests.ps1` if the generator or MountData
     shape changed (WS2 repFaction, WS10 subcat).
  3. Deploy (`deploy-addon` skill) → `/reload` → run the in-game checklist for
     that WS (section 4).
- **Do not** batch multiple workstreams into one commit. One WS = one commit,
  message `Phase 9: <ws short name>`.
- Smoke ≠ validated. Every WS lists explicit in-game checks.
- Keep the achievement sibling in mind but **do not** port changes there in this
  phase — land here first, backport later if it earns its keep.

---

## 2. Workstream summary & ordering

| # | Workstream | Files | Risk | Depends on |
|---|---|---|---|---|
| WS1 | `addon.Curated` — one curated-lookup helper | Core, MountModel, Obtainability, Config | low | — |
| WS2 | Obtainability data-shape cleanup | Obtainability, Overrides | low–med | WS1 |
| WS3 | Unify state→colour / dim model | Obtainability, Map | low (visual) | — |
| WS4 | One source-type model | MountModel, Config | low (visual) | — |
| WS5 | Extract `SourceBucket` / `ExpansionBucket` helpers | MountModel | low | WS4 |
| WS6 | Single-pass zone scan — delete `ZoneTally` | MountModel, Map | med | WS5 |
| WS7 | Explicit `BuildRow` options + derived cache key | MountModel | med | WS6 |
| WS8 | Fix stale rows in `RefreshCachedStates` | MountModel, Core | low | WS6/WS7 |
| WS9 | Extract `MountActions.lua` from `Core.lua` | Core → new file, TOC | low (mechanical) | WS1 |
| WS10 | Surface `subcat` as a tooltip line (Option A) | Obtainability, MountModel | low | WS1 |

**Recommended order:** WS1 → WS9 → WS3 → WS4 → WS5 → WS6 → WS7 → WS8 → WS2 → WS10.

Rationale:
- WS1 first: everything else reads curated data; get the helper in place.
- WS9 right after WS1: it *moves* the Core blocks that WS1 just touched
  (`VendorLocation`, `ShowMountMenu`); doing it early avoids re-touching them.
- WS3/WS4 are independent, low-risk, high-clarity — quick wins to build
  confidence before the model surgery.
- WS5 → WS6 → WS7 → WS8 is one connected sequence on `MountModel`'s core path;
  do them back-to-back so the contract only churns once.
- WS2 late: it's the only one that changes a static-data shape (`repFaction`),
  keep it isolated.
- WS10 last: tiny, independent, only needs `addon.Curated` from WS1.

---

## 3. Workstreams in detail

### WS1 — `addon.Curated(field, id)`

**Problem.** `MountData[field][id]` with `Overrides[field][id]` winning is the
addon's most-used primitive and exists 4×:
- `MountModel.lua:198-207` `Curated` (exported, used by `Config.lua:162`)
- `Obtainability.lua:37-46` `pick`, exported as `Obtainability.Input` (**no
  external consumer — dead export**)
- `Core.lua:258-259` inline in `VendorLocation`
- `Core.lua:284-285` inline in `ShowMountMenu`

**Target.** One function in `Core.lua`, in a new `-- Curated data` section placed
**before** the "Mount helpers" section (VendorLocation needs it):

```lua
-- Overrides.lua wins over the generated MountData for the same [field][id].
-- Both tables load after Core, so the lookups resolve lazily at call time.
local function Curated(field, id)
    local ov = addon.MountOverrides and addon.MountOverrides[field]
    if ov and ov[id] ~= nil then
        return ov[id]
    end
    local md = addon.MountData and addon.MountData[field]
    return md and md[id]
end
addon.Curated = Curated
```

**Edits.**
- `Core.lua`: add the above; in `VendorLocation` replace the two-branch lookup
  with `local vendor = addon.Curated("vendor", mountID)`; in `ShowMountMenu`
  replace the `point` lookup with `addon.Curated("points", mountID)`.
- `MountModel.lua`: delete local `Curated` (198-206) and the
  `MountModel.Curated = Curated` export; add `local Curated = addon.Curated`
  near the top (after the `local SafeApiCall …` block). Internal call sites
  (`PointFor`, `BuildRow`, `ZoneTally`) unchanged — they still call `Curated`.
- `Obtainability.lua`: delete `local function pick` (37-44) and
  `Obtainability.Input = pick` (46); add `local pick = addon.Curated` at the top.
  All internal `pick(...)` calls unchanged.
- `Config.lua:162`: `addon.MountModel.Curated("source", mountID)` →
  `addon.Curated("source", mountID)`; drop the `addon.MountModel and` guard.

**Load-order check.** TOC order is `Core → MountData → Overrides → Obtainability →
MountModel → … → Config`. `addon.Curated` is assigned at Core load; every
`local X = addon.Curated` runs strictly later. ✔

**Risk.** Low. Pure de-duplication, identical semantics.

**Verify.** Smoke green. In-game: tooltips, list states, context-menu waypoint
entries, vendor pins all unchanged (checklist 4.1).

---

### WS9 — extract `MountActions.lua` (do right after WS1)

**Problem.** `Core.lua` is 653 lines and owns ~10 responsibilities. The
mount-*interaction* layer is a cohesive unit that belongs on its own.

**Target.** New `Mount_Tracker_Local_Zones/MountActions.lua` containing, moved
verbatim from `Core.lua` (roughly lines 141–389):
- `TrimIcon` — **stays in Core** (also used by generic UI); or move to a
  `UI.lua` later. For now leave in Core.
- `MountInfo`, `MountName`, `OpenMount`, `AddObtainabilityLines`
- `SetMountHidden`
- `PlaceUserWaypoint`, `SetTomTomWaypoint`, `VendorLocation`
- `ShowMountMenu`, `BindMount`

Keep the same `addon.*` export names so no consumer changes.

**Edits.**
- Create `MountActions.lua` with `local addonName, addon = ...` header, the
  section comment, and the moved functions + their `addon.X = X` exports.
- `Core.lua`: delete the moved block; keep `TrimIcon`, `SafeApiCall*`, `Print`,
  `DebugPrint`, `Debounced`, readiness, location, lifecycle, slash, events.
- `MountActions.lua` uses `addon.Curated`, `addon.SafeApiCall*`, `addon.Print`,
  `addon.TrimIcon`, `addon.Obtainability` — all already on `addon`. ✔
- TOC: insert `MountActions.lua` **after** `MountModel.lua` and **before**
  `ListView.xml` (it needs `addon.Obtainability`; ListView/Map/Window need
  `addon.BindMount`).
- `tests/` stub/harness: confirm `tests/init.lua` loads files from the TOC list
  (it does — it parses the `.toc`). No test change expected; run smoke to
  confirm the new file loads clean.

**Result.** `Core.lua` ≈ 400 lines of genuine lifecycle/event/slash glue;
`MountActions.lua` ≈ 250 lines.

**Risk.** Low, mechanical. Main hazard: a missed local dependency — the smoke
harness will throw immediately if so.

**Verify.** Smoke green (it drives every slash command + window + menu path).
In-game checklist 4.1 again (same surface as WS1).

---

### WS3 — unify state → colour / "dimmed"

**Problem.** `Obtainability.STATE` already holds per-state colour and
`Obtainability.Color(state)` is used by `ListView.lua:131`. `Map.lua:19-32`
re-declares `COLOR_AVAILABLE/FARMABLE/DROP/GATED`, `ALPHA_GATED`, a `GATED_STATE`
set, and re-derives the mapping in `DressPin` (`Map.lua:113-129`). Comments say
"mirrors the ListView row colours" — a written-down drift hazard. `COLOR_DROP`
is **already** a different grey (`0.90³` vs `STATE.drop` `0.87/0.86/0.81`).

**Target.**
- `Obtainability.lua`: add `dim = true` to the four gated states in `STATE`
  (`quest_gated`, `rep_gated`, `achievement_gated`, `reset_locked`). Add:
  ```lua
  function Obtainability.IsDimmed(state)
      local e = STATE[state]
      return e and e.dim or false
  end
  ```
- `Map.lua`: delete `COLOR_AVAILABLE/FARMABLE/DROP/GATED` and `GATED_STATE`; keep
  `ALPHA_GATED` local (it's a map-rendering choice). `DressPin` becomes:
  ```lua
  local r, g, b = addon.Obtainability.Color(entry.state)
  local dim = addon.Obtainability.IsDimmed(entry.state)
  pin.texture:SetVertexColor(r, g, b)
  pin.texture:SetAlpha(dim and ALPHA_GATED or 1)
  ```

**Visible delta.** World/minimap "drop" pins shift from `0.90` grey to the
slightly warmer/darker `STATE.drop` parchment — now matching the list rows
exactly. This is the intended outcome; note it in the changelog.

**Risk.** Low. Cosmetic, and it makes two surfaces consistent.

**Verify.** In-game: open world map in a zone with pins of several states
(e.g. Storm Peaks — Time-Lost Proto-Drake `drop`, a vendor mount `available`,
a rep-locked mount `rep_gated`); pin colours should match the tracker rows for
the same mounts. Checklist 4.3.

---

### WS4 — one source-type model

**Problem.** `MountModel.lua:28-44` (`SOURCE_ORDER`, `SOURCE_LABEL`,
`SOURCE_RANK`) is canonical. `Config.lua:11-26` re-lists it as `SOURCE_FILTERS`
and derives a second `SOURCE_LABEL`. They must agree so filter checkboxes match
list headers — and they don't: `SOURCE_ORDER` has `rare` and `achievement`,
`SOURCE_FILTERS` has neither.

**Investigation result.** Generated `MountData.source` values in practice:
`vendor, drop, instance, zonedrop, quest, worldevent, profession`. `Overrides`
`source` values: all `drop`. So `source == "rare"` and `source == "achievement"`
are **unreachable** — `rare` is a `subcat`, achievement-gating is an
`achievementID` field + Obtainability state, not a source. `SOURCE_ORDER`'s
`rare`/`achievement` entries are dead.

**Target.** Canonical list, exported from `MountModel`:
```lua
MountModel.SOURCE_ORDER = { "instance", "drop", "vendor", "quest",
                            "zonedrop", "worldevent", "profession", "other" }
-- SOURCE_LABEL / SOURCE_RANK built from it as today
function MountModel.SourceLabel(s) return SOURCE_LABEL[s] or "Other" end
```
- Drop `rare` and `achievement` from `SOURCE_ORDER`/`SOURCE_LABEL` (keep the
  `rare = "Rare Drop"` alias out entirely; `drop` already means "Rare Drop").
- `GroupRows` `SOURCE_LABEL[row.source] or "Other"` still works (unknown →
  "Other" bucket, `SOURCE_RANK.other`).
- `Config.lua`: delete `SOURCE_FILTERS` + its derived `SOURCE_LABEL`; in
  `AddSourceFilters` iterate `addon.MountModel.SOURCE_ORDER` (skip `"other"` if
  you don't want a "Show Other" box — decide; recommend **keep** it so hiding
  the misc bucket is possible). `SourceBucketLabel` in Config uses
  `addon.MountModel.SourceLabel`.

**Visible delta.** Options panel "Filter by source" section: same 9 rows minus
none / plus "Show Other" if you keep `other` (recommended). No functional change
for existing users; `hiddenSources` keys are unchanged strings.

**Risk.** Low. Watch the `sourceFilterProxy` metatable in `Config.lua:112-129` —
it keys on `show_<sourcetype>`; iterating the canonical order must produce the
same `sourceType` strings (it will).

**Verify.** In-game: options panel source section renders; unchecking "Show
Vendor" removes the Vendor group from the list; re-checking restores it.
Checklist 4.4.

---

### WS5 — `SourceBucket` / `ExpansionBucket` helpers

**Problem.** `GroupRows` (`MountModel.lua:314-360`) inlines the grouping-key
logic with an unreadable `and/or` chain for expansions:
```lua
local exp = tonumber(row.expansion)
exp = (exp and exp >= 0) and exp or (exp and 0) or nil
key = "e:" .. tostring(exp or "x")
label = row.expansion ~= nil and ExpansionLabel(exp) or "Other"
rank = exp and -exp or 99
```
`ExpansionLabel` (`:66-75`) **already** clamps `n < 0 → 0`; this re-implements the
clamp a second way.

**Target.** Two pure helpers, each returning `key, label, rank`:
```lua
local function ExpansionBucket(raw)          -- groupBy == "expansion"
    local n = tonumber(raw)
    if not n then return "e:x", "Other", 99 end
    if n < 0 then n = 0 end
    return "e:" .. n, EXPANSION_LABEL[n] or "Other", -n
end

local function SourceBucket(source)          -- groupBy == "source"
    local s = source or "other"
    return "s:" .. s, SOURCE_LABEL[s] or "Other",
           SOURCE_RANK[s] or SOURCE_RANK.other
end
```
`GroupRows` inner loop becomes:
```lua
local key, label, rank =
    (groupBy == "expansion" and ExpansionBucket or SourceBucket)(
        groupBy == "expansion" and row.expansion or row.source)
if isGlobal then key = "g:" .. key end
```
(or a plain `if/else` — keep it boring.)

**Note.** `ExpansionBucket` folds the `EXPANSION_LABEL[n] or "Other"` that
`ExpansionLabel` also does; consider deleting `ExpansionLabel` and pointing its
one other caller (there isn't one outside `GroupRows` — confirm with grep) at
`ExpansionBucket`. If `ExpansionLabel` has no other caller, delete it.

**Risk.** Low. Same keys, same ranks, same labels — assert via smoke's
`groupBy = expansion` step (`tests/smoke.lua:294`).

**Verify.** In-game: `/mtlz` → options → Group by → "By expansion"; groups appear
newest-first, one "Classic" bucket (no split from a stray negative id), unknown
last. Switch back to "By source". Checklist 4.5.

---

### WS6 — single-pass zone scan, delete `ZoneTally`

**Problem.** `MountModel.GetZoneMounts` runs the candidate list through
`GroupRows` → `BuildRow` → `Obtainability.Evaluate`, then **`ZoneTally(ids)`
(`:427-445`) loops the same ids again**, re-calling `MountInfo` and `Evaluate`.
`ZoneTally` is a hand-reimplementation of work `BuildRow`/`FinishGroup` already
do. ~2× the API calls per rebuild.

They diverge only because `BuildRow` *filters* (collected / faction / unusable /
hidden-source / obtainable-only) and the summary wants **unfiltered** zone totals
(collected mounts counted even when hidden from the list).

**Target — the code-judo move.** Stop filtering *inside* `BuildRow`. `BuildRow`
always returns a row (or `nil` only for a not-a-real-mount id), plus an
`include` flag and enough fields to tally:

```lua
-- returns row or nil.  row.include == false => count it, don't list it.
local function BuildRow(mountID)
    ... name guard: nil if not a real mount ...
    local row = { id=…, name=…, isCollected=…, isUsable=…, source=…,
                  expansion=…, state=…, detail=…, sortRank=…, point=… }
    row.include =
        (db.showCollected or not row.isCollected)
        and not (db.hidden and db.hidden[mountID])
        and not (db.hiddenSources and db.hiddenSources[row.source])
        and (db.showUnusable or row.isUsable)
        and (row.isCollected or not db.showObtainableOnly
             or OBTAINABLE[row.state])
        and factionOK
    return row
end
```

Then in `GetZoneMounts`, **one** pass builds a `rows` array; from it:
- `GroupRows` takes `rows` (already built) instead of `ids`, skips
  `not row.include`.
- zone tally = fold over the same `rows`: `zoneTotal = #realRows`,
  `zoneCollected = count(isCollected)`, `zoneAvailable =
  count(state=="available" and not isCollected)`.

Delete `ZoneTally` entirely (~20 lines).

**Consumer impact — `Map.Compute` (`Map.lua:47-87`).** It calls
`MountModel.BuildRow(mountID)` and relies on `nil` for filtered/collected mounts
(`if not row or row.isCollected or row.state == "collected" or not row.point`).
Update to `if not row or not row.include or row.isCollected or not row.point`.
`include` already encodes hidden / hiddenSources / unusable, which Map arguably
*should* respect (it doesn't today — minor behaviour fix, note it).

**`GroupRows` signature change.** `GroupRows(rows, groupBy, isGlobal)` — callers:
`GetZoneMounts` (zone + global), that's it. `MountModel.GroupRows` is exported
but grep shows no external caller — safe to change. If you want to keep the
`ids`-taking export for Map's global pass, have `GetZoneMounts` build rows for
both zone and global ids in the single pass and slice.

**Risk.** Medium — this is the central path. Mitigations: smoke exercises
`showCollected`, `showObtainableOnly`, `showUnusable`, `hiddenSources`,
`showGlobal`, both `groupBy` values, and the `/mtlz list` deep path in the "warm"
scenario. Add one smoke assertion: summary counts (`zoneCollected/zoneTotal`)
match a hand-known fixture zone.

**Verify.** In-game, in a zone with a mix (Northrend Dalaran or a Draenor zone):
- summary line "N / M collected · K available · … account" numbers look right
  with `showCollected` OFF and ON (totals must not change when you toggle it).
- Turn on "Only show obtainable"; list shrinks, summary totals unchanged.
- Hide a mount (right-click → Hide); it leaves the list; summary total drops by
  one (it's genuinely gone, not just filtered) — **confirm this matches intent**;
  if hidden mounts should still count toward the zone total, keep `hidden` out of
  the tally fold.
Checklist 4.6.

---

### WS7 — explicit `BuildRow` options + derived cache key

**Problem.** `GetZoneMounts` cache key (`:454-462`) is a hand-concatenated list
of `db` fields that must mirror **every** field `BuildRow` reads. It already
**omits `db.showVendorIcons`**, which `BuildRow:268` reads to set `row.point`
for vendor mounts. Toggling "Show vendor icons" with the window open
(`Config.lua:34` routes it to `Map.Rebuild` only) leaves stale `row.point` →
context-menu "Place map pin (vendor)" appears/disappears wrongly until the next
invalidation.

**Target.** One declared list of cache-affecting settings, used to build both the
key and (optionally) an `opts` table passed into `BuildRow`:

```lua
local CACHE_KEYS = { "groupBy", "showCollected", "showObtainableOnly",
                     "showGlobal", "showUnusable", "showVendorIcons" }

local function cacheKey(mapID)
    local db = addon.db or EMPTY
    local parts = { tostring(mapID) }
    for _, k in ipairs(CACHE_KEYS) do parts[#parts+1] = tostring(db[k]) end
    parts[#parts+1] = hiddenSourcesHash()
    parts[#parts+1] = hiddenHash()          -- see below
    return table.concat(parts, "|")
end
```

Also fold `db.hidden` into the key (today a hidden mount is dropped via
`Core.SetMountHidden` → `InvalidateCache`, so it's *handled*, but making it part
of the key removes the "must remember to call InvalidateCache" coupling).
`hiddenHash()` = sorted concat of hidden ids, same shape as `hiddenSourcesHash`.

**`Config.lua:29-52` `OnSettingChanged`.** Simplify: any key in `CACHE_KEYS`
(minus the map-only ones) → `InvalidateCache()` + `RefreshWindow()`.
`showVendorIcons` currently only triggers `Map.Rebuild` — it must **also**
invalidate the model cache now. `showMapIcons` / `showMinimapIcons` stay
map-only.

**Risk.** Medium-low. The failure mode is a stale window, not a crash. Smoke
toggles most of these already.

**Verify.** In-game: open window in a zone with a buyable mount; toggle "Show
vendor icons" in options; the mount's right-click menu gains/loses "Place map pin
(vendor)" **immediately** (no zone change needed). Checklist 4.7.

---

### WS8 — fix stale rows in `RefreshCachedStates`

**Problem.** `MountModel.RefreshCachedStates` (`:515-534`) refreshes cached rows
in place via `BuildRow(row.id)` on `NEW_MOUNT_ADDED` / usability change. If a
mount was just collected and `showCollected` is off, `BuildRow` returns a row
with `include == false` (post-WS6) / `nil` (today) and the `if fresh` guard skips
it — the stale "not collected" row **stays in the list** until a zone change,
because the `GetZoneMounts` cache key has no collection-state component.
`NEW_MOUNT_ADDED` is exactly when that row should leave.

**Target.** Split the two triggers in `Core.lua`:
- `NEW_MOUNT_ADDED` (membership can change): `MountModel.InvalidateCache()` +
  `addon.RefreshWindow()` — same as the zone path. The debounce
  (`RequestStateRefresh`, `:494`) stays; just change its body, or route
  `NEW_MOUNT_ADDED` to `RequestRefresh` and keep `RequestStateRefresh` for
  usability only.
- `MOUNT_JOURNAL_USABILITY_CHANGED` (state only, no add/remove): keep the cheap
  in-place `RefreshCachedStates`, but make its contract explicit in the comment:
  *"in-place refresh; never adds or removes rows. Only valid when the candidate
  set is unchanged."* And in the loop, if `fresh` is `nil`/`not fresh.include`,
  fall back to `InvalidateCache()` + bail rather than silently keeping the stale
  row.

**Risk.** Low. Worst case is an extra full rebuild on `NEW_MOUNT_ADDED`, which is
rare (once per mount collected) and already debounced 0.5s.

**Verify.** In-game: open the tracker in a zone that lists an uncollected mount
you can obtain on the spot (a cheap vendor mount, or use a GM/collected test
char). With "Show collected" OFF: collect it → within ~1s the row disappears
from the list and the summary "collected" count ticks up. With "Show collected"
ON: the row stays but recolours to the grey "collected" state. Checklist 4.8.

---

### WS2 — Obtainability data-shape cleanup

**Problem.** `Obtainability.lua` carries dual-shape access for curated tables
that ship exactly one shape:
- `vendor.cost or vendor[5]`, `vendor.currencyID or vendor[6]` (`:169-170`,
  `:114-115`), `vendor.npc or vendor.name` (`:116`) — every `vendor` entry
  (Overrides + the empty `MountData.vendor`) uses **named** keys; `Core.
  VendorLocation` reads named only. The `[5]`/`[6]`/`.name` branches are dead.
- `repFaction.factionID or repFaction[1]`, `repFaction.standing or
  repFaction[2]` (`:156-157`) — here the **data is the tuple** (`{1173, 42000}`)
  so the *named* branch is dead.
- `Obtainability.lua:68-69`:
  `data.currentReactionThreshold and data.currentStanding or data.currentStanding`
  is `X and Y or Y` ≡ `data.currentStanding` — a no-op.

**Target.**
- `vendor`: use `vendor.cost`, `vendor.currencyID`, `vendor.npc` directly. Delete
  the positional/`.name` fallbacks in `Evaluate` and `VendorDetail`.
- `repFaction`: **convert to named** for readability (only ~5 entries, all in
  `Overrides.lua:140-146`; `MountData.repFaction` is an empty stub, generator
  doesn't emit it — confirm with grep). New shape:
  `[398] = { factionID = 1173, standing = 42000 }`. Update the `Overrides.lua`
  header doc (`:18-19`) and `Evaluate:156-157` to `repFaction.factionID` /
  `repFaction.standing`.
  - *Alternative* if you'd rather not touch data: keep the tuple, just delete the
    dead `.factionID or` / `.standing or` and read `repFaction[1]`/`[2]` with a
    one-line comment. Lower churn, slightly worse readability. **Recommend named.**
- Line 68-69: replace with `local standing = data.currentStanding`.
  **Decided:** plain `data.currentStanding` — matches current actual behaviour
  (the old expression already collapsed to it), no displayed-number change.
  Drop the local entirely if you prefer: `return data.currentStanding,
  threshold, data.currentStanding >= threshold, nil`.

**Risk.** Low–medium (only because it's a saved-data-adjacent shape). No
`SavedVariables` impact — `repFaction` is static addon data, not user state.
Bump nothing. `test_mountdata.py:164` lists expected `MountData` keys — unchanged
(repFaction stays an empty stub there).

**Verify.** In-game, a rep-gated mount (Brown Riding Camel — Ramkahen Exalted, or
Tamed Skitterfly — Dragonscale Renown 25): tooltip + row show "Reputation needed
· Renown N / need M" (major faction) or "current / needed reputation" (classic
faction) with sane numbers. A gold vendor mount (Winged Steed of the Ebon Blade):
shows "available now" with the gold cost formatted, or "reputation needed" when
you can't afford it. Checklist 4.2.

---

### WS10 — surface `subcat` as a tooltip line

**Decided:** Option A. Keep `subcat` and the generator's instance-type work;
surface it as a dim tooltip line. Option B (full removal) is kept below only as
the rejected alternative / future reference.

**Problem.** `subcat` (`"dungeon"` / `"raid"` / `"rare"`) is set in
`BuildRow` (`MountModel.lua:259`), documented in `Overrides.lua:9`, emitted by
the generator (`tools/generate_mount_zones.py` — `INSTANCE_SUBCAT`, `render_lua`
`subcat` block), asserted by `tests/test_generator.py` (~6 assertions) and
`tests/test_mountdata.py:106`, and occupies ~70 lines of `MountData.lua`. It is
**read nowhere in the addon**.

**Target (Option A).** In `Obtainability.AddTooltipLines`, for mounts whose
`source == "instance"`, append a dim context line from `subcat`:
`{ dungeon = "Dungeon drop", raid = "Raid drop", rare = "Rare drop" }`. ~5 lines,
placed after the existing `result.detail` / `note` lines, guarded so it only
shows when there's a subcat and it isn't already implied by `result.detail`.

`AddTooltipLines` already has `mountID`; add `local subcat = pick("subcat",
mountID)` (i.e. `addon.Curated` post-WS1). No `MountModel` change needed —
`BuildRow` keeps setting `row.subcat` (or drop it from the row and read it only
in the tooltip; recommend the latter, so `subcat` has exactly one reader).

**Deferred (not this phase):** splitting the "Dungeon & Raid" group into
"Dungeon" / "Raid" via `SourceBucket` (WS5) keyed on `source .. subcat`. Nicer,
more work, revisit if raid/dungeon separation proves useful in play.

**Rejected alternative — Option B, remove `subcat` end-to-end.**
- `MountModel.lua`: drop `subcat = Curated(...)` from `BuildRow` and the doc
  comment.
- `tools/generate_mount_zones.py`: remove `INSTANCE_SUBCAT`, the `subcat` dict,
  its `build()` return slot, `render_lua` param + block, the summary string.
- `tests/test_generator.py`: delete the ~6 subcat assertions / fixture fields.
- `tests/test_mountdata.py`: delete `test_subcat_values_are_non_empty_strings`;
  remove `"subcat"` from the expected-keys list (`:164`).
- Regenerate `MountData.lua` (`refresh-gamedata` skill) — the `subcat` block
  disappears (~70 lines).
- `Overrides.lua`: delete the `subcat` block (`:48-56`) and doc line.

**Verify.** In-game: hover a raid-drop mount (Invincible, Ashes of Al'ar) →
tooltip shows "Raid drop"; a dungeon mount (Raven Lord) → "Dungeon drop"; a
plain rare (Time-Lost Proto-Drake, `source == "drop"`) → no such line. Smoke +
generator tests green.

---

## 4. In-game verification checklists

Run the matching block after deploying each WS. Baseline: `/mtlz` opens the
tracker, `/mtlz debug` on for the zone-id line.

### 4.1 — WS1 & WS9 (curated helper / file extraction)
- [ ] `/mtlz` opens; list populates for the current zone.
- [ ] Hover a mount row → tooltip shows name + obtainability block.
- [ ] Right-click a rare-drop mount (Storm Peaks → Time-Lost Proto-Drake) →
      menu has "Place map pin", "Set TomTom waypoint" (if TomTom loaded).
- [ ] Right-click a vendor mount → menu has "… (vendor)" variants.
- [ ] "Hide this mount" removes it; options → Hidden mounts → Restore brings it
      back.
- [ ] `/mtlz list` prints groups to chat; `/mtlz map` reports pin count (debug).
- [ ] No Lua errors on login or `/reload`.

### 4.2 — WS2 (obtainability shapes)
- [ ] Rep mount (Brown Riding Camel): row/tooltip "Reputation needed · …" with a
      believable number; after hitting Exalted it flips to "available"/gold cost.
- [ ] Major-faction mount (Tamed Skitterfly): "Renown N / need 25".
- [ ] Gold vendor mount (Winged Steed): "available now · 250,000g" (or "…
      needed" when broke — test by checking on a low-gold alt).
- [ ] Currency vendor mount if any: cost shows with "(currency)".

### 4.3 — WS3 (colour unification)
- [ ] World map in Storm Peaks: pin colours for Time-Lost (drop / parchment),
      a rep mount (dim reddish), a vendor mount (green) match the tracker rows
      for those same mounts.
- [ ] Minimap pins same.
- [ ] Gated pins visibly dimmer (alpha) than active ones.

### 4.4 — WS4 (source model)
- [ ] Options → "Filter by source": rows render, labels match the list's group
      headers.
- [ ] Uncheck "Show Vendor" → Vendor group vanishes from the list; re-check →
      returns.
- [ ] "Show Other" (if kept) hides/shows the misc bucket.

### 4.5 — WS5 (bucket helpers)
- [ ] Group by → "By expansion": groups newest-first, single "Classic" bucket,
      "Other" last.
- [ ] Group by → "By source": unchanged from before.

### 4.6 — WS6 (single-pass scan)
- [ ] Summary "N / M collected" — toggle "Show collected" on/off: **M does not
      change**, only which rows are listed.
- [ ] "Only show obtainable": list shrinks, summary M unchanged.
- [ ] "K available" count matches the number of green rows visible.
- [ ] Hide a mount → decide expected: total drops by one (gone) — confirm that's
      the intent.
- [ ] `showGlobal` on: Global divider + groups appear; counts sane.

### 4.7 — WS7 (cache key)
- [ ] Window open in a zone with a buyable mount; toggle "Show vendor icons" →
      that mount's right-click menu gains/loses "Place map pin (vendor)"
      immediately.
- [ ] Toggle each "Mount list" option with the window open → list updates
      without a zone change.

### 4.8 — WS8 (stale rows)
- [ ] "Show collected" OFF: collect a listed mount → row disappears < 1s,
      summary "collected" +1.
- [ ] "Show collected" ON: row stays, recolours to grey "collected".
- [ ] Usability change (learn a class that can use a dimmed mount, or faction
      transfer test) → row un-dims without a full reload.

### 4.10 — WS10 (subcat tooltip line)
- [ ] Hover a raid-drop mount (Invincible / Ashes of Al'ar) → tooltip has a dim
      "Raid drop" line.
- [ ] Hover a dungeon mount (Raven Lord) → "Dungeon drop".
- [ ] Hover a plain open-world rare (Time-Lost Proto-Drake) → no such line.
- [ ] Line doesn't duplicate info already in the detail/note lines.

---

## 5. Smoke-test additions (land with the relevant WS)

- WS4: assert `addon.MountModel.SOURCE_ORDER` exists and every entry has a label;
  assert `Config` source-filter count == `#SOURCE_ORDER` (minus `other` if
  skipped).
- WS6: pick a fixture zone in `tests/stub.lua` with a known mount mix; assert
  `MountModel.Summary()` returns the expected `zoneTotal` / `zoneCollected`
  before and after flipping `showCollected` (must be equal).
- WS8: after `Harness.fireEvent("NEW_MOUNT_ADDED")` with a stub mount flipped to
  collected and `showCollected=false`, assert the row is gone from
  `GetZoneMounts()`.
- WS10 (Option A): assert the tooltip stub captured a "Raid drop" / "Dungeon
  drop" line for a subcat'd instance mount.

---

## 6. Rollback

Each WS is one commit. `git revert <sha>` is clean for WS1–WS9 (no data-shape
migration). WS2's `repFaction` rename and WS10 Option B touch `Overrides.lua` /
`MountData.lua` / the generator — revert those together with a regenerate if
already refreshed. No `SavedVariables` version bump is needed anywhere in this
phase (no user-state shape changes); leave `defaults.version = 1`.

---

## 7. Out of scope for phase 9 (note for later)

- Backporting any of this to `achivement-local-tracker`.
- `Window.PrintZoneMountListToChat` vs `RefreshTrackerWindow` partial overlap —
  acceptable (chat vs frame), leave it.
- `SafeApiCall` / `SafeApiCallMulti` / `MountInfo` double-guarding — defensive,
  cheap, leave it.
- A `UI.lua` for `TrimIcon` + shared frame helpers — only if a third surface
  needs them.
