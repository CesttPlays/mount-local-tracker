# Plan 009: Route the ~90 user-facing strings through `addon.L`

> **Executor instructions**: Follow this plan file by file. After each file, run
> the smoke suite. Honour "STOP conditions". When done, update the status row in
> `plans/README.md` and hand the maintainer the in-game checklist at the bottom
> — this plan is **not done** until that checklist has been run on a live
> client.
>
> **Drift check (run first)**:
> `git diff --stat 8188db1..HEAD -- Mount_Tracker_Local_Zones/`
> The line numbers below were captured at `8188db1`. If plan 008 or anything
> else shifted them, match on the **string content**, not the line number.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM — touches every user-facing string; a dropped string or a
  broken `:format` won't fail the offline suite. The in-game checklist is the
  real gate.
- **Depends on**: 008 (needs `addon.L` and `Locales/enUS.lua`)
- **Category**: i18n
- **Planned at**: commit `8188db1`, 2026-09-01

## Why this matters

Plan 008 added the translation table but nothing reads from it. This plan moves
every hardcoded English UI string onto `L["..."]`, keyed by the exact English
text already listed in `Locales/enUS.lua`. On an enUS client the output is
byte-identical; on any other client, translated strings now render and
untranslated ones fall back to English. This is the change that actually makes
the addon localizable.

## Ground rules

- The key is **the English source string**, and it must match `Locales/enUS.lua`
  exactly (plan 008). If a string here isn't in `enUS.lua`, that's a STOP.
- `"Foo"` → `L["Foo"]`.
- `("...%d..."):format(n)` → `L["...%d..."]:format(n)` — the format string is the
  key; keep every `%s` / `%d` / `%.1f` intact and in order.
- **Never concatenate translated fragments.** A sentence built from
  `"a " .. x .. " b"` becomes one phrase `L["a %s b"]:format(x)`, or two
  independent whole-sentence phrases.
- Each consumer file gets `local L = addon.L` immediately under its
  `local _, addon = ...` header (or `local addonName, addon = ...` where that is
  the header). `Core.lua` already set `addon.L` in plan 008 — add a file-local
  `local L = addon.L` there too, **after** the `addon.L =` line.
- **`Map.lua` has only `DebugPrint` strings — do not touch it.**
- `MountData.lua` / `Overrides.lua` are data files — do not touch.

### Never localize (leave exactly as-is)

Slash keywords `reset/list/config/debug/map/show/toggle`; STATE tokens
(`available/farmable/drop/quest_gated/rep_gated/achievement_gated/reset_locked/collected`
— the `Obtainability.STATE` keys, `row.state` values and the `entry.state ==`
comparisons); `windowStyle` values `"stylized"/"classic"`; `groupBy` values
`"source"/"expansion"`; source-type keys
`"instance"/"drop"/"vendor"/"quest"/"zonedrop"/"worldevent"/"profession"/"other"`;
the `"MTLZ_"` setting-ID prefix; the `"s:"` / `"e:"` / `"g:"` / `"show_"` key
prefixes; `"Alliance"/"Horde"` (API constants); the `Print` colour +
`addonName` prefix (`"|cff00ccff" .. addonName .. "|r: "`); every `DebugPrint` /
`Map:` debug string; texture paths; wordless format skeletons
(`"%s (%d/%d)"`, `"  %s - %s"`, `"%s  |cff9d9d9d%d/%d|r"`,
`"%s  |cff9d9d9d%d|r"`, `"%s \194\183 %s"`, `" \194\183 "`).

### Curated data strings — out of scope (same as plan 008)

`Obtainability.lua` shows the `lockout` cadence word (`"weekly"` / `"daily"`),
the `dropChance` text and free-text `note` values **verbatim from
`Overrides.lua`**. These are curated *data*, not code literals — localizing them
is out of scope for this batch (same rationale as `MountData.lua`). So:

- `Obtainability.lua` line ~203 `local detail = lockout` — **leave**.
- `Obtainability.lua` line ~205 `("%s \194\183 %s"):format(lockout, dropChance)`
  — **leave** (wordless skeleton; both args are curated data).
- `Obtainability.lua` line ~217 `local detail = dropChance or note` — **leave**.
- `Obtainability.lua` line ~256-258 the trailing `note` line — **leave**.

Only the *code-authored* wrapper text around them is localized (see the file
table below).

### Judgement calls (decide before running `test_locales.py`)

