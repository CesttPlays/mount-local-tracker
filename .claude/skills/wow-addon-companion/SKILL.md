---
name: wow-addon-companion
description: Conventions and working style for this World of Warcraft addon repo. Use when coding, debugging, reviewing, or refactoring the addon — Lua files, TOC/XML definitions, WoW API calls, event flow, saved variables, and addon lifecycle logic.
---

# WoW Addon Companion

Project-aware coding companion for this WoW addon: **Mount Tracker: Local Zones** — a
zone-aware window listing the mounts you can still collect where you're standing.
Sibling project to `achivement-local-tracker`, which the same author built first; that
repo is the reference implementation for architecture, tests, CI, and release flow.

## Source of truth
- Treat `.toc`, `.xml`, and `.lua` files as the primary implementation truth.
- Reason from the repo context first (`context/` files), then from WoW API knowledge.
- The addon's TOC `## Interface` line pins the game build being targeted — check it before assuming an API exists.

## WoW API safety
- Before using a WoW API function that isn't already in the code, verify it against
  https://warcraft.wiki.gg (or https://wowprogramming.com/docs/api.html) — API names and
  signatures change between game builds. Record confirmed calls in
  `context/wow-api-reference-cache.md` after in-game validation, and reuse that cache.
- Use the defensive pattern established in `Core.lua`: verify the function exists
  (`type(fn) == "function"`), call it via `pcall`, require the expected result type, and
  only then treat the API as ready (`SafeApiCall` / `SafeApiCallMulti`). Don't assume a
  single function name exists across all client builds; fall back where the code already does.
- Mount collection state comes from `C_MountJournal` — `GetMountIDs()`, `GetMountInfoByID(id)`
  (returns `name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific,
  faction, shouldHideOnChar, isCollected, mountID, isSteadyFlight`), `GetMountInfoExtraByID(id)`
  (`creatureDisplayInfoID, description, source, isSelfMount, mountTypeID, ...`). The journal
  loads early in the session but still guard it — no heavy readiness-retry loop is needed
  (unlike the achievement API in the sibling repo).
- Prefer zone-based checks (`C_Map.GetBestMapForUnit("player")` + parent chain) as the
  locale-independent zone key. `GetRealZoneText` / `GetZoneText` are for display only.

## Data pipeline
- There is **no** WoW API mapping mounts to zones. The mapping is datamined offline by
  `tools/generate_mount_zones.py` into `Mount_Tracker_Local_Zones/MountData.lua` (generated —
  do not hand-edit). Hand-tuning lives in `Overrides.lua`, merged at runtime.
- Generator resolution passes: instance drops (`JournalEncounterItem` → item → spell →
  `Mount.SourceSpellID`, `JournalInstance.MapID` → uiMap), achievement-reward mounts (reuse
  the achievement→zone logic), and `Mount.SourceText_lang` zone-name matching. Everything
  unresolved goes to a curated `Overrides.lua` or the `global` bucket.

## Change discipline
- Prefer the smallest correct change over a broad rewrite.
- Avoid unrelated cleanup or refactors the user didn't ask for.
- Deliver patch-ready, targeted diffs. Do not echo full changed files back — end with a
  per-file line-range briefing (see the user's global instructions).
- When a change alters runtime behavior, state the assumption or caveat and tell the user
  what to verify in-game (`/mtlz`, `/mtlz list`, `/reload`, the tracker window).
- Flag likely API limitations or build-version assumptions up front when uncertain.

## Headless smoke tests
- After editing any addon `.lua`, run `python tests/run.py` (or `.\run-tests.ps1`). It loads
  every file in TOC order under a fake WoW client (`tests/stub.lua`) and drives the full
  lifecycle + all slash commands, asserting only that nothing throws. Fast; runs in CI too.
- It catches load errors, `nil` calls, typos, bad vararg wiring, and obvious logic blow-ups —
  nothing about how Blizzard's real APIs behave, and nothing visual. See `tests/README.md`.
- Passing smoke is **not** "tested": [[no-push-until-tested]] still means an in-game
  `/reload`. Smoke just makes regressions cheap to catch before that.
- To turn a smoke check into a real behavioural assertion, add fixture data to the `warm`
  block in `tests/init.lua` and assert in `tests/smoke.lua`.

## Session continuity
- `context/context-cache.md` is the persistent project memory; `context/immediate-next-steps.md`
  holds the current priority work and `context/future-features.md` holds deferred ideas.
- Immediate next steps always take priority over future features. Record future ideas, don't
  implement them ahead of the current blocker.
- Keep `context/` current — see the `update-context` skill for when and how.
