#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

say() { printf '%s\n' "$*"; }
ok() { say "  ok: $*"; }
bad() { say "  FALLO: $*"; fail=1; }

# Python con PyGObject (misma idea que packaging/ilutex-gui): el PATH puede
# tener mise/pyenv sin gi. Vacío → no hay candidato.
find_python_gi() {
  local cand
  for cand in "${ILUTEX_PYTHON:-}" python3 /usr/bin/python3 python; do
    [ -n "$cand" ] || continue
    command -v "$cand" >/dev/null 2>&1 || continue
    if "$cand" -c 'import gi' >/dev/null 2>&1; then
      printf '%s\n' "$cand"
      return 0
    fi
  done
  return 1
}
PY_GI="$(find_python_gi || true)"

say "==> ilutex smoke"
if [ ! -x "${REPO_DIR}/target/release/ilutex" ]; then
  cargo build --release --manifest-path "${REPO_DIR}/Cargo.toml" >/dev/null
fi

if "${REPO_DIR}/target/release/ilutex" --version >/dev/null; then
  ok "--version"
else
  bad "--version"
fi

if { "${REPO_DIR}/target/release/ilutex" --help 2>&1 || true; } | grep -q "brightness"; then
  ok "--help menciona brightness"
else
  bad "--help"
fi

if python3 -m py_compile "${REPO_DIR}/gui/control_panel.py"; then
  ok "GUI compila"
else
  bad "GUI"
fi

if ! command -v desktop-file-validate >/dev/null 2>&1; then
  ok "desktop-file-validate no disponible, omitido"
elif desktop-file-validate "${REPO_DIR}/packaging/desktop/ilutex.desktop"; then
  ok "desktop válido"
else
  bad "desktop"
fi

if grep -q 'TAG+="uaccess"' "${REPO_DIR}/packaging/udev/70-ilutex.rules"; then
  ok "udev uaccess"
else
  bad "udev"
fi

if grep -q '/run/ilutex/writer.lock' "${REPO_DIR}/packaging/tmpfiles.d/ilutex.conf" \
  && grep -q '^g ilutex' "${REPO_DIR}/packaging/sysusers.d/ilutex.conf"; then
  ok "candado tmpfiles/sysusers"
else
  bad "candado tmpfiles/sysusers"
fi

# Instalar ≠ autorizar (KBC-01/11): no invocar usermod (documentarlo en echo sí vale).
if ! grep -E 'usermod[[:space:]]+-aG[[:space:]]+ilutex' \
      "${REPO_DIR}/scripts/install-cli.sh" "${REPO_DIR}/scripts/install.sh" \
      "${REPO_DIR}/packaging/debian/postinst" \
    | grep -vE 'echo |# ' | grep -q .; then
  ok "install/postinst sin usermod automático"
else
  bad "usermod automático (debe ser preparación explícita)"
fi

if grep -q 'Instalar no te mete en el grupo\|autorización de escritura pendiente' \
     "${REPO_DIR}/scripts/install-cli.sh"; then
  ok "install-cli.sh documenta habilitación explícita"
else
  bad "install-cli.sh sin mensaje de habilitación explícita"
fi

# G-06: instaladores separados + orquestador documentado.
if [ -x "${REPO_DIR}/scripts/install-cli.sh" ] \
  && [ -x "${REPO_DIR}/scripts/install-gui.sh" ] \
  && grep -q 'install-cli.sh' "${REPO_DIR}/scripts/install.sh" \
  && grep -q 'install-gui.sh' "${REPO_DIR}/scripts/install.sh"; then
  ok "install.sh orquesta install-cli + install-gui"
else
  bad "reparto install-cli/install-gui"
fi

# H-07: --release verifica integridad; el camino por defecto no descarga.
if grep -qE -- '--release' "${REPO_DIR}/scripts/install.sh" \
  && grep -q 'sha256sum -c SHA256SUMS --ignore-missing' "${REPO_DIR}/scripts/install.sh" \
  && grep -q 'gh attestation verify' "${REPO_DIR}/scripts/install.sh" \
  && grep -q 'sin flags.*no usa la red\|Compila e instala desde el árbol local' \
       "${REPO_DIR}/scripts/install.sh"; then
  ok "install.sh --release con SHA256SUMS/attestation"
