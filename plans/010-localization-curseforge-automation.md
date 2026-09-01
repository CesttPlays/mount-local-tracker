# Plan 010: CurseForge phrase push/pull tooling + `refresh-locales` workflow

> **Executor instructions**: Build the scripts, dry-run them, wire the workflow,
> then update the status row in `plans/README.md`. The **live** parts (a real CF
> push/pull, enabling the workflow schedule) are **BLOCKED** until the CurseForge
> project exists — see "Blocking prerequisites" below. The **docs sub-step (Step
> 6)** is additionally blocked until plan 009 has been validated in-game.
>
> **Drift check (run first)**:
> `git diff --stat 8188db1..HEAD -- .pkgmeta .github/workflows/ tools/ Mount_Tracker_Local_Zones/Locales/`

## Provenance

Port of `achivement-local-tracker/plans/007` (2026-08-31), re-derived against
this repo at `8188db1` on 2026-09-01. Same design; the material differences from
the sibling are called out in **"Blocking prerequisites"** and **"What differs
from the sibling"** below.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW-MEDIUM — new files + one new workflow; the workflow only ever
  opens a PR, never merges. The live CF calls cannot be exercised until the CF
  project exists, so all verification here is dry-run / offline.
- **Depends on**: 008 (final `Locales/enUS.lua` phrase set). Step 6 also depends
  on 009 validated in-game. **Live use** additionally depends on the CF project
  (see below).
- **Category**: tooling / CI
- **Planned at**: commit `8188db1`, 2026-09-01

## Why this matters

Plans 008-009 make the addon localizable but leave translation as a manual chore.
This plan makes CurseForge Localization the translator-facing hub and automates
both directions:

- **push**: English phrases from `Locales/enUS.lua` → the CF phrasebook.
- **pull**: approved CF translations → committed `Locales/<code>.lua`, via a
  scheduled workflow that opens a PR and never merges itself — the exact pattern
  this repo already uses for `MountData.lua` (`refresh-mount-data.yml`).

Translations stay **static in git** (they work in a dev checkout, the packager
needs no CF access at build time), and every translation change gets the same
review-before-merge treatment as datamined data.

## Blocking prerequisites (why the live half is deferred)

Unlike the sibling repo, **the mount addon has no CurseForge project yet**
(`context/immediate-next-steps.md`, `context/context-cache.md`):

- No `## X-Curse-Project-ID` line in the `.toc`.
- No `CF_API_KEY` secret, no `deploy` GitHub Environment, and the repo's Actions
  "allow GitHub Actions to create and approve pull requests" toggle is still off
  (the same gate that blocks `refresh-mount-data.yml` from being trusted).

So this plan **builds and dry-runs** the scripts + workflow now (they are
useful the moment the project exists and cost nothing to carry), but:

- `CF_PROJECT_ID` default is left as a **`REPLACE_ME` placeholder** with a clear
  comment; the scripts must `exit 1` with a helpful message if it is still the
  placeholder on a non-`--dry-run` invocation.
- `refresh-locales.yml` ships with its `schedule:` trigger **commented out** —
  only `workflow_dispatch` is active — so it never fires on a cron until someone
  deliberately enables it.
- The status row stays **BLOCKED (CF project not created)** for the live parts;
  the "scripts + workflow file exist and dry-run" part can be marked DONE.

When the CF project is created, the follow-up is: add `## X-Curse-Project-ID` to
the `.toc`, set the real id as `CF_PROJECT_ID` default (one edit per script) or
rely on the env var, create the `deploy` environment + `CF_API_KEY` secret,
uncomment the `schedule:` block, and run the post-merge steps at the bottom.

## What differs from the sibling (007)

| Sibling (007) | Here (010) |
|---|---|
| CF project id `1674769` hardcoded as default | `CF_PROJECT_ID` default = `REPLACE_ME` placeholder + guard |
| `refresh-locales.yml` schedule active | `schedule:` commented out; dispatch-only |
| `environment: deploy` already exists | `environment: deploy` referenced but must be created first |
| Addon folder `Achivement_Tracker_Local_Zones` | `Mount_Tracker_Local_Zones` |
| `refresh-zone-data.yml` is the pattern to mirror | `refresh-mount-data.yml` is the pattern to mirror |
| `tools/generate_zone_achievements.py` house style | `tools/generate_mount_zones.py` house style |