Two spots restructure a colour-embedded string. The `enUS.lua` keys in plan 008
already assume the restructure — if the maintainer wants it done differently,
change plan 008's `enUS.lua` and this table together.

1. **`Window.lua` `SummaryText` / `ListView.lua` `InitHeader`** — both build a
   line like `"<zone> — 3 / 10 collected |cff66cc66· 2 available|r
   |cff9d9d9d· 1 / 5 account|r"`. The `|cff…|r` wrappers and the `·` middot stay
   in code; the translatable pieces become phrases:
   `L["%s \226\128\148 %d / %d collected"]`, `L["%d available"]`,
   `L["%d / %d account"]`.
2. **`Obtainability.lua` `VendorDetail`** — `("%s |cffffffff(currency)|r")`
   becomes `L["%s |cffffffff(%s)|r"]:format(cost, L["currency"])`.
3. **`MinimapButton.lua` lines 25-26** — the original bolds only the
   "Left-click" / "Right-click" word via `|cffeeeeee…|r`. These become plain
   whole phrases (`L["Left-click to toggle the tracker"]` /
   `L["Right-click for options"]`) and lose the partial highlight — same
   decision the sibling addon made.

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Smoke | `python tests/run.py` | `All smoke scenarios passed.` |
| Python suite | `python -m unittest discover -s tests -p "test_*.py"` | `OK` |
| Lint | `luacheck .` | `0 warnings / 0 errors` |
| Placeholder audit | `python -m unittest discover -s tests -p "test_locales.py" -v` | `OK` |

## Git workflow

- Branch: `feat/009-localization-string-migration` off the 008 branch (or `main`
  once 008 is merged).
- One commit for the lot is fine:
  `i18n: route user-facing strings through addon.L`.
- Do NOT push before the maintainer has run the in-game checklist.
- No session-URL trailer (repo rule).

## Steps

### File: `Mount_Tracker_Local_Zones/Core.lua`

Add `local L = addon.L` just after the `addon.L = L` line from plan 008.

| Line | Current | After |
|---|---|---|
| 214 | `or "Unknown"` (end of the `state.lastZone = ...` chain in `UpdateCurrentLocation`) | `or L["Unknown"]` |
| 221 | `return state.lastZone or "Unknown"` (`GetCurrentLocationName`) | `return state.lastZone or L["Unknown"]` |
| 324 | `Print("Window and section state reset.")` | `Print(L["Window and section state reset."])` |
| 333 | `Print("Options are not available yet.")` | `Print(L["Options are not available yet."])` |
| 337 | `Print("Debug output " .. (addon.db.debug and "enabled" or "disabled") .. ".")` | `Print(addon.db.debug and L["Debug output enabled."] or L["Debug output disabled."])` |
| 347 | `Print("Commands: /mtlz [show | list | config | map | debug | reset]")` | `Print(L["Commands: /mtlz [show | list | config | map | debug | reset]"])` |

Line 241 (`("Zone: %s (uiMapID %s)"):format(...)`) is inside a `DebugPrint`
guard — **leave it**.

### File: `Mount_Tracker_Local_Zones/MountActions.lua`

Header is `local _, addon = ...`. Add `local L = addon.L`.

| Line | Current | After |
|---|---|---|
| 35 | `return "Mount " .. tostring(mountID)` (`MountName` fallback) | `return L["Mount %d"]:format(mountID)` |
| 41 | `Print("Can't open the Mount Journal during combat.")` | `Print(L["Can't open the Mount Journal during combat."])` |
| 100 | `Print("Can't place a map pin for that mount here.")` | `Print(L["Can't place a map pin for that mount here."])` |
| 113 | `from = "Mount Tracker",` (TomTom waypoint source) | `from = L["Mount Tracker"],` |
| 163 | `rootDescription:CreateButton("Place map pin", function()` | `rootDescription:CreateButton(L["Place map pin"], function()` |
| 167 | `rootDescription:CreateButton("Set TomTom waypoint", function()` | `rootDescription:CreateButton(L["Set TomTom waypoint"], function()` |
| 172 | `rootDescription:CreateButton("Place map pin (vendor)", function()` | `rootDescription:CreateButton(L["Place map pin (vendor)"], function()` |
| 176 | `rootDescription:CreateButton("Set TomTom waypoint (vendor)", function()` | `rootDescription:CreateButton(L["Set TomTom waypoint (vendor)"], function()` |
| 189 | `rootDescription:CreateButton("Summon", function()` | `rootDescription:CreateButton(L["Summon"], function()` |
| 193 | `rootDescription:CreateButton("Hide this mount", function()` | `rootDescription:CreateButton(L["Hide this mount"], function()` |