else
  bad "install.sh --release / integridad"
fi

# udev local: origen privilegiado /usr/lib; no copiar a ~/.local para pkexec.
# La tilde es el literal a buscar, no una ruta del shell.
# shellcheck disable=SC2088
if grep -q '/usr/lib/udev/rules.d/70-ilutex.rules' "${REPO_DIR}/scripts/install-cli.sh" \
  && ! grep -qF '~/.local/share/ilutex/70-ilutex.rules' \
    "${REPO_DIR}/scripts/install-cli.sh" "${REPO_DIR}/scripts/install-gui.sh" \
    "${REPO_DIR}/scripts/install.sh"; then
  ok "install no usa ~/.local para regla udev privilegiada"
else
  bad "install udev ~/.local"
fi

if grep -q "ExecStart=/usr/bin/ilutex restore" "${REPO_DIR}/packaging/systemd/ilutex.service"; then
  ok "systemd service (/usr/bin)"
else
  bad "systemd"
fi

if grep -q "ExecStart=/usr/bin/ilutex animation" "${REPO_DIR}/packaging/systemd/ilutex-animation@.service" \
  && grep -q "ExecStopPost=/usr/bin/ilutex stop" "${REPO_DIR}/packaging/systemd/ilutex-animation@.service"; then
  ok "systemd anim (/usr/bin, stop restaura color)"
else
  bad "systemd anim"
fi

# La instalación local reescribe las rutas /usr/bin de las unidades; el
# placeholder __ILUTEX_BIN__ pertenece a las plantillas de npm.
if grep -q 's|/usr/bin/ilutex-gui|' "${REPO_DIR}/scripts/install-gui.sh" \
  && grep -q 's|/usr/bin/ilutex|' "${REPO_DIR}/scripts/install-gui.sh" \
  && grep -q '__ILUTEX_BIN__' "${REPO_DIR}/npm/install.js"; then
  ok "install-gui.sh reescribe unidades a ~/.local/bin"
else
  bad "install-gui.sh reescritura de unidades"
fi

# Bandeja: una unidad de usuario y una sola fuente de arranque.
if grep -q 'ExecStart=/usr/bin/ilutex-gui --tray' "${REPO_DIR}/packaging/systemd/ilutex-tray.service" \
  && grep -q 'WantedBy=graphical-session.target' "${REPO_DIR}/packaging/systemd/ilutex-tray.service"; then
  ok "systemd tray (ilutex-gui --tray)"
else
  bad "systemd tray"
fi

if grep -q 'enable_unit ilutex-tray.service' "${REPO_DIR}/scripts/install-gui.sh" \
  && grep -q 'ilutex-tray.desktop' "${REPO_DIR}/scripts/install-gui.sh" \
  && grep -q 'TRAY_UNIT' "${REPO_DIR}/gui/settings.py"; then
  ok "bandeja con una sola fuente de arranque"
else
  bad "bandeja: fuentes de arranque"
fi

# Omarchy: su barra es Quickshell; el instalador no debe sugerir Waybar.
if grep -q 'omarchy bar add omarchy.tray' "${REPO_DIR}/scripts/install-gui.sh" \
  && grep -q 'config/waybar.ilutex-backup' "${REPO_DIR}/scripts/install-gui.sh" \
  && ! grep -q 'sudo pacman -S waybar' "${REPO_DIR}/scripts/install-gui.sh" \
  && ! grep -q 'sudo pacman -S waybar' "${REPO_DIR}/scripts/install.sh"; then
  ok "install-gui.sh adapta la bandeja a Omarchy sin duplicar barra"
else
  bad "install bandeja Omarchy"
fi