## Background facts

- CF **legacy** Localization API base:
  `https://legacy.curseforge.com/api/projects/<id>/localization/{export,import}`.
  Confirm the exact query params / multipart field names against **(a)** the CF
  project's Localization → "API" help panel (once the project exists) and
  **(b)** `BigWigsMods/packager`'s `release.sh` (its `export` call is the
  canonical working reference). Keep the URL + params in one constant block per
  script so a change is one edit.
- Auth header for the CF Localization API: `X-Api-Token: <CF_API_KEY>`.
- `.pkgmeta` has **no** `@localization@` tokens and this plan adds none — the
  packager stays out of localization. `Locales/` is not in the `.pkgmeta`
  `ignore:` list, so it already ships.
- `tools/` house style (see `generate_mount_zones.py`): `#!/usr/bin/env python3`,
  a "why" module docstring ending with a `Usage:` block,
  `from __future__ import annotations`, stdlib only, exits non-zero and writes
  nothing on a sanity failure.

## Scope

**In scope** (create):

- `tools/push_locale_phrases.py` — stdlib
- `tools/pull_locale_translations.py` — stdlib
- `tools/seed_locale_translations.py` — OPTIONAL, needs `anthropic`
- `tools/README.md` — NEW
- `.github/workflows/refresh-locales.yml` (schedule commented out)
- `.github/workflows/sync-phrases.yml` — OPTIONAL
- Step 6 only: `README.md`, `CURSEFORGE.md` edits

**Out of scope**: `.pkgmeta` (no change), `release.yml`, `ci.yml`,
`refresh-mount-data.yml`, any addon `.lua`, the `.toc` (the
`## X-Curse-Project-ID` line is a CF-project-creation follow-up, not this plan).

## Commands you will need

| Purpose | Command | Expected |
|---------|---------|----------|
| Push dry-run | `python tools/push_locale_phrases.py --dry-run` | prints phrase count + the request it *would* send; exit 0; no network |
| Pull dry-run | `python tools/pull_locale_translations.py --dry-run` | prints the per-locale URLs it *would* GET; exit 0; no network |
| Push without id | `python tools/push_locale_phrases.py` (no `--dry-run`, placeholder id) | `exit 1` with "set CF_PROJECT_ID / create the CF project first" |
| Python suite | `python -m unittest discover -s tests -p "test_*.py"` | `OK` |
| Workflow lint | `python -c "import yaml; yaml.safe_load(open('.github/workflows/refresh-locales.yml'))"` | no error |

## Git workflow

- Branch: `feat/010-localization-automation`.
- Commits: (1) `tools: CurseForge phrase push/pull scripts`,
  (2) `ci: add refresh-locales workflow (dispatch-only until CF project exists)`,
  (3 optional) `tools: machine-seed translations via Anthropic SDK`,
  (4, after 009 in-game + CF project) `docs: document translation support`.
- No session-URL trailer.
- Do NOT push Step 6 until plan 009 is validated in-game.

## Steps

### Step 1: `tools/push_locale_phrases.py`

**Purpose**: upload the English phrase set to CurseForge as the base language so
translators can work on it.

- Docstring: why (CF is the translation hub; `enUS.lua` is the source of truth),
  then `Usage: python tools/push_locale_phrases.py [--dry-run] [--prune]`.
- Env: `CF_API_KEY` (required unless `--dry-run`), `CF_PROJECT_ID` (default
  `REPLACE_ME` — see "Blocking prerequisites"). On a non-`--dry-run` run with the
  default still in place, print
  `"CF_PROJECT_ID is unset and no CurseForge project exists yet — see plans/010"`
  and `exit 1` before any network.
- Read `Mount_Tracker_Local_Zones/Locales/enUS.lua`. Extract every `L["..."]` /
  `L['...']` key. Handle both `= true` and `= "literal"` right-hand sides. A
  small regex or a real mini-parser — but **validate**: keys non-empty, no
  duplicate keys (raw-text scan), every `%` placeholder well-formed (`%%`, `%d`,
  `%s`, `%1$s`, `%.1f` …). Abort (write nothing, `exit 1`) on any failure.