Line 178 (`("%s \194\183 %s"):format(MountName(mountID), vendorNPC)`) is a
wordless skeleton — **leave**. Line 215 passes the live mount name — **leave**.

### File: `Mount_Tracker_Local_Zones/Window.lua`

Header is `local _, addon = ...`. Add `local L = addon.L`.

| Line | Current | After |
|---|---|---|
| 264 | `SetWindowTitle(trackerWindow, "Mount Tracker")` | `SetWindowTitle(trackerWindow, L["Mount Tracker"])` |
| 316 | `addon.Print("Reload your UI (/reload) to apply the new window style.")` | `addon.Print(L["Reload your UI (/reload) to apply the new window style."])` |
| 326-331 | `string.format("%s \226\128\148 %d / %d collected", zoneName or "Unknown", summary.zoneCollected, summary.zoneTotal)` | `L["%s \226\128\148 %d / %d collected"]:format(zoneName or L["Unknown"], summary.zoneCollected, summary.zoneTotal)` |
| 333 | `text = text .. string.format(" \|cff66cc66\194\183 %d available\|r", summary.zoneAvailable)` | `text = text .. " " .. ("\|cff66cc66\194\183 %s\|r"):format(L["%d available"]:format(summary.zoneAvailable))` |
| 336-340 | `text = text .. string.format(" \|cff9d9d9d\194\183 %d / %d account\|r", summary.accountCollected or 0, summary.accountTotal)` | `text = text .. " " .. ("\|cff9d9d9d\194\183 %s\|r"):format(L["%d / %d account"]:format(summary.accountCollected or 0, summary.accountTotal))` |
| 351 | `SetWindowTitle(trackerWindow, "Mounts: " .. (zoneName or "Unknown"))` | `SetWindowTitle(trackerWindow, L["Mounts: %s"]:format(zoneName or L["Unknown"]))` |
| 357 | `message = "Every mount here is already collected."` | `message = L["Every mount here is already collected."]` |
| 406 | `addon.Print("Mounts for " .. (zoneName or "Unknown") .. ":")` | `addon.Print(L["Mounts for %s:"]:format(zoneName or L["Unknown"]))` |
| 418 | `addon.Print("-- Global --")` | `addon.Print(("-- %s --"):format(L["Global"]))` |

Lines 420 / 422 (`"%s (%d/%d)"`, `"  %s - %s"`) are wordless skeletons —
**leave** (`group.label` is already localized via `SourceLabel`, and
`entry.detail` / `entry.name` are values).

> The rewrites on 333 / 336-340 keep the exact `|cff…|r · …|r` visual by
> wrapping the localized inner phrase in a code-owned colour skeleton. If a
> reviewer prefers the whole `|cff…|r` fragment to be one translatable key,
> that is the alternative — but then update `enUS.lua` to match and drop the
> `%d available` / `%d / %d account` keys.

### File: `Mount_Tracker_Local_Zones/MountModel.lua`

Header is `local _, addon = ...`. Add `local L = addon.L`.

| Line | Current | After |
|---|---|---|
| 51-59 | `SOURCE_LABEL = { instance = "Dungeon & Raid", drop = "Rare Drop", vendor = "Vendor", quest = "Quest", zonedrop = "Zone Drop", worldevent = "World Event", profession = "Profession", other = "Other" }` | wrap every value: `instance = L["Dungeon & Raid"]`, … `other = L["Other"]`. **Keys stay** (`instance`, `drop`, …). |
| 67 | `return SOURCE_LABEL[s] or "Other"` (`SourceLabel`) | `return SOURCE_LABEL[s] or L["Other"]` |
| 74 | `return "s:" .. s, SOURCE_LABEL[s] or "Other", ...` (`SourceBucket`) | `return "s:" .. s, SOURCE_LABEL[s] or L["Other"], ...` — the `"s:"` prefix stays |
| 82-95 | `EXPANSION_LABEL = { [0] = "Classic", [1] = "The Burning Crusade", … [11] = "Midnight" }` | wrap every value in `L[...]` (see `enUS.lua` "Expansion group labels"). Numeric keys stay. |
| 105 | `return "e:x", "Other", 99` (`ExpansionBucket`) | `return "e:x", L["Other"], 99` |
| 108 | `return "e:" .. n, EXPANSION_LABEL[n] or "Other", -n` | `return "e:" .. n, EXPANSION_LABEL[n] or L["Other"], -n` |
| 421 | `return "Loading mounts..."` (`StatusFor`) | `return L["Loading mounts..."]` |
| 424 | `return "No collectable mounts tracked for this zone."` | `return L["No collectable mounts tracked for this zone."]` |

