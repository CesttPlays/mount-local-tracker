# WoW API Reference Cache

Source of truth for this repo's addon work. Target build: TOC `## Interface: 120100`.

Two tiers:
- **Carried over** — validated in-game in the sibling repo `achivement-local-tracker` and
  reused here unchanged. Trust but re-check on first use in this addon.
- **Pending** — the mount-specific calls this addon needs. NOT yet validated in-game.
  Move an entry up to a dated "validated" note once its code path runs clean in the live client.

---

## PENDING — Mounts (C_MountJournal)

Not yet validated in this addon. Signatures from warcraft.wiki.gg, current as of the
War Within / Midnight API.

### C_MountJournal.GetMountIDs() -> number[]
- All mount IDs known to the client (collected or not). The id IS the DB2 `Mount.ID` on
  modern clients — the datamined `MountData.lua` keys on the same number.
- `C_MountJournal.GetNumMounts()` / display-index helpers exist but are filter-dependent;
  prefer `GetMountIDs()` for a stable full set.

### C_MountJournal.GetMountInfoByID(mountID)
- Returns: `name(1), spellID(2), icon(3), isActive(4), isUsable(5), sourceType(6),
  isFavorite(7), isFactionSpecific(8), faction(9), shouldHideOnChar(10), isCollected(11),
  mountID(12), isSteadyFlight(13)`.
- `isCollected` (11) is account-wide. `faction` (9): 0 = Horde, 1 = Alliance, only meaningful
  when `isFactionSpecific` (8) is true. `icon` (3) is a fileID → `Texture:SetTexture`.
- `sourceType` (6) is a 1-based index into the `MOUNT_SOURCE_TYPES` / source-filter enum
  (Drop, Quest, Vendor, Profession, World Event, Achievement, ...). Confirm the exact
  ordering in-game before relying on it for grouping — prefer the datamined `source` table.

### C_MountJournal.GetMountInfoExtraByID(mountID)
- Returns: `creatureDisplayInfoID(1), descriptionText(2), sourceText(3), isSelfMount(4),
  mountTypeID(5), uiModelSceneID(6), animID(7), spellVisualKitID(8),
  disablePlayerMountPreview(9)`.
- `sourceText` (3) is the localized freeform "Drop: X / Zone: Y" string — same content as
  DB2 `Mount.SourceText_lang`. Display only; do not parse at runtime.

### GameTooltip:SetMountBySpellID(spellID)
- Populates the tooltip with a mount (pass `spellID` from `GetMountInfoByID`, not `mountID`).
  Fallback: `GameTooltip:SetSpellByID(spellID)`.

### Opening the Mount Journal to a mount
- `ToggleCollectionsJournal(1)` opens Collections on the Mounts tab (LoD-loads
  `Blizzard_Collections`). Then `MountJournal_SelectByMountID(mountID)` selects it.
- Guard both (`type(fn) == "function"`); gate the toggle on `not InCombatLockdown()` if it
  turns out to taint.

### C_MountJournal.SummonByID(mountID)
- Summons a collected mount (0 = random favorite). For the right-click "Summon" action;
  only offer when `isCollected`.

### Events
- `NEW_MOUNT_ADDED` (arg1 = mountID) — a mount was just collected. Trigger a state-only
  refresh (like `ACHIEVEMENT_EARNED` in the sibling).
- `MOUNT_JOURNAL_USABILITY_CHANGED` — usability flags changed (riding skill, zone). Cheap
  refresh.
- `COMPANION_LEARNED` / `COMPANION_UNLEARNED` — older, broader; `NEW_MOUNT_ADDED` is preferred.

---

## CARRIED OVER — Map / zone (validated in the sibling repo)

### C_Map.GetBestMapForUnit("player") -> uiMapID
- The player's current uiMapID. `C_Map.GetMapInfo(uiMapID)` -> `{ name, parentMapID, mapType, ... }`;
  walk `parentMapID` for the zone→continent chain. Locale-independent key for zone data.