- Build the CF import payload: `multipart/form-data` with
  `metadata = {"language":"enUS","namespace":"","missing-phrases": <bool>}` and
  `localizations = <the L["..."] = "..." block>` (emit each key as
  `L["key"] = "key"` — CF wants explicit English text on both sides).
  `--prune` sets `missing-phrases: true`; default `false` (add/update only).
- Build the multipart body by hand with `urllib.request`. Header `X-Api-Token`.
- `--dry-run`: print the phrase count, the endpoint, and the first ~10 lines of
  the `localizations` blob; do not open a socket; exit 0.
- On a real run: print the HTTP status + response body; non-2xx → `exit 1`.

### Step 2: `tools/pull_locale_translations.py`

**Purpose**: regenerate `Locales/<code>.lua` from CurseForge's current approved
translations. This is what the workflow runs.

- Docstring + `Usage: python tools/pull_locale_translations.py [--locales de,fr]
  [--dry-run]`.
- Env: `CF_API_KEY` (required unless `--dry-run`), `CF_PROJECT_ID` (same
  placeholder + guard as Step 1).
- Locale set: default = `deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW` (the
  ship list minus `enUS`); `--locales` overrides.
- Read `Locales/enUS.lua` first for the authoritative key set.
- Per locale:
  `GET .../localization/export?lang=<code>&export-type=Table&unlocalized=Ignore&table-name=L`
  with `X-Api-Token`. Body is a Lua `L["key"] = "value"` snippet.
  - Keep only lines whose key is in `enUS.lua`.
  - Drop lines where `value == key` (untranslated; the fallback covers it).
  - Placeholder parity: the multiset of `%`-tokens in `value` must equal that of
    the enUS key. Mismatch → **skip that line and warn**, do not fail the run.
- Write `Locales/<code>.lua`:
  ```lua
  -- GENERATED from CurseForge Localization by tools/pull_locale_translations.py.
  -- Manual edits are overwritten. Untranslated keys fall back to Locales/enUS.lua.

  local addonName = ...
  local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "<code>")
  if not L then return end

  L["<key>"] = "<value>"   -- sorted in the same order as enUS.lua
  ```
  If zero lines survive, write the bare stub (no `L["..."]` lines) — identical to
  the plan-008 stub, so `git` sees no change.
- **Sanity gate**: if any locale request returns non-200, or the body doesn't
  parse as `L[...] = ...` lines at all, abort the whole run and write nothing
  (`exit 1`) — mirrors the generator's fail-closed stance.
- `--dry-run`: print the URL per locale and exit 0 without writing.
- Output: one line per locale, e.g.
  `deDE: 41/94 phrases (2 skipped: placeholder mismatch)`.
- **Never touch `Locales/enUS.lua`.**

### Step 3: `tools/seed_locale_translations.py` — OPTIONAL

**Purpose**: machine-draft translations for the standard WoW locales so there's
something to review instead of a blank phrasebook. Not run in CI.

- Docstring makes the `anthropic` dependency explicit and notes it is dev-only.
  `Usage: python tools/seed_locale_translations.py [--locales ...] [--only-missing]
  [--out {files,cf}]` (default `files`).
- Env: `ANTHROPIC_API_KEY`.
- Read `enUS.lua` for phrases and existing `Locales/<code>.lua` for already-done
  keys (`--only-missing` skips those).
- One Claude call per locale (current Sonnet — see the `claude-api` skill for the
  model id, keep it a single constant near the top). System prompt: *translate
  WoW addon UI strings into `<locale>` using Blizzard's official in-client
  terminology; preserve every `%s` / `%d` / `%1$s` placeholder exactly and in
  order; keep `/mtlz`, `/reload` and the literal sub-command list
  (`show | list | config | map | debug | reset`) verbatim; keep any `|cff…|r`
  colour escapes; return a JSON object mapping each English source string to its
  translation, nothing else.*
- Validate placeholder parity per line; drop and warn on mismatch.
- `--out files`: rewrite `Locales/<code>.lua` with a
  `-- MACHINE-DRAFTED, needs human review` banner line, same shape as Step 2.
- `--out cf`: POST to the import endpoint per language. Docstring note: CF's
  import has no "suggestion" state — imported strings are live translations — so
  `files` (review in a PR) is the safer default.

### Step 4: `tools/README.md`

