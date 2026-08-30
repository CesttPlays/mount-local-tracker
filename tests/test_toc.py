#!/usr/bin/env python3
"""TOC / packaging consistency checks for the addon.

Catches the mistakes a headless Lua load can't: a file listed in the .toc that
isn't on disk, a source file nobody loads, a malformed `## Interface` line, or a
SavedVariables name that drifted out of sync with .luacheckrc.

Run:  python -m unittest discover -s tests -p test_toc.py
"""

import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "Mount_Tracker_Local_Zones")
TOC = os.path.join(ADDON, "Mount_Tracker_Local_Zones.toc")


def read_toc_lines():
    with open(TOC, encoding="utf-8") as fh:
        return [ln.rstrip("\n") for ln in fh]


def toc_directives():
    out = {}
    for line in read_toc_lines():
        match = re.match(r"^##\s*([^:]+):\s*(.*)$", line.strip())
        if match:
            out[match.group(1).strip()] = match.group(2).strip()
    return out


def toc_referenced_files():
    # `#@do-not-package@` / `#@end-do-not-package@` are packager pragmas, not
    # file references, but the file lines between them (e.g. Mechanic.lua) are
    # real TOC entries the client loads -- they don't start with '#'.
    files = []
    for line in read_toc_lines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        files.append(stripped.replace("\\", "/"))
    return files


class TestToc(unittest.TestCase):
    def test_every_referenced_file_exists(self):
        for rel in toc_referenced_files():
            # LibStub / CallbackHandler-1.0 / LibDBIcon-1.0 are vendored and
            # committed; LibDataBroker-1.1 + HereBeDragons are fetched by the
            # BigWigs packager at build time (see .pkgmeta) and so may be absent
            # from a fresh checkout. Skip the lot -- load order is what matters.
            if rel.startswith("Libs/"):
                continue
            self.assertTrue(
                os.path.isfile(os.path.join(ADDON, rel)),
                f"{rel} is listed in the .toc but missing on disk",
            )

    def test_interface_version_is_five_or_six_digits(self):
        directives = toc_directives()
        self.assertIn("Interface", directives)
        self.assertRegex(directives["Interface"], r"^\d{5,6}$")

    def test_savedvariables_matches_luacheckrc(self):
        saved = toc_directives().get("SavedVariables", "")
        self.assertTrue(saved, "## SavedVariables missing from the .toc")
        with open(os.path.join(ROOT, ".luacheckrc"), encoding="utf-8") as fh:
            luacheckrc = fh.read()
        for name in (n.strip() for n in saved.split(",")):
            self.assertIn(
                name, luacheckrc,
                f"SavedVariables '{name}' is not declared as a global in .luacheckrc",
            )

    def test_no_orphan_lua_or_xml_source_files(self):
        referenced = set(toc_referenced_files())
        for entry in sorted(os.listdir(ADDON)):
            if entry.startswith("."):
                continue
            if entry.endswith((".lua", ".xml")) and entry != os.path.basename(TOC):
                self.assertIn(
                    entry, referenced,
                    f"{entry} sits in the addon folder but no .toc line loads it",
                )

    def test_core_load_order_puts_data_before_the_model(self):
        files = [f for f in toc_referenced_files() if f.endswith((".lua", ".xml"))]
        order = {name: i for i, name in enumerate(files)}
        # MountModel reads addon.MountData / addon.MountOverrides / addon.Obtainability
        # at call time, but Core defines the SafeApiCall helpers everything caches
        # at load, so Core must lead.
        self.assertLess(order["Core.lua"], order["MountData.lua"])
        self.assertLess(order["MountData.lua"], order["MountModel.lua"])
        self.assertLess(order["Overrides.lua"], order["MountModel.lua"])
        self.assertLess(order["Obtainability.lua"], order["MountModel.lua"])
        self.assertLess(order["MountModel.lua"], order["Window.lua"])
        # ListView.xml declares the frame templates ListView.lua fills in.
        self.assertLess(order["ListView.xml"], order["ListView.lua"])


if __name__ == "__main__":
    unittest.main()