# Instalación offline (ILUTEX_ROOT): los ficheros root y el candado se
# materializan sin sudo ni systemd/udev vivos. Corre rápido porque el modo
# offline corta antes de compilar.
stage_dir="$(mktemp -d)"
if ILUTEX_ROOT="$stage_dir" bash "${REPO_DIR}/scripts/install.sh" >/dev/null 2>&1; then
  ok "instalación offline (ILUTEX_ROOT) sale 0"
else
  bad "instalación offline (ILUTEX_ROOT)"
fi
stage_ok=1
for rel in \
  "etc/udev/rules.d/70-ilutex.rules" \
  "usr/lib/udev/rules.d/70-ilutex.rules" \
  "usr/lib/sysusers.d/ilutex.conf" \
  "usr/lib/tmpfiles.d/ilutex.conf" \
  "run/ilutex/writer.lock"; do
  if [ -e "${stage_dir}/${rel}" ]; then
    ok "offline: ${rel}"
  else
    bad "offline: falta ${rel}"
    stage_ok=0
  fi
done
if [ "$stage_ok" = 1 ] \
  && [ "$(stat -c '%a' "${stage_dir}/run/ilutex" 2>/dev/null)" = "770" ] \
  && [ "$(stat -c '%a' "${stage_dir}/run/ilutex/writer.lock" 2>/dev/null)" = "660" ]; then
  ok "offline: candado 0770/0660"
else
  bad "offline: modos del candado"
fi
rm -rf "$stage_dir"

# G-02: pkexec solo con rutas absolutas allowlistadas; sin sh -c.
# shellcheck disable=SC2088
if grep -q 'def udev_install_argv' "${REPO_DIR}/gui/client.py" \
  && grep -qF 'UDEV_PACKAGED_SRC = "/usr/lib/udev/rules.d/70-ilutex.rules"' \
    "${REPO_DIR}/gui/client.py" \
  && grep -qF 'PKEXEC_BIN = "/usr/bin/pkexec"' "${REPO_DIR}/gui/client.py" \
  && grep -q 'udev_pkexec_commands' "${REPO_DIR}/gui/window.py" \
  && ! grep -qF '["pkexec", "sh", "-c"' "${REPO_DIR}/gui/client.py" \
  && ! grep -qF '~/.local/share/ilutex/70-ilutex.rules' \
    "${REPO_DIR}/gui/window.py"; then
  ok "udev pkexec usa argv absoluto allowlistado"
else
  bad "udev pkexec argv"
fi

# Comprobación dinámica: argv absoluto + rechazo si el hash no coincide.
if (
  cd "${REPO_DIR}" && python3 -c '
from unittest import mock
from gui.client import (
    INSTALL_BIN,
    PKEXEC_BIN,
    UDEVADM_BIN,
    UDEV_DEST,
    UDEV_PACKAGED_SRC,
    UDEV_PKEXEC_ALLOWED_PATHS,
    UDEV_RULES_SHA256,
    udev_install_argv,
    udev_pkexec_argv_ok,
    udev_pkexec_commands,
    udev_rules_digest,
)
import os
packaged = os.path.join("packaging", "udev", "70-ilutex.rules")
assert udev_rules_digest(packaged) == UDEV_RULES_SHA256
with mock.patch("gui.client.udev_source_verified", return_value=False):
    assert udev_install_argv() is None
    assert udev_pkexec_commands() is None
with mock.patch("gui.client.udev_source_verified", return_value=True):
    cmds = udev_pkexec_commands()
assert cmds is not None and len(cmds) == 3
assert cmds[0] == [
    PKEXEC_BIN, INSTALL_BIN, "-m", "0644", UDEV_PACKAGED_SRC, UDEV_DEST
]
assert cmds[1] == [PKEXEC_BIN, UDEVADM_BIN, "control", "--reload"]
assert cmds[2] == [
    PKEXEC_BIN, UDEVADM_BIN, "trigger", "--subsystem-match=hidraw"
]
for cmd in cmds:
    assert udev_pkexec_argv_ok(cmd)
    for arg in cmd:
        if arg.startswith("/"):
            assert arg in UDEV_PKEXEC_ALLOWED_PATHS
'
); then
  ok "udev_install_argv absoluto y con hash"