Line 216-221 (`PlayerFactionIndex`, `"Alliance"` / `"Horde"`) — API constants,
**leave**. Line 531-540 (`DebugPrint` format) — **leave**.

> `SOURCE_LABEL` / `EXPANSION_LABEL` are module-load tables. `addon.L` is set by
> `Core.lua`, which the `.toc` loads before `MountModel.lua`, so `L[...]` at
> module load is safe. `Config.lua` reads `addon.MountModel.SourceLabel(...)` at
> panel-build time (post-login) — also fine.

### File: `Mount_Tracker_Local_Zones/Obtainability.lua`

Header is `local _, addon = ...`. Add `local L = addon.L`.

| Line | Current | After |
|---|---|---|
| 55 | `("Renown %d"):format(level)` | `L["Renown %d"]:format(level)` |
| 113 | `price = ("%s \|cffffffff(currency)\|r"):format(cost)` | `price = L["%s \|cffffffff(%s)\|r"]:format(cost, L["currency"])` |
| 128 | `detail = affordable and "available from a vendor" or "vendor"` | `detail = affordable and L["available from a vendor"] or L["vendor"]` |
| 152 | `local detail = label and ("%s / need %s"):format(label, tostring(needed))` | `local detail = label and L["%s / need %s"]:format(label, tostring(needed))` |
| 153 | `or ("%s / %s reputation"):format(tostring(current or "?"), tostring(needed))` | `or L["%s / %s reputation"]:format(tostring(current or "?"), tostring(needed))` |
| 186 | `detail = type(achName) == "string" and achName ~= "" and achName or "achievement reward"` | `… or L["achievement reward"]` |
| 199 | `detail = ("%s \194\183 done this reset"):format(lockout)` | `detail = L["%s \194\183 done this reset"]:format(lockout)` |
| 244-251 | `labels = { available = "Available now", farmable = "Farmable now", rep_gated = "Reputation needed", achievement_gated = "Achievement needed", quest_gated = "Quest needed", reset_locked = "Locked this reset", drop = "Not yet collected" }` | wrap every value in `L[...]`. **Keys stay** (they are STATE tokens). |
| 252 | `tooltip:AddLine(labels[result.state] or "Not yet collected", r, g, b)` | `tooltip:AddLine(labels[result.state] or L["Not yet collected"], r, g, b)` |
| 265 | `local SUBCAT_LABEL = { dungeon = "Dungeon drop", raid = "Raid drop", rare = "Rare drop" }` | wrap every value in `L[...]`. Keys `dungeon`/`raid`/`rare` stay. |

Lines 203, 205, 217, 256-258 (`lockout` / `dropChance` / `note` passthrough) —
**leave** (curated data, see "out of scope" above). Line 99-104 `FormatGold`
`text .. "g"` — the bare `"g"` gold-unit suffix — **leave** for v1 (it is a
unit symbol next to a number, not a phrase; revisit only if a translator asks).

### File: `Mount_Tracker_Local_Zones/ListView.lua`

Header is `local _, addon = ...`. Add `local L = addon.L`.

| Line | Current | After |
|---|---|---|
| 32 | `local GLOBAL_SEPARATOR_LABEL = "Global"` | `local GLOBAL_SEPARATOR_LABEL = addon.L["Global"]` |
| 99-101 | `text = text .. string.format("  \|cff66cc66\194\183 %d available\|r", group.available)` | `text = text .. "  " .. ("\|cff66cc66\194\183 %s\|r"):format(L["%d available"]:format(group.available))` |
| 149 | `row.status:SetText(entry.detail or (entry.state == "collected" and "collected") or "")` | `row.status:SetText(entry.detail or (entry.state == "collected" and L["collected"]) or "")` — the `entry.state == "collected"` comparison stays a raw token |

