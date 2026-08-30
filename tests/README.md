# Tests

Everything here is **offline** — no WoW client, no wago.tools. It is a
regression net for load/runtime errors, the data-generator transforms, and the
shape of the shipped `MountData.lua`. It is **not** a substitute for an in-game
`/reload` (see "What it does NOT cover" below).

| Suite | Command | What it checks |
|-------|---------|----------------|
| Lint | `luacheck .` | static analysis of every addon Lua file (config: `.luacheckrc`) |
| Headless smoke | `python tests/run.py` | the addon loads in TOC order and drives its whole lifecycle + every `/mtlz` command without throwing |
| Generator | `python -m unittest discover -s tests -p test_generator.py` | the pure transforms in `tools/generate_mount_zones.py` (SourceText parse, zone-name match, instance loot-table join, sanity thresholds, Lua rendering) |

## Run

```powershell
.\run-tests.ps1            # all suites; installs lupa if needed
```

or directly:

```sh
python -m pip install --user lupa       # one time
python tests/run.py                      # smoke
python -m unittest discover -s tests -p "test_*.py" -v
```

Exit code: `0` all passed, non-zero otherwise.

## The headless smoke suite

Two scenarios, each in a fresh Lua state:

| Scenario | Mount API | Exercises |
|----------|-----------|-----------|
| `cold` | `GetMountIDs` returns nothing | file load, event wiring, the readiness-retry loop, slash commands, the "Loading…" path |
| `warm` | a tiny fake world (uiMapID 84 with 4 mounts: one collected, one affordable vendor mount, one renown-gated, one global) | the above **plus** `MountModel.GetZoneMounts` walking the map chain, `BuildRow`, `Obtainability.Evaluate` (available / rep_gated / collected), `GroupRows` by source *and* by expansion, `ListView.Layout`, the window render + summary line, the Global divider |

The `warm` run additionally asserts that `/mtlz list` names the seeded uncollected
mount and the seeded global mount — a guard against the model silently regressing
to an early return.

## What it does NOT cover — still needs an in-game `/reload`

- **Whether Blizzard's real APIs behave as assumed.** `tests/stub.lua` is a
  stand-in: `C_MountJournal.GetMountInfoByID` etc. return hand-written tuples. A
  wrong field index or a changed return signature passes here and breaks live.
- **Anything visual or layout-related.** Frames are inert tables; `SetPoint`,
  sizes, textures, the ScrollBox — all no-ops.
- **Taint / secure-frame rules**, combat lockdown, the real `C_Timer`, saved
  variables round-tripping through the client.
- **The embedded libraries.** `LibStub` and a slice of HereBeDragons-Pins /
  LibDBIcon / LDB are faked so `Map.lua` / `MinimapButton.lua` run their own code
  — the libraries themselves are not loaded.
- **Whether the datamined `MountData.lua` is _correct_.** The generator suite
  checks transform behaviour on fixtures, not that mount 6 really lives in
  Wetlands. Wrong matches are caught only in play (`Overrides.lua`).

So `no-push-until-tested` still stands.

## Files

- `run.py` — spawns a fresh `lupa` Lua state per scenario, prints results, sets exit code.
- `init.lua` — per-scenario setup: install the stub, seed `warm` data, load the addon, run the smoke sequence.
- `stub.lua` — the fake WoW client (frames, timers, events, mount/map/zone/reputation APIs).
- `harness.lua` — reads the `.toc`, loads the addon files, exposes `login()` / `changeZone()` / `collectMount()` / `slash()` / `runTimers()` / …
- `smoke.lua` — the sequence + checks.
- `test_generator.py` — unit tests for `tools/generate_mount_zones.py` (fixtures only, no network).