Short: what each script does, which need env vars, which need `anthropic`, the
one-liner `refresh-locales.yml` runs, and a prominent note that the live CF
calls need the CurseForge project to exist first (`CF_PROJECT_ID` +
`## X-Curse-Project-ID` + `CF_API_KEY`). Note `seed_*` output must be
human-reviewed before merge.

### Step 5: `.github/workflows/refresh-locales.yml`

Mirror `refresh-mount-data.yml` conventions (branch name `chore/refresh-locales`,
`peter-evans/create-pull-request@v6`, `labels: automated`, never auto-merge,
`Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` in the commit message).
**Ship with the `schedule:` block commented out** — dispatch-only until the CF
project exists.

```yaml
name: Refresh locales

# Pulls approved translations from CurseForge Localization into
# Mount_Tracker_Local_Zones/Locales/<locale>.lua and opens a pull request.
# Never merges on its own -- the diff is reviewed and validated in-game (client
# set to that language) first. Mirrors refresh-mount-data.yml.
#
# Dispatch-only until the CurseForge project exists (needs CF_PROJECT_ID, the
# ## X-Curse-Project-ID .toc line, and the CF_API_KEY secret in the "deploy"
# environment). Uncomment the schedule block once that is in place.

on:
  workflow_dispatch:
  # schedule:
  #   - cron: "37 9 * * 2"  # Tuesdays ~09:37 UTC, just after refresh-mount-data

permissions:
  contents: write
  pull-requests: write

jobs:
  refresh:
    runs-on: ubuntu-latest
    environment: deploy          # CF_API_KEY lives here (same as release.yml)
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - name: Pull translations from CurseForge
        env:
          CF_API_KEY: ${{ secrets.CF_API_KEY }}
          CF_PROJECT_ID: ${{ vars.CF_PROJECT_ID }}
        run: python tools/pull_locale_translations.py

      - name: Lua syntax check
        run: |
          sudo apt-get update && sudo apt-get install -y --no-install-recommends lua5.1
          for f in Mount_Tracker_Local_Zones/Locales/*.lua; do
            lua5.1 -e "assert(loadfile('$f'))" || exit 1
          done

      - name: Validate locale-file shape
        run: python -m unittest discover -s tests -p "test_locales.py" -v

      - name: Open pull request
        uses: peter-evans/create-pull-request@v6
        with:
          branch: chore/refresh-locales
          add-paths: Mount_Tracker_Local_Zones/Locales/*.lua
          title: "chore: refresh translations from CurseForge"
          commit-message: |
            chore: refresh translations from CurseForge

            Regenerated Locales/*.lua from CurseForge Localization by the
            refresh-locales workflow. Base language (enUS) is not touched.

            Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
          body: |
            Automated refresh of `Mount_Tracker_Local_Zones/Locales/*.lua`
            from CurseForge Localization. Only per-language files change;
            `Locales/enUS.lua` is the source of truth and is left alone.

            **Before merging:** skim the diff, then log in with the client set to
            each changed language (or `/console locale <code>` + `/reload`) and
            eyeball the tracker window, `/mtlz config`, the right-click menu and
            the minimap tooltip. Watch for clipped text and broken `%s` / `%d`.

            Generated with Claude Code
          labels: automated
```

`environment: deploy` may carry a required-reviewer gate (as `release.yml`
does) — the run will pause for the maintainer's approval, which is fine.

### Step 5b: `.github/workflows/sync-phrases.yml` — OPTIONAL

Only if the maintainer wants hands-off phrase upload once the CF project exists:

```yaml
name: Sync phrases to CurseForge

on:
  workflow_dispatch:
  # push:
  #   branches: [main]
  #   paths:
  #     - "Mount_Tracker_Local_Zones/Locales/enUS.lua"

permissions:
  contents: read

jobs:
  push:
    runs-on: ubuntu-latest
    environment: deploy
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Push English phrases to CurseForge
        env:
          CF_API_KEY: ${{ secrets.CF_API_KEY }}
          CF_PROJECT_ID: ${{ vars.CF_PROJECT_ID }}
        run: python tools/push_locale_phrases.py
```

Add/update only (no `--prune`), so it is idempotent. If the maintainer prefers to
run the push by hand, skip this file and document the command in
`tools/README.md`.

### Step 6: docs — BLOCKED until plan 009 is validated in-game AND the CF project exists

- `README.md`: a short "Translations" section — the addon follows the game
  client language; untranslated strings fall back to English; contribute
  translations on the CurseForge Localization page (link the project). Keep it to
  capabilities, no implementation detail (repo rule for README).
- `CURSEFORGE.md`: add `AceLocale-3.0` to the "Bundles the following open
  libraries: …" line (currently `LibStub, CallbackHandler-1.0,
  LibDataBroker-1.1, LibDBIcon-1.0, and HereBeDragons-2.0`), and add one line
  under a "Compatibility" / "Languages" heading noting community translations via
  CF Localization.

## Test plan

- `python tools/push_locale_phrases.py --dry-run` → phrase count matches the
  number of `L[...]` lines in `enUS.lua`; prints a well-formed request preview;
  exit 0.
- `python tools/pull_locale_translations.py --dry-run` → prints 10 export URLs
  (one per non-enUS locale); exit 0; `git status` clean.
- `python tools/push_locale_phrases.py` (no dry-run, placeholder id) → `exit 1`
  with the "create the CF project first" message; nothing sent.
- `python -m unittest discover -s tests -p "test_*.py"` → `OK`.
- YAML parses (command in the table above); confirm `schedule:` is commented out.
- If `anthropic` is installed and `ANTHROPIC_API_KEY` set:
  `python tools/seed_locale_translations.py --locales deDE --out files` produces
  a reviewable `Locales/deDE.lua`; revert it after inspecting.

## Done criteria

- [ ] `tools/push_locale_phrases.py` + `tools/pull_locale_translations.py` exist,
      stdlib-only, `--dry-run` works offline, non-dry-run without a real
      `CF_PROJECT_ID` fails closed
- [ ] `tools/README.md` documents all scripts + env vars + the CF-project
      prerequisite
- [ ] `.github/workflows/refresh-locales.yml` parses, mirrors
      `refresh-mount-data.yml`, opens a PR on `chore/refresh-locales`, never
      merges, and its `schedule:` is commented out
- [ ] `python -m unittest discover -s tests -p "test_*.py"` → `OK`
- [ ] Step 6 (docs) done **only** after plan 009's in-game checklist passed and
      the CF project exists
- [ ] `plans/README.md` status row for 010 updated (BLOCKED for the live half)

## Post-merge (out of band, maintainer — after the CF project is created)

1. Add `## X-Curse-Project-ID: <id>` to the `.toc`; set `CF_PROJECT_ID` as a repo
   Actions **variable** (or edit the script defaults); create the `deploy`
   environment + `CF_API_KEY` secret; enable "Actions can create and approve
   PRs".
2. Uncomment the `schedule:` block in `refresh-locales.yml` (and, if wanted,
   `sync-phrases.yml`).
3. Run `python tools/push_locale_phrases.py` (or dispatch `sync-phrases.yml`) to
   seed the CF `enUS` phrasebook.
4. Optionally run `tools/seed_locale_translations.py --out files`, review the
   drafts, commit the good ones.
5. Dispatch `refresh-locales.yml`; validate each changed language in-game before
   merging that PR.
6. `release.yml` only auto-fires on a `MountData.lua` change, so an i18n-only
   merge won't ship automatically — cut the release with a manual
   `workflow_dispatch` once everything is validated. The packager needs no
   changes: `Locales/*.lua` are ordinary files it already zips.

## STOP conditions

- The CF Localization API shape differs from what's assumed here and you can't
  confirm the correct params from the CF help panel or the BigWigs packager
  source — stop and report; do not guess at a live POST.
- `pull_locale_translations.py` would rewrite `Locales/enUS.lua`.
- Step 6 reached before plan 009 is validated in-game / the CF project exists.
- A script would send a live request with the placeholder `CF_PROJECT_ID`.

## Maintenance notes

- `## Notes-xxXX` localized TOC descriptions could be added later: give the
  `## Notes` text its own phrase key and have `pull_locale_translations.py` also
  rewrite the `## Notes-xxXX:` lines from the CF export. Not worth it for v1.
- If CF's `export-type=Table` output format changes, only the parse step in
  `pull_locale_translations.py` needs updating — keep it isolated in one function.
- The seed script's model id will drift — read it from the `claude-api` skill or
  keep it a single constant near the top.
