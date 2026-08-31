# Immediate next steps

## Current state (2026-08-31)
- **Phases 1-7 are merged to `main`.** PR #1 (vendor-location waypoints) is merged. The
  stale `phase-buildout` and `feat/vendor-waypoints` branches have been deleted.
- All green offline:
  - `luacheck .` -> 0/0 (11 addon files)
  - `python tests/run.py` -> cold 73/73, warm 86/86
  - `python -m unittest discover -s tests -p "test_*.py"` -> 63 (35 generator + 23 mountdata + 5 toc)
- **In-game: only smoke-touched.** The addon has loaded in the live client once
  (SavedVariables written 2026-08-30, window moved/resized), so it loads and the frame
  works — but the `context/phase8-ingame-checklist.md` sections A-G have NOT been worked
  through. The load-bearing WoW API assumptions are still unverified in the client.
- **Not released.** No git tag, no GitHub Release. TOC is at the default `## Version: 0.1.0`.

## GitHub setup (pending — needed before the first release)
- **`deploy` environment** — create it:
  `gh api --method PUT repos/CesttPlays/mount-local-tracker/environments/deploy`
- **"Allow GitHub Actions to create and approve pull requests"** — enable it (needed by
  `refresh-mount-data.yml`'s `create-pull-request` step): repo Settings -> Actions ->
  General -> Workflow permissions, or
  `gh api --method PUT repos/CesttPlays/mount-local-tracker/actions/permissions/workflow -F can_approve_pull_request_reviews=true -f default_workflow_permissions=read`
- Only when the CurseForge project exists: the `CF_API_KEY` secret in the `deploy`
  environment + a `## X-Curse-Project-ID` line in the `.toc`. GitHub Release + zip work
  without them.

## Next: phase 8 — in-game validation + first release
1. Work through `context/phase8-ingame-checklist.md` (A-G) in the live client. Fix as you
   go; re-run `.\run-tests.ps1` after every fix. Move verified APIs from PENDING to a dated
   "validated" note in `context/wow-api-reference-cache.md`.
2. When it all passes: bring `context/` fully up to date in the same commit
   ([[bundle-context-updates-into-feature-commit]]).
3. First release: **manual dispatch of `release.yml` with `version = 0.1.0`.**

## Deferred (not blockers — see `context/future-features.md`)
- Achievement-reward mount -> zone resolver (~60 mounts sitting in `global`).
- `lockoutQuest` ids so Obtainability can show "done this reset".
- Variant-map dedup for the `zones` table.
- Vendor cost / rep-requirement from DB2 instead of hand-curation.

## Working rule
- Test in-game before releasing ([[no-push-until-tested]]).
- Deploy = copy the whole `Mount_Tracker_Local_Zones/` folder.
