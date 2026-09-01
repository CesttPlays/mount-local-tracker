#!/usr/bin/env python3
"""Regenerate Locales/<code>.lua from CurseForge's current approved translations.

This is what .github/workflows/refresh-locales.yml runs: it pulls every
non-English locale from CurseForge Localization and rewrites the committed
Mount_Tracker_Local_Zones/Locales/<code>.lua files, then the workflow opens a
pull request. Translations stay static in git -- a dev checkout and the packager
need no CurseForge access.

Mount_Tracker_Local_Zones/Locales/enUS.lua is the source of truth for the key set
and is never touched. A translation is dropped when it equals the English key
(untranslated -- the AceLocale fallback covers it) or when its `%` placeholders
don't match the English key (a bad CF entry is skipped with a warning, it does
not fail the run).

NOTE: the mount addon has no CurseForge project yet (see plans/010). Until it
exists, a non-`--dry-run` run fails closed; `--dry-run` prints the URLs offline.

Reference for the export URL + params: BigWigsMods/packager `release.sh`.

Usage:
  python tools/pull_locale_translations.py [--locales deDE,frFR] [--dry-run]

  --locales   comma-separated subset of the ship locales (default: all non-enUS)
  --dry-run   print the export URL per locale and exit; no network, no writes.

Env:
  CF_API_KEY     CurseForge API token (required unless --dry-run)
  CF_PROJECT_ID  CurseForge project id. No default -- the project does not exist
                 yet, so this is REPLACE_ME until it is created.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import urllib.error
import urllib.request

# --- CurseForge Localization API ------------------------------------------------
# One edit point if CurseForge changes the endpoint, header or query params.
CF_API_BASE = "https://legacy.curseforge.com/api/projects/{project_id}/localization"
CF_EXPORT_URL = CF_API_BASE + "/export"
CF_EXPORT_PARAMS = "export-type=Table&unlocalized=Ignore&table-name=L"
CF_AUTH_HEADER = "X-Api-Token"

# The ship list minus enUS (see tests/test_locales.py TRANSLATIONS).
DEFAULT_LOCALES = ["deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]
# The mount addon has no CurseForge project yet -- see plans/010.
PLACEHOLDER_PROJECT_ID = "REPLACE_ME"
DEFAULT_PROJECT_ID = PLACEHOLDER_PROJECT_ID

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALES_DIR = os.path.join(ROOT, "Mount_Tracker_Local_Zones", "Locales")
ENUS_PATH = os.path.join(LOCALES_DIR, "enUS.lua")

# L["key"] = true  in enUS.lua (escaped quotes in the key handled).
ENUS_KEY_RE = re.compile(
    r"""^\s*L\[\s*(?P<q>["'])(?P<key>(?:\\.|(?!(?P=q)).)*)(?P=q)\s*\]\s*="""
)
# ["key"] = "value"  or  L["key"] = "value"  (optional trailing comma), as the
# CF export emits -- tolerant of both a bare-additions and a table-constructor body.
EXPORT_PAIR_RE = re.compile(
    r"""^\s*(?:L\s*)?\[\s*(?P<kq>["'])(?P<key>(?:\\.|(?!(?P=kq)).)*)(?P=kq)\s*\]\s*=\s*"""
    r"""(?P<vq>["'])(?P<val>(?:\\.|(?!(?P=vq)).)*)(?P=vq)\s*,?\s*$"""
)
# Lines in an export body that carry no translation: a comment, a blank line, the
# `L = {` / `L = L or {}` table opener, or a closing `}` / `},`.
EXPORT_NOISE_RE = re.compile(r"""^\s*(?:--.*|L\s*=\s*L?\s*(?:or)?\s*\{\s*\}?|[}\],]+)?\s*$""")
PLACEHOLDER_RE = re.compile(r"%\d+\$s|%[-+ #0-9.]*[sdfxXqg%]")


class PullError(Exception):
    """A sanity failure -- the run writes nothing and exits non-zero."""


def lua_unescape(raw: str) -> str:
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1), m.group(1)), raw)


def read_enus_keys(path: str) -> "list[tuple[str, str]]":
    """[(quote, raw_key), ...] in source order -- the authoritative key set."""
    keys: list[tuple[str, str]] = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if not line.strip().startswith("L["):
                continue
            match = ENUS_KEY_RE.match(line)
            if match:
                keys.append((match.group("q"), match.group("key")))
    if not keys:
        raise PullError(f"{path}: no L[...] keys found")
    return keys


def parse_export(body: str) -> "dict[str, tuple[str, str]]":
    """logical key -> (value_quote, raw_value) for every pair in a CF export body.

    Raises PullError if the body is an error page, or has meaningful content that
    is not a `[...] = "..."` line at all (a shape change we must not paper over)."""
    head = body.lstrip()[:200].lower()
    if head.startswith(('{"error', "{'error")) or "<!doctype" in head or "<html" in head:
        raise PullError(f"export looks like an error response: {body.strip()[:200]!r}")

    pairs: dict[str, tuple[str, str]] = {}
    junk: list[str] = []
    for line in body.splitlines():
        if not line.strip() or EXPORT_NOISE_RE.match(line):
            continue
        match = EXPORT_PAIR_RE.match(line)
        if match:
            pairs[lua_unescape(match.group("key"))] = (match.group("vq"), match.group("val"))
        else:
            junk.append(line.strip())
    if junk and not pairs:
        raise PullError(f"export body did not parse as L[...] = ... lines: {junk[0]!r}")
    return pairs


