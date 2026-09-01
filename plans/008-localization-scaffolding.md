# Plan 008: Add AceLocale-3.0 + `Locales/` scaffolding + test/lint support

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If
> anything in "STOP conditions" occurs, stop and report — do not improvise.
> When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat 8188db1..HEAD -- Mount_Tracker_Local_Zones/Mount_Tracker_Local_Zones.toc .gitignore .luacheckrc tests/`
> If any of those changed since this plan was written, compare the "Current
> state" excerpts against the live files before proceeding; on a mismatch,
> treat it as a STOP condition.

## Provenance

Plans `008`–`010` add **localization (i18n)** to the addon. They are a direct
port of the sibling repo's localization batch
(`achivement-local-tracker/plans/005`–`007`, written 2026-08-31), re-derived
against this repo's `main` at commit `8188db1` on 2026-09-01. The sibling plans
were the design exploration; this port only re-maps them to the mount addon's
file set, string list, slash command (`/mtlz`), folder name
(`Mount_Tracker_Local_Zones`, correctly spelled) and saved-variable key
(`MountTrackerLocalZonesDB`).

Plans `001`–`007` in this folder are an unrelated `improve`-audit batch
(map/obtainability cleanups + the achievement→zone resolver spike). The
localization batch is numbered `008`–`010` only to avoid collision; there is no
dependency either way.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (no displayed string changes; adds an unused-but-exercised layer)
- **Depends on**: none
- **Category**: i18n infrastructure
- **Planned at**: commit `8188db1`, 2026-09-01

## Why this matters

The addon is heading for a CurseForge release (see
`context/immediate-next-steps.md`) with no localization support at all. This
plan lays the foundation — the `addon.L` translation table, the `Locales/` file
tree, and the test/lint changes that keep the suite green — so that plan 009 can
move strings onto it and plan 010 can automate translation sync. After this plan
the addon still shows exactly the same English text; the only observable change
is that `addon.L` exists and the smoke harness loads the locale files.

AceLocale-3.0 was chosen (over a hand-rolled table) because it is the standard
WoW i18n idiom, it is tiny, it only needs LibStub (already vendored), and its
`L["English"] = true` / fallback-to-default semantics are exactly what we want.
It is already vendored in sibling repos (`Mechanic/Mechanic/Libs/AceLocale-3.0/`).

## Locked design decisions (inherited from the sibling batch)

| Choice | Decision |
| --- | --- |
| i18n library | **AceLocale-3.0**, vendored (committed) under `Libs/`. Needs only LibStub. |
| Key convention | Key = the English source string. `enUS.lua` uses the AceLocale idiom `L["English"] = true`. |
| Translations location | Static, committed `Locales/<locale>.lua` — works in a dev checkout, not just packaged builds. |
| Language-override setting | **No.** Addon language = `GetLocale()`; AceLocale falls back enGB→enUS and any→enUS automatically. |
| Locales shipped | `enUS` (base) + stubs `deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW`. |
| `.pkgmeta` | No functional change — no `@localization@` tokens, so the packager stays out of localization; `Locales/` ships as ordinary files (it is not in the `.pkgmeta` `ignore:` list). |

## Out of scope for this plan

- Any of the ~90 hardcoded strings at their call sites — that is plan 009.
- `.pkgmeta`, `README.md`, `CURSEFORGE.md` — untouched here (docs are plan 010,
  and gated on plan 009's in-game pass per the repo's README rule).
- `MountData.lua`, `Overrides.lua`, `tools/generate_mount_zones.py`,
  `refresh-mount-data.yml` — pure integer/enum data, no translatable text.
- **Curated data strings** shown to the user but sourced from `Overrides.lua`,
  not code literals: the `lockout` cadence words (`"daily"` / `"weekly"`),
  `dropChance` text, and free-text `note` values. These render through
  `Obtainability.lua` but localizing datamined/curated *data* is out of scope for
  the whole batch, same rationale as `MountData.lua`. Noted again in plan 009.
- Slash sub-commands (`reset/list/config/debug/map/show/toggle`); STATE tokens
  (`available/farmable/drop/quest_gated/rep_gated/achievement_gated/reset_locked/collected`);
  `windowStyle` values (`stylized/classic`); `groupBy` values (`source/expansion`);
  source-type keys (`instance/drop/vendor/quest/zonedrop/worldevent/profession/other`);
  `MTLZ_` setting-ID prefix; `s:` / `e:` / `g:` group-key prefixes;
  `Alliance` / `Horde` API constants — never localized.

## Current state

### `Mount_Tracker_Local_Zones/Mount_Tracker_Local_Zones.toc`

```
## Interface: 120100
## Title: Mount Tracker: Local Zones
## Author: Cestt
## Version: 0.1.0
## SavedVariables: MountTrackerLocalZonesDB
## OptionalDeps: !Mechanic, TomTom

Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
Libs\LibDataBroker-1.1\LibDataBroker-1.1.lua
Libs\HereBeDragons\HereBeDragons-2.0.lua
Libs\HereBeDragons\HereBeDragons-Pins-2.0.lua
Libs\HereBeDragons\HereBeDragons-Migrate.lua
Libs\LibDBIcon-1.0\LibDBIcon-1.0.lua