Line 98 (`"%s  |cff9d9d9d%d/%d|r"`) is a wordless skeleton — **leave**.

### File: `Mount_Tracker_Local_Zones/MountModel.lua` — none beyond the table above.

### File: `Mount_Tracker_Local_Zones/Config.lua`

Header is `local _, addon = ...`. Add `local L = addon.L`. All of these run
after `PLAYER_LOGIN` (`SetupConfig` / panel `OnShow`), so `addon.L` is ready.

| Line | Current | After |
|---|---|---|
| 147 | `AddSection(layout, "Filter by source")` | `AddSection(layout, L["Filter by source"])` |
| 152 | `category, "MTLZ_" .. proxyKey, proxyKey, sourceFilterProxy, "boolean", "Show " .. label, true` | `… "Show %s" -> L["Show %s"]:format(label), true` — the `"MTLZ_"` prefix and `proxyKey` stay |
| 154 | `Settings.CreateCheckbox(category, setting, ("Show %s mounts in the tracker list."):format(label:lower()))` | `… (L["Show %s mounts in the tracker list."]:format(label:lower())))` |
| 186 | `header.restore:SetText("Restore section")` | `header.restore:SetText(L["Restore section"])` |
| 220 | `row.restore:SetText("Restore")` | `row.restore:SetText(L["Restore"])` |
| 265-268 | `intro:SetText("Mounts you have hidden (right-click a mount -> Hide this mount). " .. "Hidden mounts stay out of the tracker list and off the map.")` | one arg: `intro:SetText(L["Mounts you have hidden (right-click a mount -> Hide this mount). Hidden mounts stay out of the tracker list and off the map."])` |
| 273 | `restoreAll:SetText("Restore all")` | `restoreAll:SetText(L["Restore all"])` |
| 277 | `empty:SetText("No hidden mounts.")` | `empty:SetText(L["No hidden mounts."])` |
| 321 | `name = (type(name) == "string" and name ~= "" and name) or ("Mount " .. id),` | `… or L["Mount %d"]:format(id),` |
| 357 | `Settings.RegisterCanvasLayoutSubcategory(parentCategory, panel, "Hidden mounts")` | `… panel, L["Hidden mounts"])` |
| 372 | `Settings.RegisterVerticalLayoutCategory("Mount Tracker: Local Zones")` | `Settings.RegisterVerticalLayoutCategory(L["Mount Tracker: Local Zones"])` |
| 374 | `AddSection(layout, "Window")` | `AddSection(layout, L["Window"])` |
| 377 | `"Window style",` | `L["Window style"],` |
| 379-380 | `"Classic uses the Blizzard dialog frame and scrollbar. Stylized uses a flat dark panel " .. "with minimal controls. Reload your UI (/reload) after changing this.",` | one arg: `L["Classic uses the Blizzard dialog frame and scrollbar. Stylized uses a flat dark panel with minimal controls. Reload your UI (/reload) after changing this."],` |
| 381 | `{ { "stylized", "Stylized" }, { "classic", "Classic" } }` | `{ { "stylized", L["Stylized"] }, { "classic", L["Classic"] } }` — **values `"stylized"/"classic"` stay** |
| 386 | `"Reopen on login",` | `L["Reopen on login"],` |
| 387 | `"Reopen the tracker window when you log in if it was open when you logged out."` | `L["Reopen the tracker window when you log in if it was open when you logged out."]` |
| 390 | `AddSection(layout, "Mount list")` | `AddSection(layout, L["Mount list"])` |
| 393 | `"Group by",` | `L["Group by"],` |
| 395 | `"How the tracked mounts are grouped in the list.",` | `L["How the tracked mounts are grouped in the list."],` |
| 396 | `{ { "source", "By source type" }, { "expansion", "By expansion" } }` | `{ { "source", L["By source type"] }, { "expansion", L["By expansion"] } }` — values `"source"/"expansion"` stay |
| 401 | `"Show collected mounts",` | `L["Show collected mounts"],` |
| 402 | `"Include mounts you already own. They appear greyed out in the list."` | `L["Include mounts you already own. They appear greyed out in the list."]` |
| 407 | `"Only show obtainable mounts",` | `L["Only show obtainable mounts"],` |
| 408-409 | `"Hide mounts you can't get right now (reputation locked, weekly farm already done, " .. "achievement incomplete)."` | one arg: `L["Hide mounts you can't get right now (reputation locked, weekly farm already done, achievement incomplete)."]` |
| 414 | `"Show unusable mounts",` | `L["Show unusable mounts"],` |
| 415 | `"Include mounts your class or faction can't use. They appear dimmed. Turn off to hide them."` | `L["Include mounts your class or faction can't use. They appear dimmed. Turn off to hide them."]` |
| 420 | `"Show global mounts",` | `L["Show global mounts"],` |
| 421-422 | `"Also list mounts with no home zone (class, racial, PvP, store, promotion), under a " .. "\"Global\" divider. Their sections start collapsed."` | one arg: `L['Also list mounts with no home zone (class, racial, PvP, store, promotion), under a "Global" divider. Their sections start collapsed.']` |
| 427 | `AddSection(layout, "Map & minimap")` | `AddSection(layout, L["Map & minimap"])` |
| 431 | `"Show minimap button",` | `L["Show minimap button"],` |
| 432 | `"A button on the minimap that toggles the tracker (right-click for options)."` | `L["A button on the minimap that toggles the tracker (right-click for options)."]` |
| 437 | `"Show world map icons",` | `L["Show world map icons"],` |
| 438 | `"An icon on the world map for each uncollected mount that has a known location."` | `L["An icon on the world map for each uncollected mount that has a known location."]` |
| 443 | `"Show minimap icons",` | `L["Show minimap icons"],` |
| 444 | `"An icon on the minimap for each nearby uncollected mount that has a known location."` | `L["An icon on the minimap for each nearby uncollected mount that has a known location."]` |
| 449 | `"Show vendor icons",` | `L["Show vendor icons"],` |
| 450 | `"Also mark the vendor on the map for mounts you can buy."` | `L["Also mark the vendor on the map for mounts you can buy."]` |
| 463 | `addon.Print("Options panel is unavailable.")` | `addon.Print(L["Options panel is unavailable."])` |

