# Immediate next steps

## Current state (2026-08-31)
- **Phases 1-9 done. Merged to `main`.** PR #1 (vendor waypoints), PR #2 (context
  reconcile) and PR #3 (phase-9 code-quality refactor) merged. Stale `phase-buildout` /
  `feat/vendor-waypoints` branches deleted.
- All green offline:
  - `luacheck .` -> 0/0 (12 addon files)
  - `python tests/run.py` -> cold 89/89, warm 121/121
  - `python -m unittest discover -s tests -p "test_*.py"` -> 90 (35 generator + 23 mountdata
    + 27 obtainability + 5 toc)
- **In-game: validated 2026-08-31.** Worked through `context/phase8-ingame-checklist.md`
  A-G in the live client — everything runs, no addon-code fixes were needed. The
  load-bearing WoW API assumptions (`GetMountInfoByID` tuple order, HBD-Pins arg order,
  the Settings metatable-proxy binding, `C_Reputation` / `C_MajorFactions` field names)
  are now confirmed; see `context/wow-api-reference-cache.md`. Curated coords in
  `Overrides.lua` remain eyeballed (display-only, per plan).
- **Not released yet.** No git tag, no GitHub Release. TOC at the default `## Version: 0.1.0`.

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

## Next: first release (0.1.0)
1. Do the "GitHub setup" above (deploy environment + the Actions PR-creation toggle).
2. **Manual dispatch of `release.yml` with `version = 0.1.0`** — bumps the `.toc`, tags
   `v0.1.0`, runs the BigWigs packager, publishes the GitHub Release + zip.
3. CurseForge upload only happens once the project exists and `CF_API_KEY` /
   `## X-Curse-Project-ID` are wired.

## Deferred (not blockers — see `context/future-features.md`)
- Achievement-reward mount -> zone resolver (~60 mounts sitting in `global`).
- `lockoutQuest` ids so Obtainability can show "done this reset".
- Variant-map dedup for the `zones` table.
- Vendor cost / rep-requirement from DB2 instead of hand-curation.

## Working rule
- Test in-game before releasing ([[no-push-until-tested]]).
- Deploy = copy the whole `Mount_Tracker_Local_Zones/` folder.