Core.lua
MountData.lua
Overrides.lua
Obtainability.lua
MountModel.lua
MountActions.lua
ListView.xml
ListView.lua
Window.lua
Map.lua
Config.lua
MinimapButton.lua

#@do-not-package@
Mechanic.lua
#@end-do-not-package@
```
No `## Notes`. No `## X-Curse-Project-ID` (the CF project does not exist yet).
No `Locales\` lines.

### `.gitignore` (embedded-libraries block)

```
# Embedded libraries.
# LibStub, CallbackHandler-1.0, LibDBIcon-1.0 are vendored (committed) -- no maintained
# non-legacy git source. LibDataBroker-1.1 + HereBeDragons are fetched by the packager
# (.pkgmeta); kept on disk for local testing but not committed. libs.json is a Mechanic
# tool file, not shipped (see .pkgmeta ignore).
Mount_Tracker_Local_Zones/Libs/*
!Mount_Tracker_Local_Zones/Libs/LibStub/
!Mount_Tracker_Local_Zones/Libs/CallbackHandler-1.0/
!Mount_Tracker_Local_Zones/Libs/LibDBIcon-1.0/
```

### `Mount_Tracker_Local_Zones/Core.lua` line 1

```lua
local addonName, addon = ...
```

### `.luacheckrc`

`exclude_files = { "Mount_Tracker_Local_Zones/Libs/", "tests/", ".claude/" }`
— a vendored lib under `Libs/` is not linted, and `tests/` is not linted.
`read_globals` has no `GetLocale`. There is also a
`files["**/*.lua"] = { globals = { "SLASH_MTLZ1", "SlashCmdList",
"MountTrackerWindow", "MountTrackerLocalZonesDB" } }` block — unaffected.

### `tests/harness.lua` (line ~25)

```lua
if rel:match("%.lua$") and not rel:match("^Libs/") then
```
The harness reads the load order from the `.toc` but **skips every `Libs/`
line** — the stub fakes `LibStub` instead of loading real libraries. So a
vendored AceLocale is *not* executed in the smoke tests; the stub must fake it.
Files under `Locales/` are **not** `Libs/`, so they *do* load through the
harness.

### `tests/stub.lua` (the `libs` table inside `Stub.install()`, line ~351)

```lua
local libs = {
    ["HereBeDragons-Pins-2.0"] = { ... },
    ["LibDataBroker-1.1"] = { NewDataObject = function(_, _, obj) return obj end },
    ["LibDBIcon-1.0"] = { ... },
}
_G.LibStub = setmetatable({
    GetLibrary = function(_, name) return libs[name] end,
    NewLibrary = function() return nil end,
}, { __call = function(_, name) return libs[name] end })
```
There is no `GetLocale` global and no `AceLocale-3.0` entry.

### `tests/test_toc.py`

- `test_every_referenced_file_exists` — every non-comment `.toc` line must point
  to a file on disk, **except lines starting with `Libs/`** (skipped).
- `test_no_orphan_lua_or_xml_source_files` — every top-level `.lua`/`.xml` in the
  addon folder must be `.toc`-referenced. **Scans `os.listdir(ADDON)` only — not
  subdirectories**, so files under `Locales/` are not checked for orphan status
  (but each one listed in the `.toc` must still exist).
- `test_core_load_order_puts_data_before_the_model` — checks `Core.lua` etc.
  ordering only; nothing about `Locales/`.

### `.github/workflows/ci.yml` — the `data:` job

```yaml
      - name: Check MountData.lua / Overrides.lua structure
        run: python -m unittest discover -s tests -p "test_mountdata.py" -v
      - name: Check obtainability engine
        run: python -m unittest discover -s tests -p "test_obtainability.py" -v
      - name: Check TOC / packaging consistency
        run: python -m unittest discover -s tests -p "test_toc.py" -v
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Smoke tests | `python tests/run.py` | `All smoke scenarios passed.` |
| Python suite | `python -m unittest discover -s tests -p "test_*.py"` | ends with `OK` |
| Lint (Lua) | `luacheck .` | `0 warnings / 0 errors` (skip if not installed) |
| Everything | `pwsh -File run-tests.ps1` | `All suites passed.` |

