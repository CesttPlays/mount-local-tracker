#!/usr/bin/env python3
"""Unit tests for tools/push_locale_phrases.py and tools/pull_locale_translations.py.

Pure-function coverage with hand-built fixtures -- no network, no CurseForge. They
pin the parsing and validation a bad push/pull would silently break: the enUS
phrase scan (dupes, blank keys, malformed `%`), the CF export parser (both body
shapes + error pages), the untranslated / placeholder-mismatch drops, the
generated Locales/<code>.lua shape, and the REPLACE_ME project-id guard (the
mount addon has no CurseForge project yet -- see plans/010).

Run:  python -m unittest discover -s tests -p test_locale_tools.py
"""

import contextlib
import io
import os
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import push_locale_phrases as push  # noqa: E402
import pull_locale_translations as pull  # noqa: E402

ENUS = os.path.join(ROOT, "Mount_Tracker_Local_Zones", "Locales", "enUS.lua")


def write(tmp, name, text):
    path = os.path.join(tmp, name)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    return path


class TestReadPhrases(unittest.TestCase):
    def test_reads_the_real_enus_file(self):
        phrases = push.read_phrases(ENUS)
        with open(ENUS, encoding="utf-8") as fh:
            line_count = sum(1 for ln in fh if ln.strip().startswith("L["))
        self.assertEqual(len(phrases), line_count)
        self.assertGreater(len(phrases), 40)

    def test_handles_both_quote_styles_and_escaped_quotes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "enUS.lua",
                         'L["plain"] = true\n'
                         'L[\'Requires "%s" first\'] = true\n'
                         "L['it\\'s fine'] = true\n")
            phrases = push.read_phrases(path)
        self.assertEqual(
            push.localizations_blob(phrases),
            'L["plain"] = "plain"\n'
            'L[\'Requires "%s" first\'] = \'Requires "%s" first\'\n'
            "L['it\\'s fine'] = 'it\\'s fine'",
        )

    def test_duplicate_key_across_quote_styles_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "enUS.lua", 'L["dup"] = true\nL[\'dup\'] = true\n')
            with self.assertRaises(push.PhraseError):
                push.read_phrases(path)

    def test_blank_key_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "enUS.lua", 'L["  "] = true\n')
            with self.assertRaises(push.PhraseError):
                push.read_phrases(path)

    def test_malformed_placeholder_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "enUS.lua", 'L["50%% sure about %z"] = true\n')
            with self.assertRaises(push.PhraseError):
                push.read_phrases(path)

    def test_well_formed_placeholders_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write(tmp, "enUS.lua",
                         'L["%d of %s (%.1f%%) %1$s"] = true\n')
            self.assertEqual(len(push.read_phrases(path)), 1)


class TestMultipart(unittest.TestCase):
    def test_body_has_both_fields_and_a_matching_boundary(self):
        body, content_type = push.multipart_body({"metadata": "{}", "localizations": "L[\"a\"] = \"a\""})
        boundary = content_type.split("boundary=")[1]
        text = body.decode("utf-8")
        self.assertIn(f'--{boundary}\r\n', text)
        self.assertIn('name="metadata"', text)
        self.assertIn('name="localizations"', text)
        self.assertTrue(text.endswith(f"--{boundary}--\r\n"))


class TestProjectIdGuard(unittest.TestCase):
    """No CurseForge project exists yet -- a non-dry-run must fail closed."""

    def setUp(self):
        self._saved = os.environ.pop("CF_PROJECT_ID", None)

    def tearDown(self):
        if self._saved is not None:
            os.environ["CF_PROJECT_ID"] = self._saved
        else:
            os.environ.pop("CF_PROJECT_ID", None)

    def test_default_is_the_placeholder(self):
        self.assertEqual(push.DEFAULT_PROJECT_ID, "REPLACE_ME")
        self.assertEqual(pull.DEFAULT_PROJECT_ID, "REPLACE_ME")

    def test_empty_env_resolves_to_the_placeholder(self):
        os.environ["CF_PROJECT_ID"] = "   "
        self.assertEqual(push.resolve_project_id(), "REPLACE_ME")
        self.assertEqual(pull.resolve_project_id(), "REPLACE_ME")

    def test_real_env_overrides_the_placeholder(self):
        os.environ["CF_PROJECT_ID"] = "123456"
        self.assertEqual(push.resolve_project_id(), "123456")
        self.assertEqual(pull.resolve_project_id(), "123456")

    def _run(self, module, *args):
        argv = sys.argv
        sys.argv = [f"{module.__name__}.py", *args]
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                return module.main()
        finally:
            sys.argv = argv

    def test_push_exits_1_without_a_project_id_and_sends_nothing(self):
        self.assertEqual(self._run(push), 1)

    def test_pull_exits_1_without_a_project_id(self):
        self.assertEqual(self._run(pull), 1)

    def test_pull_dry_run_still_works_with_the_placeholder(self):
        self.assertEqual(self._run(pull, "--dry-run"), 0)


