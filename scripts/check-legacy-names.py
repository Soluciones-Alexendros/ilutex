#!/usr/bin/env python3
"""Impide que vuelvan los nombres anteriores al renombrado del producto.

El producto se llama `ilutex` desde 3.0.0. Quedan menciones **legítimas** a
`keybackcon`/`kbd-rgb`: lectura del estado y pidfiles heredados, binarios
antiguos reconocidos, `conflicts`/`replaces` de los paquetes y el registro
histórico (CHANGELOG, ADR). Todo lo demás es un residuo que este script
rechaza: variables de entorno, placeholders de plantilla, nombres de clase,
rutas de empaquetado y números de versión mentirosos.

Uso: scripts/check-legacy-names.py [--verbose]
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# Patrones que NUNCA son legítimos (residuos del renombrado).
PROHIBIDOS: list[tuple[str, str]] = [
    (r"KEYBACKCON_", "variable de entorno con el nombre anterior (usa ILUTEX_*)"),
    (r"__KEYBACKCON", "placeholder de plantilla con el nombre anterior (usa __ILUTEX_*)"),
    (r"\bKeybackcon\w*", "nombre de clase/cliente con el nombre anterior (usa Ilutex*)"),
    (r"bin/keybackcon", "ruta de binario anterior (usa bin/ilutex)"),
    (r"70-keybackcon", "regla udev anterior (usa 70-ilutex)"),
    (r"po/keybackcon\.pot", "catálogo anterior (usa po/ilutex.pot)"),
    (r"keybackcon\.(service|rules|conf|desktop)", "artefacto de empaquetado anterior"),
    (r"keybackcon-gui", "lanzador anterior (usa ilutex-gui)"),
    (r"org\.iniciativas\.", "App ID anterior (usa org.alexendros.ilutex)"),
]

# Ficheros donde estos patrones aparecen a propósito al documentar el historial.
EXENTOS = {
    "CHANGELOG.md",
    "docs/architecture/decisions/DECISIONS.md",
    "scripts/check-legacy-names.py",
    "scripts/check-npm-platforms.py",
}

# Menciones heredadas permitidas (migración), verificadas para que sigan
# existiendo: si alguien las borra, la migración se rompe en silencio.
MIGRACION = [
    ("src/state.rs", "keybackcon/state"),
    ("src/animation.rs", "keybackcon/animation.pid"),
    ("gui/client.py", "keybackcon/state"),
    ("scripts/install-cli.sh", "keybackcon/state"),
]

MARCA_LEGADO = "legado:"

EXTENSIONES = {
    ".rs", ".py", ".sh", ".js", ".toml", ".yml", ".yaml", ".md", ".txt",
    ".json", ".po", ".pot", ".service", ".conf", ".rules", ".desktop", ".xml",
    "PKGBUILD", "Makefile",
}


def ficheros_versionados() -> list[Path]:
    salida = subprocess.run(
        ["git", "ls-files"], cwd=RAIZ, capture_output=True, text=True, check=True
    ).stdout
    return [RAIZ / linea for linea in salida.splitlines() if linea]


def es_relevante(ruta: Path) -> bool:
    return ruta.suffix in EXTENSIONES or ruta.name in EXTENSIONES


def main() -> int:
    verbose = "--verbose" in sys.argv
    errores: list[str] = []
    revisados = 0

    for ruta in ficheros_versionados():
        if not ruta.is_file() or not es_relevante(ruta):
            continue
        relativa = ruta.relative_to(RAIZ).as_posix()
        if relativa in EXENTOS:
            continue
        revisados += 1
        texto = ruta.read_text(encoding="utf-8", errors="ignore")
        for numero, linea in enumerate(texto.splitlines(), start=1):
            if MARCA_LEGADO in linea:
                continue
            for patron, motivo in PROHIBIDOS:
                if re.search(patron, linea):
                    errores.append(f"{relativa}:{numero}: {motivo}\n    {linea.strip()}")

    for relativa, fragmento in MIGRACION:
        ruta = RAIZ / relativa
        if not ruta.is_file() or fragmento not in ruta.read_text(encoding="utf-8", errors="ignore"):
            errores.append(f"{relativa}: falta la lectura heredada '{fragmento}'")

    if errores:
        for e in errores:
            print(f"  FALLO: {e}", file=sys.stderr)
        return 1
    if verbose:
        print(f"check-legacy-names: {revisados} ficheros revisados")
    print("check-legacy-names: OK (sin residuos del nombre anterior; migración intacta)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