## Scope

**In scope** (create / modify):

- `Mount_Tracker_Local_Zones/Libs/AceLocale-3.0/AceLocale-3.0.lua` — NEW (vendored)
- `Mount_Tracker_Local_Zones/Locales/enUS.lua` — NEW
- `Mount_Tracker_Local_Zones/Locales/{deDE,esES,esMX,frFR,itIT,koKR,ptBR,ruRU,zhCN,zhTW}.lua` — NEW (10 stubs)
- `Mount_Tracker_Local_Zones/Mount_Tracker_Local_Zones.toc` — add lib line, 11 `Locales\` lines, `## Notes`
- `.gitignore` — one keep-exception + comment tweak
- `Mount_Tracker_Local_Zones/Core.lua` — set `addon.L` (one/two lines near the top)
- `tests/stub.lua` — fake `AceLocale-3.0` + `_G.GetLocale`
- `.luacheckrc` — add `"GetLocale"` to `read_globals`
- `tests/test_locales.py` — NEW
- `tests/smoke.lua` — add `L` checks
- `tests/README.md` — one row + paragraph
- `.github/workflows/ci.yml` — one step in the `data:` job

**Out of scope** (do NOT touch): any of the ~90 hardcoded strings at their call
sites (that is plan 009), `.pkgmeta`, `README.md`, `CURSEFORGE.md`,
`MountData.lua`, `Overrides.lua`, `tools/`.

## Git workflow

- Branch: `feat/008-localization-scaffolding` off `main`.
- 2 commits is fine: (a) vendored lib + `.gitignore`, (b) everything else.
  Message style — short imperative, matching `git log`:
  `i18n: add AceLocale-3.0 and Locales/ scaffolding`.
- Do NOT push or open a PR unless the maintainer asked.
- Do NOT add a `Claude-Session:` / session-URL trailer to commits or the PR body
  (repo rule).

## Steps

### Step 1: Vendor AceLocale-3.0

Copy `AceLocale-3.0.lua` into
`Mount_Tracker_Local_Zones/Libs/AceLocale-3.0/AceLocale-3.0.lua`. Bare `.lua`
only — match the `LibStub/LibStub.lua` layout, no per-lib `.toc`/`.xml`.

Source (all identical — the same frozen file):
- `D:\Propio\GitHub\World of Warcraft add-ons\Mechanic\Mechanic\Libs\AceLocale-3.0\AceLocale-3.0.lua`
- or an installed Ace3 addon under `_retail_\Interface\AddOns\*\Libs\AceLocale-3.0\`
- or the Ace3 distribution (`https://www.wowace.com/projects/ace3`).

Key facts about the lib (verify the copy matches):
- `local MAJOR, MINOR = "AceLocale-3.0", 6`
- `:NewLocale(app, locale, isDefault, silent)` — for a non-default locale returns
  a write-proxy only when `GetLocale()` matches (else `nil`); `= true` values are
  replaced with the key string.
- `:GetLocale(app)` returns the app table; with a **silent** default locale,
  missing keys resolve to the key itself (no error). enGB is mapped to enUS
  inside the lib.

### Step 2: `.gitignore` keep-exception

Replace the embedded-libraries block with:

```
# Embedded libraries.
# LibStub, CallbackHandler-1.0, LibDBIcon-1.0, AceLocale-3.0 are vendored (committed) --
# no maintained non-legacy git source, and all are tiny and effectively frozen.
# LibDataBroker-1.1 + HereBeDragons are fetched by the packager (.pkgmeta); kept on disk
# for local testing but not committed. libs.json is a Mechanic tool file, not shipped
# (see .pkgmeta ignore).
Mount_Tracker_Local_Zones/Libs/*
!Mount_Tracker_Local_Zones/Libs/LibStub/
!Mount_Tracker_Local_Zones/Libs/CallbackHandler-1.0/
!Mount_Tracker_Local_Zones/Libs/LibDBIcon-1.0/
!Mount_Tracker_Local_Zones/Libs/AceLocale-3.0/
```