> The `enUS.lua` key for line 421-422 uses `'...'` single-quote Lua string
> syntax so the embedded `"Global"` double-quotes need no escaping. Match that
> key **exactly** (including the `"Global"` word, which is *not* the same as the
> standalone `L["Global"]` divider key).
>
> Line 200 (`string.format("%s  |cff9d9d9d%d|r", elementData.name, #elementData.ids)`)
> — wordless skeleton, **leave** (`elementData.name` is the localized bucket
> label from `SourceBucketLabel` → `MountModel.SourceLabel`).

### File: `Mount_Tracker_Local_Zones/MinimapButton.lua`

Header is `local addonName, addon = ...`. Add `local L = addon.L`.

| Line | Current | After |
|---|---|---|
| 12 | `text = "Mount Tracker",` | `text = L["Mount Tracker"],` |
| 24 | `tooltip:AddLine("Mount Tracker: Local Zones")` | `tooltip:AddLine(L["Mount Tracker: Local Zones"])` |
| 25 | `tooltip:AddLine("\|cffeeeeeeLeft-click\|r  toggle the tracker", 1, 1, 1)` | `tooltip:AddLine(L["Left-click to toggle the tracker"], 1, 1, 1)` |
| 26 | `tooltip:AddLine("\|cffeeeeeeRight-click\|r  options", 1, 1, 1)` | `tooltip:AddLine(L["Right-click for options"], 1, 1, 1)` |

## Test plan

After each file: `python tests/run.py` → `All smoke scenarios passed.`
After all files:

- `luacheck .` → `0 warnings / 0 errors`
- `python -m unittest discover -s tests -p "test_*.py"` → `OK`
- `git diff` review: every removed string literal reappears as an `L[...]` key
  that exists verbatim in `Locales/enUS.lua`. Eyeball the diff against
  `enUS.lua` — any key with no match is a STOP.

## Done criteria (offline)

- [ ] No hardcoded user-facing English string remains in `Core.lua`,
      `MountActions.lua`, `Window.lua`, `MountModel.lua`, `Obtainability.lua`,
      `ListView.lua`, `Config.lua`, `MinimapButton.lua` (debug strings, curated
      data passthrough and the never-localize list excepted)