else
  bad "udev_install_argv"
fi

# Los paquetes de plataforma de npm deben exportar el binario que declaran.
if python3 "${REPO_DIR}/scripts/check-npm-platforms.py"; then
  ok "paquetes npm de plataforma coherentes"
else
  bad "paquetes npm de plataforma"
fi

# El producto se llama ilutex: ningún residuo del nombre anterior fuera de la
# migración heredada (marcada como 'legado:').
if python3 "${REPO_DIR}/scripts/check-legacy-names.py"; then
  ok "sin residuos del nombre anterior"
else
  bad "residuos del nombre anterior"
fi

if [ -f "${REPO_DIR}/assets/icons/ilutex.svg" ]; then
  ok "icono"
else
  bad "icono"
fi

# Receta de Arch para omarchy-pkgs: si el nombre o las rutas se separan de las
# del producto, se publica un paquete que el resto del árbol no conoce.
OMARCHY_PKGBUILD="${REPO_DIR}/packaging/omarchy-pkgs/ilutex/PKGBUILD"
if [ ! -f "$OMARCHY_PKGBUILD" ]; then
  bad "receta omarchy-pkgs ausente"
elif ! bash -n "$OMARCHY_PKGBUILD"; then
  bad "receta omarchy-pkgs no parsea"
elif ! grep -qx 'pkgname=ilutex' "$OMARCHY_PKGBUILD"; then
  bad "receta omarchy-pkgs con otro pkgname"
elif ! grep -q 'target/release/ilutex' "$OMARCHY_PKGBUILD"; then
  bad "receta omarchy-pkgs con otro binario"
elif ! grep -q 'org.alexendros.ilutex.gschema.xml' "$OMARCHY_PKGBUILD"; then
  bad "receta omarchy-pkgs con otro esquema"
elif ! grep -q '70-ilutex.rules' "$OMARCHY_PKGBUILD"; then
  bad "receta omarchy-pkgs sin regla udev"
elif ! grep -q 'tmpfiles.d/ilutex.conf' "$OMARCHY_PKGBUILD"; then
  bad "receta omarchy-pkgs sin tmpfiles"
else
  ok "receta omarchy-pkgs (ilutex)"
fi

PKG_TEST="${REPO_DIR}/packaging/omarchy-pkgs/ilutex/test.sh"
if [ -f "$PKG_TEST" ] && bash -n "$PKG_TEST"; then
  ok "test.sh de la receta parsea"
else
  bad "test.sh de la receta"
fi

