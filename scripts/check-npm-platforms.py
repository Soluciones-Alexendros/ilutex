#!/usr/bin/env python3
"""Verifica los paquetes de plataforma de `npm/` antes de publicarlos.

Falla si un `platforms/*/index.js` exporta una ruta que no coincide con el
binario declarado en su `package.json` (`files`) o si el nombre del paquete
no coincide con la carpeta. Evita republicar un lanzador que apunte a un
fichero inexistente (regresión detectada en `v3.0.1`: el índice exportaba
`bin/keybackcon`, nombre anterior al renombrado del producto).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

NPM_DIR = Path(__file__).resolve().parent.parent / "npm"
PLATFORMS = NPM_DIR / "platforms"


def fallos() -> list[str]:
    errores: list[str] = []
    if not PLATFORMS.is_dir():
        return [f"no existe {PLATFORMS}"]

    for carpeta in sorted(p for p in PLATFORMS.iterdir() if p.is_dir()):
        pkg_json = carpeta / "package.json"
        index_js = carpeta / "index.js"
        if not pkg_json.is_file() or not index_js.is_file():
            errores.append(f"{carpeta.name}: falta package.json o index.js")
            continue

        pkg = json.loads(pkg_json.read_text(encoding="utf-8"))
        esperado = f"ilutex-linux-{carpeta.name.split('-')[-1]}"
        if pkg.get("name") != esperado:
            errores.append(
                f"{carpeta.name}: package.json dice '{pkg.get('name')}', se esperaba '{esperado}'"
            )

        # `files` debe declarar exactamente un binario bajo bin/
        binarios = [f for f in pkg.get("files", []) if f.startswith("bin/")]
        if len(binarios) != 1:
            errores.append(
                f"{carpeta.name}: 'files' debe declarar un único binario bin/*, hay {binarios}"
            )
            continue
        esperado_bin = binarios[0]

        codigo = index_js.read_text(encoding="utf-8")
        rutas = re.findall(r"join\([^)]*\)", codigo)
        if not rutas:
            errores.append(f"{carpeta.name}: index.js no construye una ruta con join()")
            continue
        partes = re.findall(r"'([^']+)'", rutas[-1])
        exportado = "/".join(partes[-2:]) if len(partes) >= 2 else "/".join(partes)
        if exportado != esperado_bin:
            errores.append(
                f"{carpeta.name}: index.js exporta '{exportado}', "
                f"pero 'files' declara '{esperado_bin}'"
            )
        if re.search(r"keybackcon|kbd-rgb", codigo):
            errores.append(
                f"{carpeta.name}: index.js menciona un nombre anterior al renombrado"
            )
    return errores


def main() -> int:
    errores = fallos()
    if errores:
        for e in errores:
            print(f"  FALLO: {e}", file=sys.stderr)
        return 1
    print("check-npm-platforms: OK (índices de plataforma coherentes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