def placeholders(text: str) -> "list[str]":
    return sorted(PLACEHOLDER_RE.findall(text))


def render_locale(code: str, lines: "list[tuple[str, str, str]]") -> str:
    """`lines` = [(key_quote, raw_key, rendered_value), ...] already in enUS order."""
    out = [
        "-- GENERATED from CurseForge Localization by tools/pull_locale_translations.py.",
        "-- Manual edits are overwritten. Untranslated keys fall back to Locales/enUS.lua.",
        "",
        "local addonName = ...",
        f'local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "{code}")',
        "if not L then return end",
    ]
    if lines:
        out.append("")
        for kq, raw_key, value in lines:
            out.append(f"L[{kq}{raw_key}{kq}] = {value}")
    return "\n".join(out) + "\n"


def fetch_export(endpoint: str, code: str, api_key: str) -> str:
    request = urllib.request.Request(
        f"{endpoint}?lang={code}&{CF_EXPORT_PARAMS}",
        headers={CF_AUTH_HEADER: api_key},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            if response.status != 200:
                raise PullError(f"{code}: HTTP {response.status}")
            return response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        raise PullError(f"{code}: HTTP {exc.code} {exc.read().decode('utf-8', 'replace').strip()[:200]}")
    except urllib.error.URLError as exc:
        raise PullError(f"{code}: request failed: {exc}")


def build_locale(code: str, body: str, enus_keys: "list[tuple[str, str]]") -> "tuple[str, str]":
    """Return (rendered file text, one-line status)."""
    exported = parse_export(body)
    kept: list[tuple[str, str, str]] = []
    skipped = 0
    for quote, raw_key in enus_keys:
        logical = lua_unescape(raw_key)
        entry = exported.get(logical)
        if entry is None:
            continue
        value_quote, raw_value = entry
        if lua_unescape(raw_value) == logical:
            continue  # untranslated -- the enUS fallback covers it
        if placeholders(lua_unescape(raw_value)) != placeholders(logical):
            print(f"  {code}: skip {logical!r}: placeholder mismatch -> {lua_unescape(raw_value)!r}",
                  file=sys.stderr)
            skipped += 1
            continue
        kept.append((quote, raw_key, f"{value_quote}{raw_value}{value_quote}"))
    note = f" ({skipped} skipped: placeholder mismatch)" if skipped else ""
    status = f"{code}: {len(kept)}/{len(enus_keys)} phrases{note}"
    return render_locale(code, kept), status


def resolve_project_id() -> str:
    return os.environ.get("CF_PROJECT_ID", "").strip() or DEFAULT_PROJECT_ID


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locales", help="comma-separated subset (default: all non-enUS ship locales)")
    parser.add_argument("--dry-run", action="store_true", help="print the URLs; no network, no writes")
    args = parser.parse_args()

    locales = [c.strip() for c in args.locales.split(",")] if args.locales else DEFAULT_LOCALES
    unknown = [c for c in locales if c not in DEFAULT_LOCALES]
    if unknown:
        print(f"unknown locale(s): {', '.join(unknown)}", file=sys.stderr)
        return 1

    project_id = resolve_project_id()
    endpoint = CF_EXPORT_URL.format(project_id=project_id)

    if args.dry_run:
        for code in locales:
            print(f"{code}: GET {endpoint}?lang={code}&{CF_EXPORT_PARAMS}")
        return 0

    if project_id == PLACEHOLDER_PROJECT_ID:
        print(
            "CF_PROJECT_ID is unset and no CurseForge project exists yet -- set "
            "CF_PROJECT_ID / create the CF project first (see plans/010).",
            file=sys.stderr,
        )
        return 1

    api_key = os.environ.get("CF_API_KEY")
    if not api_key:
        print("CF_API_KEY is not set (required unless --dry-run)", file=sys.stderr)
        return 1

    try:
        enus_keys = read_enus_keys(ENUS_PATH)
        rendered: dict[str, str] = {}
        statuses: list[str] = []
        for code in locales:
            body = fetch_export(endpoint, code, api_key)
            text, status = build_locale(code, body, enus_keys)
            rendered[code] = text
            statuses.append(status)
    except PullError as exc:
        print(f"SANITY: {exc}", file=sys.stderr)
        return 1

    for code, text in rendered.items():
        path = os.path.join(LOCALES_DIR, f"{code}.lua")
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    for status in statuses:
        print(status)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("".join(f"- {s}\n" for s in statuses))
    return 0


if __name__ == "__main__":
    sys.exit(main())