- [ ] `Map.lua` untouched
- [ ] Every `L[...]` key used has an exact match in `Locales/enUS.lua`
- [ ] `luacheck .` → 0/0
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK`
- [ ] `python tests/run.py` → `All smoke scenarios passed.`
- [ ] `plans/README.md` status row for 009 updated to IN PROGRESS (not DONE —
      see below)

## Done criteria (in-game — the maintainer runs this, then flips 009 to DONE)

Auto-copy `*.lua *.toc *.xml` **and the `Locales/` folder** into
`E:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\Mount_Tracker_Local_Zones\`
(the `deploy-addon` skill; make sure it copies subfolders).

1. **enUS client, `/reload`** — no Lua error; everything reads exactly as before.
2. Walk each surface:
   - `/mtlz` (bad subcommand → help line); `/mtlz debug` twice (`Debug output
     enabled.` then `disabled.`); `/mtlz reset`; `/mtlz config`; `/mtlz map`.
   - Tracker window: title `Mounts: <zone>`; the summary line
     (`<zone> — N / M collected · K available · A / B account`); the
     "Loading mounts…" message before the journal is ready; the
     "No collectable mounts tracked for this zone." message in an empty zone;
     "Every mount here is already collected." in a fully-collected zone.
   - Group headers: source labels (Dungeon & Raid / Rare Drop / Vendor / Quest /
     Zone Drop / World Event / Profession / Other) with the `N/M` count and the
     `· K available` suffix. Switch **Group by → By expansion** and check the
     expansion names render.
   - Row status text: an affordable vendor mount ("available now" family), a
     renown-gated one (`Renown N` / `<cur> / <need> reputation`), a weekly farm
     (`weekly` and `weekly · done this reset` after you've run it), a collected
     row showing "collected".
   - Hover a mount → the obtainability tooltip block: the state header
     ("Available now" / "Farmable now" / "Reputation needed" / "Achievement
     needed" / "Locked this reset" / "Not yet collected"), and for an
     instance mount with a subcat the dim "Raid drop" / "Dungeon drop" line.
   - Right-click a row / a map pin → "Place map pin", "Set TomTom waypoint"
     (needs TomTom), "Place map pin (vendor)" / "Set TomTom waypoint (vendor)"
     for a vendor mount with no spawn point, "Summon" (for a collected mount),
     "Hide this mount". In combat: `/mtlz` then click a collected row's Summon
     → "Can't open the Mount Journal during combat." (actually triggered by
     clicking the row to open the journal in combat).
   - Options panel: category title, the 4 section headers (Window / Mount list /
     Filter by source / Map & minimap), every checkbox label + hover tooltip,
     "Window style" + tooltip + "Stylized"/"Classic", "Group by" + tooltip +
     "By source type"/"By expansion", every "Show <Source>" filter row + its
     tooltip.
   - Options → Hidden mounts: sub-panel title, intro paragraph, "Restore all",
     a per-section "Restore section" (hide two mounts of the same source first),
     a per-row "Restore", and "No hidden mounts." after restoring all.
   - Enable "Show global mounts" → `/mtlz list` shows the `-- Global --` line and
     the window shows the "Global" divider.
   - Change "Window style" → the "Reload your UI (/reload)…" line prints.
3. **`/console locale deDE` + `/reload`** — with no German strings yet,
   everything must stay English (fallback). The test: **no Lua error, no `nil`
   or blank text, no empty buttons, no empty group headers.**
4. **Prove a translation renders:** temporarily add 2-3 lines to
   `Locales/deDE.lua` (e.g. `L["Hide this mount"] = "Test DE"`,
   `L["Vendor"] = "Händler"`), `/reload` on the deDE client, confirm those show
   translated and the rest stays English. Revert the edit.
5. `/console locale enUS` + `/reload` — back to normal.

## STOP conditions

- A string in this plan is missing from `Locales/enUS.lua` (008 contract broken).
- After migrating a file, a smoke scenario throws.
- A `:format` call has a placeholder count mismatch (`luacheck` won't catch this
  — check by eye; `test_locales.py` placeholder parity only covers translated
  entries, which are all empty until plan 010).
- `Map.lua` shows up in `git diff`.
- The maintainer's in-game pass finds a broken or missing string — fix, re-copy,
  re-check before flipping to DONE.

## Maintenance notes

- Once this lands and is validated, plan 010's docs sub-step is unblocked.
- The next time a new user-facing string is added anywhere, it must be added to
  `Locales/enUS.lua` in the same change or `test_locales.py` /
  `push_locale_phrases.py` will be out of sync with the code.
- `AddTooltipLines` re-evaluates obtainability on every hover — unrelated to
  i18n, fine to leave.
