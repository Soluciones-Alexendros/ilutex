# Avisos de terceros (mesa de luz)

ilutex (CLI y GUI) se distribuye bajo la licencia MIT del repositorio. La
mesa de luz GTK4 enlaza en tiempo de ejecución con bibliotecas del sistema
cuya licencia es LGPL (u opciones duales). Este archivo documenta esa
cadena; no sustituye los textos de licencia de cada proyecto.

Los pins de [`gui/requirements.txt`](gui/requirements.txt) describen las
versiones de referencia de los bindings Python. En producción se usan los
paquetes de la distro (`python3-gi`, `python3-cairo`, GIR de GTK4/libadwaita).
[`scripts/check-gui-imports.py`](scripts/check-gui-imports.py) sigue
prohibiendo imports pip de terceros en `gui/*.py`.

## Cadena LGPL (GUI)

| Componente | Rol en ilutex | Licencia (resumen) | Origen |
| ---------- | ------------- | ------------------ | ------ |
| GTK 4 | Toolkit de la ventana | LGPL-2.1-or-later | [gtk.org](https://www.gtk.org/) / paquete distro |
| libadwaita | Estilo Adwaita / `Adw.Application` | LGPL-2.1-or-later | [GNOME libadwaita](https://gitlab.gnome.org/GNOME/libadwaita) / paquete distro |
| PyGObject (`gi`) | Bindings Python vía GObject Introspection | LGPL-2.1-or-later | [pygobject.gnome.org](https://pygobject.gnome.org) — pin `3.58.1` en `gui/requirements.txt` |
| pycairo (`cairo`) | Bindings Python de cairo (p. ej. icono de bandeja) | LGPL-2.1-only OR MPL-1.1 | [pycairo](https://pycairo.readthedocs.io) — pin `1.29.2` en `gui/requirements.txt` |
| cairo (biblioteca C) | Dependencia nativa de pycairo | LGPL-2.1-or-later (típico en distros) | paquete distro (`libcairo`) |

El inventario CSV regenerable en CI está en [`gui/licenses.csv`](gui/licenses.csv)
(`pip-licenses` sobre los pins de `gui/requirements.txt`).

## Obligaciones relevantes (resumen)

Al distribuir binarios o paquetes que enlacen con estas bibliotecas LGPL:

1. Conservar avisos de copyright y licencia de cada componente.
2. Permitir el relink / la sustitución de la biblioteca LGPL por una versión
   modificada (enlace dinámico al so de la distro lo cubre en el empaquetado
   habitual).
3. No imponer restricciones adicionales que impidan ejercer los derechos LGPL
   sobre esas bibliotecas.

El código propio de ilutex no se reclasifica como LGPL por este enlace
dinámico; la MIT del CLI/GUI se mantiene. Quien redistribuya un derivado
debe seguir los términos de cada componente de la cadena.

## Verificación en CI

El job `quality` ejecuta `pip-audit -r gui/requirements.txt` y
`pip-licenses` (CSV subido como artefacto y escrito en `gui/licenses.csv`).
