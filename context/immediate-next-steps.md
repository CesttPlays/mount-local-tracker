# Immediate next steps

## Current blocker
- Phase 1 (skeleton) written and green locally (`luacheck .` clean; lupa load test
  drives ADDON_LOADED → PLAYER_LOGIN → zone/mount events → every `/mtlz` command with
  nothing thrown). Deployed to the install path. **Awaiting in-game `/reload` check**:
  `/mtlz` (bare) is a no-op until the window lands; `/mtlz help` / any unknown arg must
  print `Commands: /mtlz [show | list | config | map | debug | reset]`; `/mtlz debug`
  toggles and, with it on, a zone change prints `Zone: <name> (uiMapID <n>)`.
  Once confirmed: commit phases-1 files + this doc together, then phase 2.

## Build order (each phase testable before the next)
1. **Skeleton** — DONE (local). `Mount_Tracker_Local_Zones.toc`, `Core.lua`
   (SavedVariables + `/mtlz` slash + event frame + `BindMount`/menu/waypoint helpers,
   no data yet), empty `MountData.lua` (all tables present, empty), `Overrides.lua`
   stub, `Mechanic.lua` (do-not-package dev hub), `Libs/` copied from the sibling repo,
   `.luacheckrc`, `.pkgmeta`, `LICENSE` (MIT), real `README.md`, `.gitignore` +
   `libs.json` path fixups, `run-tests.ps1`. `luacheck .` green. Pending in-game check.
2. **Generator v1** — DONE. `tools/generate_mount_zones.py` (instance loot-table pass +
   `SourceText_lang` `Zone:`/`Location:` parse + `global` bucket; enum ignored). Item→spell→
   mount link verified on 12.1.0.69497. `MountData.lua` regenerated (293 zones / 1846 refs /
   988 global). `tests/test_generator.py` — 35 tests green. luacheck green. See context-cache.md
   "Data pipeline" for the offline `wow.tools.local` DB2 procedure.
3. **MountModel + Obtainability + ListView + Window** — DONE. `Obtainability.lua`
   (Evaluate → collected/available/rep_gated/achievement_gated/reset_locked/farmable/drop +
   tooltip lines), `MountModel.lua` (CandidateSet/GlobalCandidateSet, BuildRow with 6 filters,
   GroupRows by source *and* expansion, GetZoneMounts + cache, Summary, RefreshCachedStates),
   `ListView.xml`/`ListView.lua` (grouped ScrollBox, Obtainability colours, Global divider),
   `Window.lua` (chrome port + summary line "Zone — C/T collected · N available · a/b account").
   `tests/` smoke harness ported: `python tests/run.py` → cold 55/55, warm 62/62, exit 0.
   luacheck green (8 files). Notes for phase-8 in-game check: verify `GetMountInfoByID` tuple
   order, `GameTooltip:SetMountBySpellID`, ScrollBox API, stylized summary-line layout.
4. **Config + MinimapButton** — Settings panel incl. the `groupBy` dropdown; minimap launcher.
5. **Map** — world-map + minimap pins for positioned uncollected mounts.
6. **Overrides.lua seed** — ~25 well-known curated rare-drop / vendor mounts with coords.
7. **tests/ full port + CI + release workflows + context/ refresh** —
   `tests/{run,stub,smoke,init,harness}.lua`, `tests/test_*.py`, `run-tests.ps1`,
   `.github/workflows/{ci,refresh-mount-data,release}.yml`.
8. **Deploy + in-game test** — copy `Mount_Tracker_Local_Zones/` to the install path,
   `/reload`, validate against a written checklist.

## Working rule
- Immediate steps beat future features. Test in-game before committing/pushing
  ([[no-push-until-tested]]). Deploy = copy the whole addon folder.
- No push / PR until the relevant phase is validated in the live client.