**Verify**: `git check-ignore -v Mount_Tracker_Local_Zones/Libs/AceLocale-3.0/AceLocale-3.0.lua`
→ no output (not ignored). `git status --porcelain` shows the new lib file.

### Step 3: `.toc` — lib line, Locale lines, `## Notes`

1. Add after the `CallbackHandler-1.0` line (AceLocale needs only LibStub, so
   anywhere after `LibStub` works; keep it in the Libs block):
   ```
   Libs\AceLocale-3.0\AceLocale-3.0.lua
   ```
2. Add a `Locales` block on its own, between the last `Libs\` line and `Core.lua`
   (enUS first — it is the default locale and must register before `GetLocale`
   is called):
   ```
   Locales\enUS.lua
   Locales\deDE.lua
   Locales\esES.lua
   Locales\esMX.lua
   Locales\frFR.lua
   Locales\itIT.lua
   Locales\koKR.lua
   Locales\ptBR.lua
   Locales\ruRU.lua
   Locales\zhCN.lua
   Locales\zhTW.lua
   ```
3. Add a `## Notes` directive (currently absent) after `## Title`:
   ```
   ## Notes: Shows the mounts you can still collect in the zone you're standing in - and whether you can actually get them right now.
   ```
   One line, ASCII only (`-` not `—`).

### Step 4: `Locales/enUS.lua` — the source of truth

Create it verbatim as below. This is the authoritative phrase list; **plan 009
migrates the call sites to match these exact keys**. `= true` is the AceLocale
idiom for "the value is the key". Keep the section order stable so translation
diffs stay readable.

