#!/usr/bin/env python3
"""Unittests de ``top_level_imports`` en check-gui-imports."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

_SCRIPTS = Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location(
    "check_gui_imports",
    _SCRIPTS / "check-gui-imports.py",
)
assert _SPEC is not None and _SPEC.loader is not None
_MOD = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MOD)

SYSTEM_BINDINGS = _MOD.SYSTEM_BINDINGS
stdlib_names = _MOD.stdlib_names
top_level_imports = _MOD.top_level_imports


class TopLevelImportsTests(unittest.TestCase):
    def test_acepta_stdlib_y_gi(self) -> None:
        src = "import os\nimport gi\nfrom pathlib import Path\n"
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".py", encoding="utf-8", delete=False
        ) as tmp:
            tmp.write(src)
            path = Path(tmp.name)
        try:
            found = top_level_imports(path)
        finally:
            path.unlink(missing_ok=True)
        self.assertEqual(found, {"os", "gi", "pathlib"})
        allowed = stdlib_names() | SYSTEM_BINDINGS
        self.assertTrue(found <= allowed)

    def test_detecta_import_prohibido(self) -> None:
        src = "import requests\n"
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".py", encoding="utf-8", delete=False
        ) as tmp:
            tmp.write(src)
            path = Path(tmp.name)
        try:
            found = top_level_imports(path)
        finally:
            path.unlink(missing_ok=True)
        self.assertEqual(found, {"requests"})
        allowed = stdlib_names() | SYSTEM_BINDINGS
        self.assertFalse(found <= allowed)


if __name__ == "__main__":
    unittest.main()
