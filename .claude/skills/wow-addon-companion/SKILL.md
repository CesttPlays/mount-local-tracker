---
name: wow-addon-companion
description: Repo-specific overlay for mount-local-tracker — this addon's data model, C_MountJournal API surface, obtainability logic, and datamine pipeline. Use when coding, debugging, or reviewing this addon. Read the shared wow-addon-family skill first for the common conventions.
---

# WoW Addon Companion — mount-local-tracker

**Mount Tracker: Local Zones** — a zone-aware, obtainability-aware window listing the mounts
you can still collect where you're standing: whether you can get one now (vendor /
affordable), are short on reputation, or the weekly farm is up.

This skill is the **overlay**. The shared baseline — architecture, `SafeApiCall` pattern,
change discipline, smoke tests, `context/` continuity, git guardrails, the family
display-name rule — is in the **`wow-addon-family`** skill; read it first. Full current
state is in `context/context-cache.md`. Second addon in the family; when in doubt, look at
how `achivement-local-tracker` solved the same thing.

Folder `Mount_Tracker_Local_Zones/` (spelled correctly), SavedVariables
`MountTrackerLocalZonesDB`, slash `/mtlz`, TOC `## Interface: 120100` (retail Midnight 12.1).

## C_MountJournal API surface
- `C_MountJournal.GetMountIDs()`, `GetMountInfoByID(id)` →
  `name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific,
  faction, shouldHideOnChar, isCollected, mountID, isSteadyFlight` — **tuple order is
  load-bearing**, still unverified in-game (see `context/wow-api-reference-cache.md`).
- `GetMountInfoExtraByID(id)` → `creatureDisplayInfoID, description, source, isSelfMount,
  mountTypeID, ...`.
- The journal loads early — still guard it (`IsMountApiReady` + retry in `Core.lua`), but no
  heavy readiness-retry loop is needed (unlike the achievement API in the sibling repo).
- Obtainability reads live: `C_Reputation`, `C_MajorFactions`, `C_CurrencyInfo`, `GetMoney`,
  `GetAchievementInfo`, `C_QuestLog.IsQuestFlaggedCompleted`.
- Tooltip: `GameTooltip:SetMountBySpellID`. Events: `NEW_MOUNT_ADDED`,
  `MOUNT_JOURNAL_USABILITY_CHANGED`.

## Data model
- **MountData.lua** — GENERATED. `{ build, updated, zones=[uiMapID]->{mountID},
  source=[mountID]->str, subcat, expansion, faction=[mountID]->0|1, points={},
  achievementID={}, repFaction={}, vendor={}, global={mountID,...} }`. `points` /
  `achievementID` / `repFaction` / `vendor` are emitted **empty** — curated in Overrides.
- **Overrides.lua** — `addon.MountOverrides = { add, remove, source, subcat, points, faction,
  expansion, dropChance, lockout, lockoutQuest, vendor, repFaction, note }`. Seeded with
  ~30 well-known mounts.
- **Obtainability.lua** — pure `Evaluate(mountID, row) -> { state, detail, sortRank }`;
  states: `collected | available | farmable | drop | quest_gated | rep_gated |
  achievement_gated | reset_locked`.
- **MountModel.lua** — `CandidateSet` / `GlobalCandidateSet` / `BuildRow` (6 filters) /
  `GroupRows(ids, groupBy)` (`db.groupBy` = `"source"` default | `"expansion"`) /
  `GetZoneMounts` (7-part cache key) / `Summary`.
- Vendor waypoints: `vendor` entries carry `{ npc, uiMapID, x, y }` (0–10000 point scale);
  `db.showVendorIcons` (default **true**) pins vendor-purchase mounts at the merchant.

## Datamine pipeline
`tools/generate_mount_zones.py` (stdlib only). **`Mount.SourceTypeEnum` is too noisy** (big
"Legacy" bucket, `-1` on new mounts) — parse **`Mount.SourceText_lang`** structured labels
instead (`Zone:` / `Location:` / `Vendor:` / `Drop:` / `Quest:` / `Faction:` /
`Profession:` / `World Event:` / `(Alliance)` / `(Horde)`). Resolution: instance drops via
`JournalEncounterItem` → item teach-spell → `Mount.SourceSpellID` → `JournalInstance.MapID`
→ uiMapID (link verified on 12.1.0.69497); `Zone:`/`Location:` name match against
`UiMap.Name_lang` (Type ∈ {3 Zone, 6 Orphan}); expansion from `ItemSparse.ExpansionID`;
faction from the `(Alliance)`/`(Horde)` tag; everything else → `global`. Sanity gate: ≥40
zones, ≥250 refs, ≥150 global, within 60–160% of the previous file. See the
`refresh-gamedata` skill for the run + offline fallback.

## In-game checks
`/mtlz` (toggle), `/mtlz list`, `/mtlz config`, `/mtlz map`, `/mtlz debug`, `/mtlz reset`.
Everything is still unvalidated in the live client — see `context/phase8-ingame-checklist.md`.