```lua
-- SOURCE OF TRUTH for every translatable string in the addon. Keys are the
-- English text; `= true` tells AceLocale to use the key as the value.
--
-- This file is pushed verbatim to CurseForge Localization by
-- tools/push_locale_phrases.py. Translations come back into the sibling
-- Locales/<code>.lua files via .github/workflows/refresh-locales.yml.
--
-- Adding a string: add the line here AND wrap the call site in L["..."].
-- Keep the section order below stable so translation diffs stay readable.

local addonName = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "enUS", true, true) -- isDefault, silent
if not L then return end

-- Shared / fallbacks
L["Mount Tracker"] = true
L["Mount Tracker: Local Zones"] = true
L["Mount %d"] = true
L["Unknown"] = true
L["Other"] = true
L["Global"] = true
L["collected"] = true

-- Chat / slash (Core.lua)
L["Window and section state reset."] = true
L["Options are not available yet."] = true
L["Debug output enabled."] = true
L["Debug output disabled."] = true
L["Commands: /mtlz [show | list | config | map | debug | reset]"] = true

-- Mount Journal / actions (MountActions.lua)
L["Can't open the Mount Journal during combat."] = true
L["Can't place a map pin for that mount here."] = true
L["Place map pin"] = true
L["Place map pin (vendor)"] = true
L["Set TomTom waypoint"] = true
L["Set TomTom waypoint (vendor)"] = true
L["Summon"] = true
L["Hide this mount"] = true

-- Tracker window (Window.lua)
L["Reload your UI (/reload) to apply the new window style."] = true
L["Mounts: %s"] = true
L["Mounts for %s:"] = true
L["Every mount here is already collected."] = true
L["%s \226\128\148 %d / %d collected"] = true
L["%d available"] = true
L["%d / %d account"] = true

-- Zone model status (MountModel.lua)
L["Loading mounts..."] = true
L["No collectable mounts tracked for this zone."] = true

-- Source-type group labels (MountModel.lua SOURCE_LABEL)
L["Dungeon & Raid"] = true
L["Rare Drop"] = true
L["Vendor"] = true
L["Quest"] = true
L["Zone Drop"] = true
L["World Event"] = true
L["Profession"] = true

-- Expansion group labels (MountModel.lua EXPANSION_LABEL). "Classic" doubles as
-- the window-style label below -- one entry covers both, intentionally.
L["Classic"] = true
L["The Burning Crusade"] = true
L["Wrath of the Lich King"] = true
L["Cataclysm"] = true
L["Mists of Pandaria"] = true
L["Warlords of Draenor"] = true
L["Legion"] = true
L["Battle for Azeroth"] = true
L["Shadowlands"] = true
L["Dragonflight"] = true
L["The War Within"] = true
L["Midnight"] = true

-- Obtainability detail text (Obtainability.lua)
L["Renown %d"] = true
L["%s / need %s"] = true
L["%s / %s reputation"] = true
L["available from a vendor"] = true
L["vendor"] = true
L["currency"] = true
L["%s |cffffffff(%s)|r"] = true
L["achievement reward"] = true
L["%s \194\183 done this reset"] = true

-- Obtainability tooltip headers (Obtainability.lua)
L["Available now"] = true
L["Farmable now"] = true
L["Reputation needed"] = true
L["Achievement needed"] = true
L["Quest needed"] = true
L["Locked this reset"] = true
L["Not yet collected"] = true
L["Dungeon drop"] = true
L["Raid drop"] = true
L["Rare drop"] = true

-- Options: sections
L["Window"] = true
L["Mount list"] = true
L["Filter by source"] = true
L["Map & minimap"] = true

-- Options: window style
L["Window style"] = true
L["Classic uses the Blizzard dialog frame and scrollbar. Stylized uses a flat dark panel with minimal controls. Reload your UI (/reload) after changing this."] = true
L["Stylized"] = true

-- Options: group-by
L["Group by"] = true
L["How the tracked mounts are grouped in the list."] = true
L["By source type"] = true
L["By expansion"] = true

-- Options: checkboxes + tooltips
L["Reopen on login"] = true
L["Reopen the tracker window when you log in if it was open when you logged out."] = true
L["Show collected mounts"] = true
L["Include mounts you already own. They appear greyed out in the list."] = true
L["Only show obtainable mounts"] = true
L["Hide mounts you can't get right now (reputation locked, weekly farm already done, achievement incomplete)."] = true
L["Show unusable mounts"] = true
L["Include mounts your class or faction can't use. They appear dimmed. Turn off to hide them."] = true
L["Show global mounts"] = true
L['Also list mounts with no home zone (class, racial, PvP, store, promotion), under a "Global" divider. Their sections start collapsed.'] = true
L["Show minimap button"] = true
L["A button on the minimap that toggles the tracker (right-click for options)."] = true
L["Show world map icons"] = true
L["An icon on the world map for each uncollected mount that has a known location."] = true
L["Show minimap icons"] = true
L["An icon on the minimap for each nearby uncollected mount that has a known location."] = true
L["Show vendor icons"] = true
L["Also mark the vendor on the map for mounts you can buy."] = true

-- Options: "Filter by source" rows
L["Show %s"] = true
L["Show %s mounts in the tracker list."] = true

-- Options: "Hidden mounts" sub-panel
L["Hidden mounts"] = true
L["Mounts you have hidden (right-click a mount -> Hide this mount). Hidden mounts stay out of the tracker list and off the map."] = true
L["Restore"] = true
L["Restore all"] = true
L["Restore section"] = true
L["No hidden mounts."] = true

-- Options: panel unavailable (Config.lua)
L["Options panel is unavailable."] = true

-- Minimap button tooltip (MinimapButton.lua)
L["Left-click to toggle the tracker"] = true
L["Right-click for options"] = true
```

> **On the spots where plan 009 restructures a string:** the debug toggle
> becomes two phrases (`Debug output enabled.` / `Debug output disabled.`); the
> minimap tooltip drops the partial `|cff...|r` colouring for two plain phrases;
> the `(currency)` price note becomes `L["%s |cffffffff(%s)|r"]:format(cost,
> L["currency"])`; the summary/header lines that embed colour codes are split so
> the translatable text (`%d available`, `%d / %d account`, the
> `%s \226\128\148 %d / %d collected` skeleton) is a phrase and the `|cff...|r`
> wrapper stays in code. Those keys are already in the list above — keep them
> even though plan 009 hasn't run yet.

### Step 5: the 10 stub locale files

Each `Locales/<code>.lua` (for `deDE esES esMX frFR itIT koKR ptBR ruRU zhCN
zhTW`) is identical except for the locale code:

```lua
-- GENERATED from CurseForge Localization by tools/pull_locale_translations.py.
-- Manual edits are overwritten. Untranslated keys fall back to Locales/enUS.lua.

local addonName = ...
local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "deDE")
if not L then return end
```

`NewLocale` returns `nil` unless the client's `GetLocale()` matches, so
`if not L then return end` is the entire guard. `L` is referenced in the `if`,
so an empty stub is luacheck-clean.

### Step 6: `Core.lua` — expose `addon.L`

Near the top of `Core.lua` (right after `local addonName, addon = ...` on line 1
is simplest):

```lua
local L = LibStub("AceLocale-3.0"):GetLocale(addonName)
addon.L = L
```

Do **not** yet use `L` anywhere in `Core.lua` — that is plan 009. (luacheck will
not warn about an unused `local L` because `addon.L = L` reads it.)

### Step 7: `tests/stub.lua` — fake AceLocale + `GetLocale`

The harness never loads the real lib. Inside `Stub.install()`:

1. A `GetLocale` global (near the other zone/faction globals, ~line 379):
   ```lua
   _G.GetLocale = function() return "enUS" end
   ```
2. An `AceLocale-3.0` entry in the `libs` table (~line 351) that mirrors the
   real semantics closely enough for the addon and `smoke.lua`:
   ```lua
   -- Faithful-enough AceLocale-3.0: `= true` resolves to the key; the stub
   -- client is always enUS, so non-default locales get no write proxy; missing
   -- keys fall back to the key string (silent default locale).
   ["AceLocale-3.0"] = {
       NewLocale = function(_, app, locale, isDefault)
           local t = aceLocaleApps[app]
           if not t then
               t = setmetatable({}, { __index = function(_, k) return k end })
               aceLocaleApps[app] = t
           end
           if locale ~= "enUS" and not isDefault then return nil end
           return setmetatable({}, {
               __newindex = function(_, k, v) rawset(t, k, v == true and k or v) end,
               __index = function(_, k) return t[k] end,
           })
       end,
       GetLocale = function(_, app)
           return aceLocaleApps[app]
               or setmetatable({}, { __index = function(_, k) return k end })
       end,
   },
   ```
   Put `local aceLocaleApps = {}` at file scope near the other stub state (or as
   an upvalue just above the `libs` table). `tests/` is excluded from lint anyway.

Result: `enUS.lua` populates the app table, the other 10 files hit
`NewLocale(... "deDE")` → `nil` → early return (covers their syntax + guard),
and `addon.L["anything"]` resolves.

### Step 8: `.luacheckrc`

Add `"GetLocale"` to the `read_globals` list (a Blizzard global the addon now
depends on indirectly). No other change is expected — `Libs/` is already
excluded so the vendored AceLocale is not linted, and the locale files only
assign to a `local L`.

Run `luacheck .` once. **Only if** it flags something in `Locales/*.lua`, add:
```lua
files["Mount_Tracker_Local_Zones/Locales/*.lua"] = { <the specific ignore> }
```
Do not add this pre-emptively.

### Step 9: `tests/test_locales.py` — NEW

Model it on `tests/test_mountdata.py` (the `_load_runtime()` / `LuaRuntime`
helper, `@unittest.skipIf(LuaRuntime is None, ...)`, bare Lua state, no WoW stub)
plus a ~15-line inline shim so the locale files execute:

```python
LUA_SHIM = r"""
local apps = {}
LibStub = setmetatable({}, { __call = function(_, name)
  if name ~= "AceLocale-3.0" then return nil end
  return {
    NewLocale = function(_, app, locale, isDefault)
      apps[app] = apps[app] or {}
      if locale ~= (GAME_LOCALE or "enUS") and not isDefault then return nil end
      local t = apps[app]
      return setmetatable({}, { __newindex = function(_, k, v)
        t[k] = (v == true) and k or v end })
    end,
    GetLocale = function(_, app) return apps[app] end,
  }
end })
function GetLocale() return GAME_LOCALE or "enUS" end
"""
```

Tests:

1. `Locales/*.lua` filenames == `{enUS, deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW}`.
2. The `.toc` references `Libs\AceLocale-3.0\AceLocale-3.0.lua` and every
   `Locales\*.lua` (reuse `test_toc.py`'s `toc_referenced_files`).
3. Load order in the `.toc`: the AceLocale lib line before the `Locales\` block;
   `Locales\enUS.lua` before every other `Locales\` line; every `Locales\` line
   before `Core.lua`.
4. enUS: load shim + `enUS.lua` with `GAME_LOCALE=nil`; every key is a non-empty
   `str`; every resolved value `== key` (the `= true` idiom).
5. No duplicate keys — raw-text scan (`re.findall(r'^L\[', ...)` style) per file;
   Lua would silently dedupe.
6. Each non-enUS file: set `GAME_LOCALE` to its code, load shim + `enUS.lua` +
   that file; assert every key it defines also exists in enUS.
7. Placeholder parity: for every translated entry, the multiset of
   `re.findall(r'%\d+\$s|%[-+ #0-9.]*[sdfxXq%]', value)` equals that of the enUS
   key. (All stubs are empty today, so this is a no-op until 010 fills them — but
   ship the test now.)
8. `loadfile` (via `lupa`) each locale file without error.
9. Each non-enUS file contains the literal `NewLocale(addonName, "<code>")`
   guard call (raw-text).

### Step 10: `tests/smoke.lua`

- Add `"L"` to the `addon.<key> is defined` loop (the list at ~line 45).
- Add two checks after the addon is loaded:
  ```lua
  check("addon.L falls back to the key",
      addon.L and addon.L["a phrase with no translation"] == "a phrase with no translation")
  check("addon.L resolves a known base phrase",
      addon.L["Hide this mount"] == "Hide this mount")
  ```

### Step 11: `.github/workflows/ci.yml`

In the `data:` job, after the `test_toc.py` step:

```yaml
      - name: Check locale-file shape
        run: python -m unittest discover -s tests -p "test_locales.py" -v
```

### Step 12: `tests/README.md`

Add a row to the suite table:

```
| Locales | `python -m unittest discover -s tests -p test_locales.py` | `Locales/*.lua` filename set, `.toc` wiring + load order, `enUS.lua` key/value shape, no duplicate keys, translations only add known keys, `%s`/`%d` placeholder parity |
```

and one line under "The headless smoke suite" noting that locale files load
through the harness like any addon file, `tests/stub.lua` fakes `AceLocale-3.0`
and returns `GetLocale() == "enUS"`.

## Test plan

- `python tests/run.py` → `All smoke scenarios passed.` (now also exercises the
  new `addon.L` checks and loads all 11 locale files)
- `python -m unittest discover -s tests -p "test_*.py"` → `OK`, test count up by
  the `test_locales.py` cases
- `luacheck .` → `0 warnings / 0 errors`
- `pwsh -File run-tests.ps1` → `All suites passed.`

## Done criteria

ALL must hold:

- [ ] `Mount_Tracker_Local_Zones/Libs/AceLocale-3.0/AceLocale-3.0.lua` exists and
      is **not** git-ignored
- [ ] `Locales/enUS.lua` + 10 stubs exist and are `.toc`-referenced
- [ ] `.toc` has the AceLocale lib line, the 11 `Locales\` lines before
      `Core.lua`, and a `## Notes` directive
- [ ] `Core.lua` sets `addon.L`; no call site changed
- [ ] `luacheck .` → 0/0
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK`
- [ ] `python tests/run.py` → `All smoke scenarios passed.`
- [ ] `git grep -n '"Hide this mount"' -- Mount_Tracker_Local_Zones/` still shows
      the **hardcoded** call site in `MountActions.lua` (proof 009 wasn't started
      here) plus the new `enUS.lua` entry
- [ ] `plans/README.md` status row for 008 updated

## STOP conditions

Stop and report if:

- The `.toc`, `.gitignore`, `.luacheckrc`, or `tests/` files differ materially
  from the "Current state" excerpts (drift).
- `luacheck` flags the vendored `AceLocale-3.0.lua` (means `exclude_files` isn't
  catching `Libs/` — do not "fix" the lib).
- A smoke scenario throws while loading a locale file.
- Making `test_locales.py` pass would require changing `enUS.lua`'s phrase list
  (that list is the 009 contract — a mismatch means the plan needs review).

## Maintenance notes

- `enGB` is intentionally absent: AceLocale maps it to `enUS` internally.
- If a future phrase needs plural forms or gender, AceLocale has no native
  support — handle it with distinct keys (as plan 009 does for the debug toggle).
- The stub's fake AceLocale is deliberately minimal. If the addon starts using
  `GetLocale(app, silent)` or namespaces, extend the fake to match.
