# `tools/`

Offline build / datamine helpers. All are **stdlib-only**, run with `python3`,
and fail closed (non-zero exit, nothing written) on a sanity error. None are
shipped in the addon zip (`tools` is in `.pkgmeta` `ignore`).

| Script | What it does | Needs |
|--------|--------------|-------|
| `generate_mount_zones.py` | Regenerates `Mount_Tracker_Local_Zones/MountData.lua` (per-zone `zones` map + flat `global` list) from wago.tools DB2 exports. Run by `.github/workflows/refresh-mount-data.yml`. | network (wago.tools) |
| `push_locale_phrases.py` | Uploads the English phrase set from `Locales/enUS.lua` to CurseForge Localization so translators have something to translate. Run by `.github/workflows/sync-phrases.yml` (manual dispatch). | `CF_API_KEY`, `CF_PROJECT_ID` (unless `--dry-run`) |
| `pull_locale_translations.py` | Rewrites `Locales/<code>.lua` from CurseForge's approved translations. Run by `.github/workflows/refresh-locales.yml`. | `CF_API_KEY`, `CF_PROJECT_ID` (unless `--dry-run`) |

## Localization round-trip

CurseForge Localization is meant to be the translator-facing hub.
`Locales/enUS.lua` is the source of truth; translations live **static in git** so
a dev checkout and the packager need no CurseForge access.

```sh
# Seed / update the CF phrasebook from enUS.lua (add/update only; --prune lets
# CF delete phrases you removed). Preview first. sync-phrases.yml runs the bare
# command on manual dispatch:
python tools/push_locale_phrases.py --dry-run
python tools/push_locale_phrases.py

# Pull approved translations back into Locales/<code>.lua. This is the exact
# command refresh-locales.yml runs:
python tools/pull_locale_translations.py
python tools/pull_locale_translations.py --dry-run          # print URLs only
python tools/pull_locale_translations.py --locales deDE,frFR # subset
```

`pull_locale_translations.py` never touches `Locales/enUS.lua`, drops any
translation that still equals the English key, and skips (with a warning, not a
failure) any line whose `%s` / `%d` placeholders don't match the English key.
A locale with no surviving translations is written as the bare AceLocale stub, so
`git` sees no change.

## Not usable yet: no CurseForge project

The mount addon **has no CurseForge project** — there is no
`## X-Curse-Project-ID` line in the `.toc`, no `CF_API_KEY` secret and no
`deploy` GitHub Environment (see
`plans/010-localization-curseforge-automation.md` and
`context/immediate-next-steps.md`).

Until the project exists:

- `--dry-run` works today (offline, no network).
- A non-`--dry-run` run **exits 1** with a "create the CF project first" message
  and sends nothing (`CF_PROJECT_ID` defaults to the `REPLACE_ME` placeholder).
- `refresh-locales.yml` and `sync-phrases.yml` ship **dispatch-only** — their
  `schedule:` / `push:` triggers are commented out.

When the project is created: add `## X-Curse-Project-ID: <id>` to the `.toc`, set
`CF_PROJECT_ID` as a repo Actions **variable** (or edit each script's
`DEFAULT_PROJECT_ID`), create the `deploy` environment + `CF_API_KEY` secret,
uncomment the workflow triggers, then run
`python tools/push_locale_phrases.py` once to seed the phrasebook.

### API reference

Endpoint constants live in one block at the top of each script. Base:
`https://legacy.curseforge.com/api/projects/<id>/localization/{import,export}`,
auth header `X-Api-Token`. Confirm against the CF project's Localization → "API"
help panel once the project exists, and `BigWigsMods/packager` `release.sh`
(export params) / `p3lim/curseforge-localizations` `update.py` (multipart
import: `metadata` JSON + `localizations` fields).

### Env vars

- `CF_API_KEY` — CurseForge API token. In CI it would come from the `deploy`
  GitHub Environment (same secret `release.yml` uses).
- `CF_PROJECT_ID` — no default. `REPLACE_ME` until the project is created.

## Machine-drafted translations (optional, not built yet)

Plan 010 sketches a `seed_locale_translations.py` that would machine-draft the
standard WoW locales via the Anthropic SDK (`anthropic`, `ANTHROPIC_API_KEY`) so
there's something to review instead of a blank phrasebook. It is a dev
convenience only — never run in CI — and its output **must be human-reviewed and
validated in-game** before merge. Not implemented yet (no CF project to feed).

## Tests

`python -m unittest discover -s tests -p "test_*.py"` covers the pure transforms
in these scripts (`test_generator.py`, `test_locale_tools.py`) plus the shipped
`Locales/` / `MountData.lua` / `.toc` shape. Not an in-game test — see
`tests/README.md`.
