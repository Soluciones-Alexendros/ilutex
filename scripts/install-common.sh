# shellcheck shell=bash
# Helpers compartidos por install-cli.sh, install-gui.sh e install.sh.
# No ejecutar directamente.

# Gestor de paquetes de la distro (para pistas de instalación concretas).
pkg_manager() {
  local id=""
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id=" ${ID:-} ${ID_LIKE:-} "
  fi
  case "$id" in
    *arch*|*manjaro*|*endeavouros*) echo pacman ;;
    *fedora*|*rhel*|*centos*|*nobara*) echo dnf ;;
    *opensuse*|*suse*) echo zypper ;;
    *debian*|*ubuntu*|*mint*|*pop*) echo apt ;;
    *) echo "" ;;
  esac
}

# pkg_hint <gettext|glib|tray>: comando concreto para instalar el rol.
pkg_hint() {
  local mgr
  mgr="$(pkg_manager)"
  case "${mgr}:$1" in
    apt:gettext)    echo "sudo apt install gettext" ;;
    apt:glib)       echo "sudo apt install libglib2.0-bin" ;;
    apt:tray)       echo "sudo apt install python3-cairo" ;;
    pacman:gettext) echo "sudo pacman -S gettext" ;;
    pacman:glib)    echo "sudo pacman -S glib2" ;;
    pacman:tray)    echo "sudo pacman -S python-cairo" ;;
    dnf:gettext)    echo "sudo dnf install gettext" ;;
    dnf:glib)       echo "sudo dnf install glib2" ;;
    dnf:tray)       echo "sudo dnf install python3-cairo" ;;
    zypper:gettext) echo "sudo zypper install gettext" ;;
    zypper:glib)    echo "sudo zypper install glib2" ;;
    zypper:tray)    echo "sudo zypper install python3-cairo" ;;
    *:gettext)      echo "instala gettext con tu gestor de paquetes" ;;
    *:glib)         echo "instala glib2 (glib-compile-schemas) con tu gestor de paquetes" ;;
    *:tray)         echo "instala python3-cairo y un host StatusNotifier (extensión AppIndicator, waybar tray, omarchy.tray, …)" ;;
    *)              echo "instala '$1' con tu gestor de paquetes" ;;
  esac
}

# ¿El usuario actual ya está en el grupo ilutex?
in_ilutex_group() {
  id -nG "${USER}" 2>/dev/null | tr ' ' '\n' | grep -qx ilutex
}

# Sustituye dst solo si el contenido difiere (idempotente: mtime estable).
# Devuelve 0 si escribió, 1 si ya era idéntico.
install_if_changed() {
  local src="$1" dst="$2" mode="${3:-644}"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    return 1
  fi
  install -m"$mode" "$src" "$dst"
  return 0
}

# Resuelve el árbol fuente: tarball de --release o el repo que contiene scripts/.
# Variables de salida: ILUTEX_TREE, ILUTEX_BIN_SRC, stage_root.
resolve_install_paths() {
  local scripts_dir="$1"
  ILUTEX_SCRIPTS_DIR="$scripts_dir"
  if [ -n "${ILUTEX_RELEASE_DIR:-}" ]; then
    ILUTEX_TREE="$(cd "${ILUTEX_RELEASE_DIR}" && pwd)"
    ILUTEX_BIN_SRC="${ILUTEX_TREE}/ilutex"
  else
    ILUTEX_TREE="$(cd "${scripts_dir}/.." && pwd)"
    ILUTEX_BIN_SRC="${ILUTEX_TREE}/target/release/ilutex"
  fi

  stage_root=""
  if [ -n "${ILUTEX_ROOT:-}" ]; then
    case "$ILUTEX_ROOT" in
      /*) stage_root="$ILUTEX_ROOT" ;;
      *) echo "    aviso: ILUTEX_ROOT debe ser absoluta; se ignora" >&2 ;;
    esac
  fi
}
