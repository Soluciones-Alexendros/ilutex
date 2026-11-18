#!/usr/bin/env bash
# Orquestador de instalación local.
#
# Uso:
#   ./scripts/install.sh                  # compila el árbol local (sin red)
#   ./scripts/install.sh --release <tag>  # descarga tarball + SHA256SUMS, verifica
#   ILUTEX_ROOT=/ruta ./scripts/install.sh  # solo ficheros root (offline)
#
# Partes:
#   install-cli.sh  — binario, udev (/usr/lib + /etc), sysusers, tmpfiles (sudo)
#   install-gui.sh  — GUI, desktop, icono, unidades de usuario (sin sudo)
#
# pkexec (GUI) solo lee /usr/lib/udev/rules.d/70-ilutex.rules; no ~/.local.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
. "${SCRIPTS_DIR}/install-common.sh"

ILUTEX_GITHUB_REPO="${ILUTEX_GITHUB_REPO:-Soluciones-Alexendros/ilutex}"
RELEASE_TAG=""

usage() {
  cat <<'EOF'
Uso: ./scripts/install.sh [--release <tag>]

  (sin flags)     Compila e instala desde el árbol local. No usa la red.
  --release TAG   Descarga ilutex-TAG-linux-x86_64.tar.gz y SHA256SUMS del
                  release de GitHub, verifica checksums (y attestation con gh
                  si hay sesión) e instala desde el tarball.

Variables:
  ILUTEX_ROOT=/ruta_absoluta   Solo ficheros root bajo ese root (sin sudo).
  ILUTEX_SKIP_UDEV=1           Omite la regla udev.
  ILUTEX_GITHUB_REPO=owner/repo  Repo de releases (default Soluciones-Alexendros/ilutex).

Partes directas:
  ./scripts/install-cli.sh   CLI + udev/sysusers/tmpfiles
  ./scripts/install-gui.sh   mesa de luz + desktop + unidades de usuario
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --release)
      shift
      if [ $# -lt 1 ] || [ -z "${1:-}" ]; then
        echo "error: --release requiere un tag (p. ej. v3.1.1)" >&2
        usage >&2
        exit 2
      fi
      RELEASE_TAG="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: argumento desconocido: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# H-07: descarga + verificación. Solo con --release; el camino por defecto
# no toca la red.
fetch_and_verify_release() {
  local tag="$1"
  local asset sums_name work download_url sums_url
  asset="ilutex-${tag}-linux-x86_64.tar.gz"
  sums_name="SHA256SUMS"
  work="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT

  download_url="https://github.com/${ILUTEX_GITHUB_REPO}/releases/download/${tag}/${asset}"
  sums_url="https://github.com/${ILUTEX_GITHUB_REPO}/releases/download/${tag}/${sums_name}"

  echo "==> ilutex: descargar release ${tag}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "${work}/${asset}" "$download_url"
    curl -fsSL -o "${work}/${sums_name}" "$sums_url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "${work}/${asset}" "$download_url"
    wget -q -O "${work}/${sums_name}" "$sums_url"
  else
    echo "error: hace falta curl o wget para --release" >&2
    exit 1
  fi

  echo "==> ilutex: verificar SHA256SUMS"
  (
    cd "$work"
    # --ignore-missing: el manifiesto lista .deb/sbom además del tarball.
    sha256sum -c SHA256SUMS --ignore-missing
  )

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "==> ilutex: verificar attestation (gh)"
    gh attestation verify "${work}/${asset}" --repo "${ILUTEX_GITHUB_REPO}"
  else
    echo "    aviso: gh no autenticado; se omite attestation verify" >&2
  fi

  echo "==> ilutex: extraer ${asset}"
  tar -xzf "${work}/${asset}" -C "$work"
  # Directorio tipico: ilutex-vX.Y.Z-linux-x86_64
  local extracted
  extracted="$(find "$work" -mindepth 1 -maxdepth 1 -type d -name 'ilutex-*-linux-x86_64' | head -n1)"
  if [ -z "$extracted" ] || [ ! -x "${extracted}/ilutex" ]; then
    echo "error: el tarball no contiene ilutex-*-linux-x86_64/ilutex" >&2
    exit 1
  fi
  # Quitar el trap de borrado: el directorio vive hasta el final del proceso
  # vía ILUTEX_RELEASE_DIR; se limpia al salir del orquestador.
  trap - EXIT
  ILUTEX_RELEASE_WORK="$work"
  export ILUTEX_RELEASE_DIR="$extracted"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT
}

if [ -n "$RELEASE_TAG" ]; then
  fetch_and_verify_release "$RELEASE_TAG"
  export ILUTEX_RELEASE_DIR
fi

# Offline: solo CLI/root (sin GUI).
if [ -n "${ILUTEX_ROOT:-}" ]; then
  case "$ILUTEX_ROOT" in
    /*)
      bash "${SCRIPTS_DIR}/install-cli.sh"
      exit $?
      ;;
    *)
      echo "    aviso: ILUTEX_ROOT debe ser absoluta; se ignora" >&2
      unset ILUTEX_ROOT
      ;;
  esac
fi

bash "${SCRIPTS_DIR}/install-cli.sh"
bash "${SCRIPTS_DIR}/install-gui.sh"

# Extensión GNOME opcional (único paso con sudo fuera de install-cli).
if [ "$(pkg_manager)" = pacman ] && [ ! -d /usr/share/omarchy ] \
  && [ "${XDG_CURRENT_DESKTOP:-}" != "Hyprland" ]; then
  # Host SNI (G-03): la extensión es el host; el cliente ya no usa Ayatana.
  if ! python3 -c 'import gi; from gi.repository import Gio, GLib
bus=Gio.bus_get_sync(Gio.BusType.SESSION, None)
r=bus.call_sync("org.kde.StatusNotifierWatcher","/StatusNotifierWatcher","org.freedesktop.DBus.Properties","Get",GLib.Variant("(ss)",("org.kde.StatusNotifierWatcher","IsStatusNotifierHostRegistered")),GLib.VariantType("(v)"),Gio.DBusCallFlags.NONE,2000,None)
assert r.unpack()[0] is True' >/dev/null 2>&1; then
    echo "==> ilutex: instalar gnome-shell-extension-appindicator (root, opcional)"
    if sudo pacman -S --needed --noconfirm gnome-shell-extension-appindicator; then
      echo "==> ilutex: extensión AppIndicator instalada; recarga GNOME Shell (Alt+F2 \"r\" + Enter) o reinicia sesión" >&2
    else
      echo "    aviso: no se pudo instalar gnome-shell-extension-appindicator" >&2
    fi
  fi
fi
