#!/usr/bin/env python3
"""Comprueba que gui/*.py no importe paquetes pip de terceros.

El glob es solo ``gui/*.py`` (módulos de primer nivel). No incluye
``gui/tests/`` ni subdirectorios.

Permitidos:
- biblioteca estándar de Python
- bindings de sistema del stack GTK: ``gi`` (PyGObject) y ``cairo``
  (python3-cairo; aparece en Recommends del .deb)
- módulos del propio paquete ``gui`` (p. ej. ``gui.constants``, ``backend``)

Uso: python3 scripts/check-gui-imports.py
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
GUI = RAIZ / "gui"

# Bindings de distro (no pip). cairo dibuja el icono de bandeja.
SYSTEM_BINDINGS = frozenset({"gi", "cairo"})


def stdlib_names() -> frozenset[str]:
    names = getattr(sys, "stdlib_module_names", None)
    if names is not None:
        return frozenset(names)
    # Fallback mínimo si el intérprete no expone el inventario.
    return frozenset(
        {
            "__future__",
            "abc",
            "ast",
            "atexit",
            "collections",
            "contextlib",
            "copy",
            "dataclasses",
            "datetime",
            "enum",
            "functools",
            "gettext",
            "hashlib",
            "importlib",
            "io",
            "json",
            "locale",
            "logging",
            "math",
            "os",
            "pathlib",
            "queue",
            "random",
            "re",
            "shutil",
            "signal",
            "string",
            "struct",
            "subprocess",
            "sys",
            "tempfile",
            "threading",
            "time",
            "typing",
            "unicodedata",
            "unittest",
            "warnings",
            "xml",
            "zlib",
        }
    )


def local_gui_modules() -> frozenset[str]:
    mods = {"gui"}
    for path in GUI.glob("*.py"):
        if path.name == "__init__.py":
            continue
        mods.add(path.stem)
    return frozenset(mods)


def top_level_imports(path: Path) -> set[str]:
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    found: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                found.add(alias.name.split(".", 1)[0])
        elif isinstance(node, ast.ImportFrom):
            if node.level and node.level > 0:
                # from . import X / from .foo import Y → paquete local
                continue
            if node.module:
                found.add(node.module.split(".", 1)[0])
    return found


def main() -> int:
    allowed = stdlib_names() | SYSTEM_BINDINGS | local_gui_modules()
    errores: list[str] = []

    for path in sorted(GUI.glob("*.py")):
        for mod in sorted(top_level_imports(path)):
            if mod not in allowed:
                errores.append(f"{path.relative_to(RAIZ)}: import prohibido {mod!r}")

    if errores:
        print("Imports de GUI fuera de stdlib/gi/cairo/paquete local:", file=sys.stderr)
        for line in errores:
            print(f"  {line}", file=sys.stderr)
        return 1

    print("OK: gui/*.py solo importa stdlib, gi/cairo o el paquete local")
    return 0


if __name__ == "__main__":
    sys.exit(main())
