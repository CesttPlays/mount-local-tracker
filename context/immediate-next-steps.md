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
4. **Config + MinimapButton** — DONE. `Config.lua`: Settings API panel (Window / Mount list /
   Filter by source / Map & minimap) + "Hidden mounts" canvas subcategory (bucketed by source).
   "Filter by source" checkboxes read "Show X" but store the inverted `db.hiddenSources[type]`
   via a metatable proxy. `MinimapButton.lua`: LDB + LibDBIcon launcher. Smoke: cold 67/67,
   warm 74/74; luacheck 10 files. Phase-8 check: 11.0.2 `RegisterAddOnSetting` signature, the
   proxy-table binding (rawget/rawset risk), canvas subcategory, minimap clicks.
5. **Map** — DONE. `Map.lua` (port of the sibling): one HBD-Pins pin per uncollected mount
   with a `row.point`, world + minimap, coloured by obtainability state, gated pins dimmed.
   `MountData.points` is empty so **no pins until Overrides.points is seeded (phase 6)**.
   Smoke: cold 70/70, warm 83/83 (warm seeds a curated point → asserts a pin is placed);
   luacheck 11 files. Phase-8 check: HBD-Pins API arg order on 12.1, pins clear on collect.
6. **Overrides.lua seed** — DONE. ~30 mounts: 7 rare-drop pins (Time-Lost Proto-Drake,
   Aeonaxx, Long-Forgotten Hippogryph, Poseidus, Solar Spirehawk, Voidtalon, Heavenly Onyx
   Cloud Serpent), 18 daily/weekly instance-farm lockouts + 24 drop chances, 7 gold/currency
   vendors, 5 repFaction, 3 `add` (zones the generator missed). Every mountID/uiMapID grepped
   from the DB2 cache. Smoke: cold 73/73, warm 86/86; luacheck 11 files. `context/phase6-
   overrides-seed.md` lists the low-confidence entries (coords, rep-value semantics) for the
   phase-8 in-game spot-check.
7. **tests/ full port + CI + release workflows + context/ refresh** —
   `tests/{run,stub,smoke,init,harness}.lua`, `tests/test_*.py`, `run-tests.ps1`,
   `.github/workflows/{ci,refresh-mount-data,release}.yml`.
8. **Deploy + in-game test** — copy `Mount_Tracker_Local_Zones/` to the install path,
   `/reload`, validate against a written checklist.

## Working rule
- Immediate steps beat future features. Test in-game before committing/pushing
  ([[no-push-until-tested]]). Deploy = copy the whole addon folder.
- No push / PR until the relevant phase is validated in the live client.