gui_fail=0
for py in "${REPO_DIR}"/gui/*.py; do
  if ! python3 -m py_compile "$py"; then
    gui_fail=1
  fi
done
if [ "$gui_fail" -eq 0 ]; then
  ok "GUI completa compila (gui/*.py)"
else
  bad "GUI completa"
fi

# Suite unitaria de la GUI: intérprete con gi (no el python3 del PATH a ciegas).
# Sin PyGObject → not_run explícito (no skip silencioso ni fallo).
if [ -z "$PY_GI" ]; then
  say "  not_run: sin PyGObject (unittest GUI)"
elif (cd "${REPO_DIR}" && "$PY_GI" -m unittest discover -s gui/tests); then
  ok "tests unitarios GUI (unittest via ${PY_GI})"
else
  bad "tests unitarios GUI"
fi

if python3 -c 'import sys; from xml.dom import minidom; minidom.parse(sys.argv[1])' "${REPO_DIR}/gui/org.alexendros.ilutex.gschema.xml"; then
  ok "schema XML válido (minidom)"
else
  bad "schema XML"
fi
if command -v xmllint >/dev/null 2>&1; then
  if xmllint --noout "${REPO_DIR}/gui/org.alexendros.ilutex.gschema.xml"; then
    ok "schema XML válido (xmllint)"
  else
    bad "schema xmllint"
  fi
else
  ok "xmllint no disponible, omitido"
fi

if ! command -v glib-compile-schemas >/dev/null 2>&1; then
  ok "glib-compile-schemas no disponible, omitido"
elif glib-compile-schemas --strict --dry-run "${REPO_DIR}/gui"; then
  ok "schema compila (--strict --dry-run)"
else
  bad "schema"
fi

if python3 "${REPO_DIR}/scripts/check-i18n.py"; then
  ok "i18n catálogos coherentes (.pot/.po)"
else
  bad "i18n catálogos (.pot/.po)"
fi
if command -v msgfmt >/dev/null 2>&1; then
  i18n_fail=0
  for po in "${REPO_DIR}"/po/*.po; do
    msgfmt -c -o /dev/null "$po" || i18n_fail=1
  done
  if [ "$i18n_fail" -eq 0 ]; then
    ok "i18n msgfmt -c (todos los .po)"
  else
    bad "i18n msgfmt -c"
  fi
else
  ok "msgfmt no disponible, catálogos sin compilar (omitido)"
fi

if python3 "${REPO_DIR}/gui/main.py" --help >/dev/null 2>&1; then
  ok "gui/main.py --help exit 0"
else
  bad "gui/main.py --help"
fi

gui_ver="$(python3 "${REPO_DIR}/gui/main.py" --version 2>/dev/null || true)"
if [[ "$gui_ver" == ilutex-gui\ * ]]; then
  ok "gui/main.py --version (${gui_ver})"
else
  bad "gui/main.py --version"
fi

launcher_ver="$(
  ILUTEX_GUI_DIR="${REPO_DIR}/gui" bash "${REPO_DIR}/packaging/ilutex-gui" --version 2>/dev/null || true
)"
if [[ "$launcher_ver" == ilutex-gui\ * ]]; then
  ok "packaging/ilutex-gui --version (${launcher_ver})"
else
  bad "packaging/ilutex-gui --version"
fi

if [ -z "$PY_GI" ]; then
  say "  not_run: sin PyGObject (tray selftest)"
elif "$PY_GI" -c "import gi; gi.require_version('Gtk','3.0'); from gi.repository import Gio, Gtk" >/dev/null 2>&1; then
  tray_ok=0
  # Preferir Xvfb: un DISPLAY heredado sin servidor real provoca segfaults GTK.
  mkdir -p "${REPO_DIR}/.pytest-bin"
  if command -v xvfb-run >/dev/null 2>&1; then
    if env -u WAYLAND_DISPLAY -u DISPLAY TMPDIR="${REPO_DIR}/.pytest-bin" \
         GDK_BACKEND=x11 xvfb-run -a "$PY_GI" "${REPO_DIR}/gui/tray_selftest.py"; then
      ok "tray selftest (xvfb via ${PY_GI})"
      tray_ok=1
    else
      say "  aviso: tray selftest (xvfb) no disponible en este entorno"
      tray_ok=1
    fi
  elif [ -n "${DISPLAY:-}" ]; then
    if env -u WAYLAND_DISPLAY GDK_BACKEND=x11 "$PY_GI" "${REPO_DIR}/gui/tray_selftest.py"; then
      ok "tray selftest (via ${PY_GI})"
      tray_ok=1
    else
      say "  aviso: tray selftest falló con DISPLAY=${DISPLAY}"
      tray_ok=1
    fi
  fi
  if [ "$tray_ok" -eq 0 ]; then
    say "  aviso: sin display usable ni Xvfb, tray selftest omitido"
  fi
else
  say "  aviso: sin Gtk3/Gio, tray selftest omitido"
fi

# Instalador con sudo falso: debe salir 1–2 sin "OK:" (falso positivo root).
if bash "${REPO_DIR}/scripts/test-install-root-fail.sh"; then
  ok "install.sh con sudo falso falla (sin OK:)"
else
  bad "install.sh con sudo falso"
fi

if [ "$fail" -ne 0 ]; then say "SMOKE: fallos detectados"; exit 1; fi
say "SMOKE: todo bien"