class TestParseExport(unittest.TestCase):
    def test_parses_bare_additions_body(self):
        body = 'L["Other"] = "Andere"\nL["done"] = "fertig"\n'
        self.assertEqual(
            pull.parse_export(body),
            {"Other": ('"', "Andere"), "done": ('"', "fertig")},
        )

    def test_parses_table_constructor_body(self):
        body = 'L = {\n\t["Other"] = "Andere",\n\t["done"] = "fertig",\n}\n'
        self.assertEqual(set(pull.parse_export(body)), {"Other", "done"})

    def test_empty_or_wrapper_only_body_is_no_translations(self):
        self.assertEqual(pull.parse_export(""), {})
        self.assertEqual(pull.parse_export("L = L or {}\n"), {})

    def test_html_error_page_raises(self):
        with self.assertRaises(pull.PullError):
            pull.parse_export("<!DOCTYPE html><html><body>403</body></html>")

    def test_json_error_body_raises(self):
        with self.assertRaises(pull.PullError):
            pull.parse_export('{"errorMessage":"bad token"}')

    def test_meaningful_junk_with_no_pairs_raises(self):
        with self.assertRaises(pull.PullError):
            pull.parse_export("this is not lua at all\nand neither is this\n")


class TestBuildLocale(unittest.TestCase):
    ENUS_KEYS = [('"', "Other"), ('"', "Mounts: %s"), ('"', "done")]

    def test_keeps_good_translations_in_enus_order(self):
        body = 'L["done"] = "fertig"\nL["Other"] = "Andere"\n'
        text, status = pull.build_locale("deDE", body, self.ENUS_KEYS)
        self.assertEqual(status, "deDE: 2/3 phrases")
        self.assertLess(text.index('L["Other"]'), text.index('L["done"]'))

    def test_drops_untranslated_lines_where_value_equals_key(self):
        body = 'L["Other"] = "Other"\nL["done"] = "fertig"\n'
        text, status = pull.build_locale("deDE", body, self.ENUS_KEYS)
        self.assertNotIn('L["Other"]', text)
        self.assertEqual(status, "deDE: 1/3 phrases")

    def test_skips_and_counts_placeholder_mismatches_without_failing(self):
        body = 'L["Mounts: %s"] = "Reittiere: %d"\nL["Other"] = "Andere"\n'
        text, status = pull.build_locale("deDE", body, self.ENUS_KEYS)
        self.assertNotIn("Mounts:", text)
        self.assertEqual(status, "deDE: 1/3 phrases (1 skipped: placeholder mismatch)")

    def test_ignores_keys_that_are_not_in_enus(self):
        body = 'L["Not A Real Key"] = "x"\n'
        text, status = pull.build_locale("deDE", body, self.ENUS_KEYS)
        self.assertEqual(status, "deDE: 0/3 phrases")

    def test_zero_survivors_render_the_bare_stub(self):
        text, _ = pull.build_locale("frFR", "", self.ENUS_KEYS)
        self.assertEqual(
            text,
            "-- GENERATED from CurseForge Localization by tools/pull_locale_translations.py.\n"
            "-- Manual edits are overwritten. Untranslated keys fall back to Locales/enUS.lua.\n"
            "\n"
            "local addonName = ...\n"
            'local L = LibStub("AceLocale-3.0"):NewLocale(addonName, "frFR")\n'
            "if not L then return end\n",
        )

    def test_stub_matches_the_committed_plan_008_locale_files(self):
        """A locale file with no translations yet must be byte-identical (newline-
        normalised) to the plan-008 stub, so `git` sees no churn."""
        locales_dir = os.path.join(ROOT, "Mount_Tracker_Local_Zones", "Locales")
        for name in os.listdir(locales_dir):
            code = os.path.splitext(name)[0]
            if code == "enUS" or not name.endswith(".lua"):
                continue
            with open(os.path.join(locales_dir, name), encoding="utf-8") as fh:
                on_disk = fh.read()
            if "L[" in on_disk:
                continue  # already has translations -- not a stub anymore
            stub, _ = pull.build_locale(code, "", self.ENUS_KEYS)
            self.assertEqual(on_disk.replace("\r\n", "\n"), stub, f"{name} drifted from the generated stub")


class TestRenderedLocaleParsesAsLua(unittest.TestCase):
    def test_output_is_a_valid_lua_chunk_with_escaped_quotes_in_a_value(self):
        try:
            from lupa.luajit21 import LuaRuntime
        except ImportError:
            try:
                from lupa import LuaRuntime
            except ImportError:
                self.skipTest("lupa not installed")
        body = 'L[\'Requires "%s" first\'] = \'Ben\\u00f6tigt zuerst "%s"\'\n'.encode().decode("unicode_escape")
        text, status = pull.build_locale("deDE", body, [("'", 'Requires "%s" first')])
        self.assertEqual(status, "deDE: 1/1 phrases")
        lua = LuaRuntime(unpack_returned_tuples=True)
        loader = lua.eval("function(src) return assert(load and load(src) or loadstring(src)) end")
        loader(text)  # raises on a syntax error


if __name__ == "__main__":
    unittest.main()
