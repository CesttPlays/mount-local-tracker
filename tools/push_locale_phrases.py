#!/usr/bin/env python3
"""Push the English phrase set from Locales/enUS.lua to CurseForge Localization.

CurseForge Localization is the translator-facing hub for this addon: translators
work against the English phrasebook there, and tools/pull_locale_translations.py
brings the approved translations back into the committed Locales/<code>.lua files.
Mount_Tracker_Local_Zones/Locales/enUS.lua is the source of truth -- this script
only ever uploads it, it never writes anything locally.

The import endpoint is multipart/form-data with two fields: `metadata` (a JSON
blob naming the base language and the missing-phrase policy) and `localizations`
(the `L["key"] = "value"` block, English text on both sides). Reference:
BigWigsMods/packager `release.sh` (the export call) and
p3lim/curseforge-localizations `update.py` (the import call).

NOTE: the mount addon has no CurseForge project yet -- there is no
`## X-Curse-Project-ID` line, no `CF_API_KEY` secret and no `deploy` environment
(see plans/010-localization-curseforge-automation.md). Until the project exists a
non-`--dry-run` run fails closed; `--dry-run` works offline today.

Usage:
  python tools/push_locale_phrases.py [--dry-run] [--prune]

  --dry-run   print the phrase count and a preview of the request; no network.
  --prune     let CurseForge delete phrases that are not in this upload
              (missing-phrase-handling = DeletePhrase). Default: add/update only.

Env:
  CF_API_KEY     CurseForge API token (required unless --dry-run)
  CF_PROJECT_ID  CurseForge project id. No default -- the project does not exist
                 yet, so this is REPLACE_ME until it is created.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

# --- CurseForge Localization API ------------------------------------------------
# One edit point if CurseForge changes the endpoint, header or field names.
CF_API_BASE = "https://legacy.curseforge.com/api/projects/{project_id}/localization"
CF_IMPORT_URL = CF_API_BASE + "/import"
CF_AUTH_HEADER = "X-Api-Token"
CF_BASE_LANGUAGE = "enUS"
# metadata["missing-phrase-handling"]: DoNothing keeps every existing phrase,
# DeletePhrase removes any phrase not present in this upload. (The CF docs also
# list DeleteIfNoTranslations / DeleteIfTranslationsOnlyExistForSelectedLanguage.)
CF_MISSING_KEEP = "DoNothing"
CF_MISSING_PRUNE = "DeletePhrase"
# The mount addon has no CurseForge project yet -- see plans/010. Set the real id
# here (or pass CF_PROJECT_ID) once the project is created.
PLACEHOLDER_PROJECT_ID = "REPLACE_ME"
DEFAULT_PROJECT_ID = PLACEHOLDER_PROJECT_ID

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENUS_PATH = os.path.join(
    ROOT, "Mount_Tracker_Local_Zones", "Locales", "enUS.lua"
)

# L["key"] = true   /   L['key'] = "literal"   -- handles escaped quotes in the key.
KEY_LINE_RE = re.compile(
    r"""^\s*L\[\s*(?P<q>["'])(?P<key>(?:\\.|(?!(?P=q)).)*)(?P=q)\s*\]\s*=\s*(?P<rhs>.+?)\s*$"""
)
# %1$s positional, or plain %s / %d / %.1f / %x / %% etc. Mirrors tests/test_locales.py.
PLACEHOLDER_RE = re.compile(r"%\d+\$s|%[-+ #0-9.]*[sdfxXqg%]")


def lua_unescape(raw: str) -> str:
    """The logical string behind a Lua single/double-quoted literal body."""
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t", "r": "\r"}.get(m.group(1), m.group(1)), raw)


class PhraseError(Exception):
    """A sanity failure -- the script writes nothing and exits non-zero."""


def read_phrases(path: str) -> list[tuple[str, str]]:
    """Return [(quote, raw_key), ...] in source order. Raises PhraseError on any
    malformed / duplicate / empty key or a broken `%` placeholder."""
    phrases: list[tuple[str, str]] = []
    seen: dict[str, int] = {}
    with open(path, encoding="utf-8") as handle:
        for lineno, line in enumerate(handle, 1):
            stripped = line.strip()
            if not stripped.startswith("L["):
                continue
            match = KEY_LINE_RE.match(stripped)
            if not match:
                raise PhraseError(f"{path}:{lineno}: cannot parse phrase line: {stripped!r}")
            quote, raw_key = match.group("q"), match.group("key")
            logical = lua_unescape(raw_key)
            if not logical.strip():
                raise PhraseError(f"{path}:{lineno}: empty phrase key")
            if logical in seen:
                raise PhraseError(
                    f"{path}:{lineno}: duplicate phrase key (also line {seen[logical]}): {logical!r}"
                )
            leftover = PLACEHOLDER_RE.sub("", logical)
            if "%" in leftover:
                raise PhraseError(f"{path}:{lineno}: malformed % placeholder in {logical!r}")
            seen[logical] = lineno
            phrases.append((quote, raw_key))
    if not phrases:
        raise PhraseError(f"{path}: no L[...] phrases found")
    return phrases


def localizations_blob(phrases: list[tuple[str, str]]) -> str:
    """The `L["key"] = "key"` block CurseForge imports (English on both sides)."""
    return "\n".join(f'L[{q}{key}{q}] = {q}{key}{q}' for q, key in phrases)


def multipart_body(fields: dict[str, str]) -> tuple[bytes, str]:
    """Hand-rolled multipart/form-data (stdlib has no helper)."""
    boundary = uuid.uuid4().hex
    chunks = []
    for name, value in fields.items():
        chunks.append(
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{name}"\r\n\r\n'
            f"{value}\r\n"
        )
    chunks.append(f"--{boundary}--\r\n")
    return "".join(chunks).encode("utf-8"), f"multipart/form-data; boundary={boundary}"


def resolve_project_id() -> str:
    return os.environ.get("CF_PROJECT_ID", "").strip() or DEFAULT_PROJECT_ID


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="print the request; no network")
    parser.add_argument("--prune", action="store_true", help="let CF delete phrases missing from this upload")
    args = parser.parse_args()

    try:
        phrases = read_phrases(ENUS_PATH)
    except PhraseError as exc:
        print(f"SANITY: {exc}", file=sys.stderr)
        return 1

    project_id = resolve_project_id()
    if not args.dry_run and project_id == PLACEHOLDER_PROJECT_ID:
        print(
            "CF_PROJECT_ID is unset and no CurseForge project exists yet -- set "
            "CF_PROJECT_ID / create the CF project first (see plans/010).",
            file=sys.stderr,
        )
        return 1

    endpoint = CF_IMPORT_URL.format(project_id=project_id)
    blob = localizations_blob(phrases)
    metadata = {
        "language": CF_BASE_LANGUAGE,
        "missing-phrase-handling": CF_MISSING_PRUNE if args.prune else CF_MISSING_KEEP,
    }

    print(f"{len(phrases)} phrases from {os.path.relpath(ENUS_PATH, ROOT)}")
    print(f"POST {endpoint}")
    print(f"metadata: {json.dumps(metadata)}")

    if args.dry_run:
        preview = blob.splitlines()[:10]
        print("localizations (first 10 lines):")
        for line in preview:
            print(f"  {line}")
        if len(phrases) > 10:
            print(f"  ... {len(phrases) - 10} more")
        return 0

    api_key = os.environ.get("CF_API_KEY")
    if not api_key:
        print("CF_API_KEY is not set (required unless --dry-run)", file=sys.stderr)
        return 1

    body, content_type = multipart_body({
        "metadata": json.dumps(metadata),
        "localizations": blob,
    })
    request = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={CF_AUTH_HEADER: api_key, "Content-Type": content_type},
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            status, text = response.status, response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        status, text = exc.code, exc.read().decode("utf-8", "replace")
    except urllib.error.URLError as exc:
        print(f"request failed: {exc}", file=sys.stderr)
        return 1

    print(f"HTTP {status}")
    print(text.strip())
    return 0 if 200 <= status < 300 else 1


if __name__ == "__main__":
    sys.exit(main())