### C_Map.SetUserWaypoint / CanSetUserWaypointOnMap / C_SuperTrack — native map pin
- `C_Map.CanSetUserWaypointOnMap(uiMapID)` → bool (false on some instance maps).
- `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapID, x, y))` places the single
  native user waypoint (x/y are 0-1); a new one replaces the old.
- `C_SuperTrack.SetSuperTrackedUserWaypoint(true)` makes the on-screen arrow track it.

### TomTom:AddWaypoint(uiMapID, x, y, opts) — optional dependency
- `opts = { title=, from=, crazy=true }`. Gate on `C_AddOns.IsAddOnLoaded("TomTom")`.
  `## OptionalDeps: TomTom` in the TOC for load order.

## CARRIED OVER — UI templates / frame behaviour

- `BasicFrameTemplateWithInset` on 12.1 has **no `.Inset`** child — anchor content with
  explicit margins (title bar ~30px top, scrollbar ~28px right, grip clearance bottom-right).
  Title is `frame.TitleText` or `frame.TitleContainer.TitleText` depending on version.
- Movable: `SetMovable(true)` + `RegisterForDrag("LeftButton")` + `OnDragStart=StartMoving` /
  `OnDragStop=StopMovingOrSizing`. Resizable: `SetResizable(true)` + `SetResizeBounds(minW, minH)`
  (NOT `SetMinResize` — removed 10.0) + a grip button calling `StartSizing("BOTTOMRIGHT")`.
  Create the grip AFTER the scroll frame (or raise its frame level) or it's unclickable.
- Persist geometry manually via `GetPoint`/`GetSize` -> SavedVariables (anchor restore to
  UIParent to dodge a missing relativeTo). `SetUserPlaced` does not save size.
- Blizzard **ScrollBox** list: `WowScrollBoxList` + a scrollbar, wired via
  `ScrollUtil.InitScrollBoxListWithScrollBar`; flat `DataProvider` of pooled elements.

## CARRIED OVER — Settings API (options panel)

- `category = Settings.RegisterVerticalLayoutCategory(name)`
- `setting = Settings.RegisterAddOnSetting(category, variable, variableKey, variableTbl, type, name, default)`
  — 11.0.2 signature; `variableKey`+`variableTbl` (3rd/4th) bind directly to a saved-vars slot.
- `Settings.CreateCheckbox(category, setting, tooltip)` (lowercase b); `setting:SetValueChangedCallback(fn)`;
  `Settings.RegisterAddOnCategory(category)`; `Settings.OpenToCategory(category:GetID())`.
- Dropdown: `Settings.CreateDropdown(category, setting, optionsFn, tooltip)` where `optionsFn`
  returns a `Settings.CreateControlTextContainer` — the sibling's `AddDropdown` helper wraps
  this with guards. Used here for the `groupBy` setting.
- `Settings.RegisterCanvasLayoutSubcategory(parentCategory, frame, name)` — nests a custom
  frame as a sub-page. Rebuild dynamic content on `frame:OnShow`. (The "Hidden mounts" panel.)
- Register on `PLAYER_LOGIN` (after saved vars exist). The old `InterfaceOptions_*` is deprecated.

## CARRIED OVER — Row / map-pin interactions

- `MenuUtil.CreateContextMenu(ownerRegion, function(owner, rootDescription) ... end)` — modern
  context menu. `rootDescription:CreateTitle(text)`, `:CreateButton(text, onClick)`.
- `RegisterForClicks("LeftButtonUp","RightButtonUp")` on a plain (non-secure) button to get
  right-clicks into `OnClick` (which then receives `button`). Taint-free for UI buttons.
- `IsModifiedClick("CHATLINK")` gates shift-click-to-link; feed the link to
  `ChatEdit_InsertLink` (false if no active edit box → fall back to `ChatFrame_OpenChat`).

## Notes
- There is NO API mapping mounts to zones. The mapping comes from the datamined
  `MountData.lua` (see `tools/generate_mount_zones.py`) plus hand-curated `Overrides.lua`.
