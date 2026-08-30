# Immediate next steps

## Current state
- **Phases 1-7 built on branch `phase-buildout`, all green offline.** Not validated in-game,
  not merged to `main`, not released.
  - `luacheck .` -> 0/0 (11 addon files)
  - `python tests/run.py` -> cold 73/73, warm 86/86
  - `python -m unittest discover -s tests -p "test_*.py"` -> 63 (35 generator + 23 mountdata + 5 toc)

## Next: phase 8 — in-game validation + first release
1. Copy `Mount_Tracker_Local_Zones/` to
   `E:\Blizzard\World of Warcraft\_retail_\Interface\AddOns\Mount_Tracker_Local_Zones\`,
   `/reload`, and work through **`context/phase8-ingame-checklist.md`** across >=3 zones,
   a city, and a dungeon zone.
2. Fix whatever the checklist turns up (most likely: `GetMountInfoByID` tuple order, the
   Settings source-filter proxy binding, HBD-Pins arg order, phase-6 coords). Re-run the
   offline suites after each fix.
3. When it passes: bring `context/` fully up to date, merge `phase-buildout` -> `main`.
4. Before the first release, set up on GitHub: the **`deploy` environment**, the
   **"Allow GitHub Actions to create and approve pull requests"** repo setting (for the
   refresh workflow), and — when the CurseForge project exists — the `CF_API_KEY` secret in
   `deploy` + a `## X-Curse-Project-ID` line in the `.toc`.
5. First release: **manual dispatch of `release.yml` with `version = 0.1.0`.**

## Build order (done)
1. Skeleton — DONE. TOC, Core.lua, empty MountData.lua, Overrides stub, Mechanic.lua, Libs,
   `.luacheckrc` / `.pkgmeta` / `LICENSE` / `run-tests.ps1`, README.
2. Generator v1 — DONE. `tools/generate_mount_zones.py` (instance loot-table + SourceText
   `Zone:`/`Location:` parse + global bucket). `MountData.lua` for 12.1.0.69497.
   `tests/test_generator.py` (35).
3. MountModel + Obtainability + ListView + Window — DONE. Smoke harness ported.
4. Config + MinimapButton — DONE. Settings panel + "Hidden mounts" subcategory + minimap
   launcher.
5. Map — DONE. HBD-Pins world + minimap pins for positioned uncollected mounts.
6. Overrides seed — DONE. ~30 mounts (7 rare-drop pins, 18 lockouts, 7 vendors, 5 repFaction,
   3 add). `context/phase6-overrides-seed.md` has the low-confidence list.
7. tests/ + CI + release + context — DONE. `tests/test_mountdata.py` (23), `tests/test_toc.py`
   (5), `.github/workflows/{ci,refresh-mount-data,release}.yml`, `CURSEFORGE.md`, README
   badges, context refresh, `context/phase8-ingame-checklist.md`.
8. In-game validation + first release — PENDING (see "Next" above).

## Working rule
- Test in-game before merging to main / releasing ([[no-push-until-tested]]).
- Deploy = copy the whole addon folder.
