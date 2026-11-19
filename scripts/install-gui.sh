#!/usr/bin/env bash
# Instala la mesa de luz GTK, lanzador, icono y unidades systemd de usuario.
# Sin sudo: todo bajo ~/.local y ~/.config. No toca udev ni el candado
# (ver install-cli.sh). La elevación pkexec de la GUI lee solo
# /usr/lib/udev/rules.d/70-ilutex.rules — no se copia la regla a ~/.local.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/install-common.sh
. "${SCRIPTS_DIR}/install-common.sh"
resolve_install_paths "$SCRIPTS_DIR"

BIN_DST="${HOME}/.local/bin"
UNIT_DST="${HOME}/.config/systemd/user"
DESK_DST="${HOME}/.local/share/applications"
ICON_DST="${HOME}/.local/share/icons/hicolor/scalable/apps"

if [ -n "${ILUTEX_ROOT:-}" ] && [ -n "${stage_root}" ]; then
  echo "==> ilutex: install-gui omite ILUTEX_ROOT (solo ficheros de usuario)"
fi

echo "==> ilutex: instalar GUI en ${BIN_DST}/ilutex-gui"
GUI_DST="${HOME}/.local/share/ilutex/gui"
mkdir -p "${GUI_DST}"
install -m644 "${ILUTEX_TREE}"/gui/*.py "${GUI_DST}/"
# Nota: no se instala 70-ilutex.rules en ~/.local; pkexec usa /usr/lib (install-cli
# o el paquete .deb/AUR). Instalación manual: ver docs/runbooks/empaquetado.md.
if [ -n "${ILUTEX_RELEASE_DIR:-}" ] && [ -x "${ILUTEX_TREE}/ilutex-gui" ]; then
  install -m755 "${ILUTEX_TREE}/ilutex-gui" "${BIN_DST}/ilutex-gui"
else
  install -m755 "${ILUTEX_TREE}/packaging/ilutex-gui" "${BIN_DST}/ilutex-gui"
fi

echo "==> ilutex: compilar traducciones (es, en)"
MO_SRC_DIR="${ILUTEX_TREE}/po"
if [ ! -d "$MO_SRC_DIR" ] && [ -n "${ILUTEX_RELEASE_DIR:-}" ]; then
  # El tarball de release no incluye po/; omite .mo si no hay fuentes.
  echo "    aviso: sin po/ en el árbol de release; se omiten traducciones" >&2
elif command -v msgfmt >/dev/null 2>&1; then
  for MO_SRC in "${MO_SRC_DIR}"/*.po; do
    [ -f "${MO_SRC}" ] || continue
    LANG_CODE="$(basename "${MO_SRC}" .po)"
    MO_BUILD="${ILUTEX_TREE}/gui/locale/${LANG_CODE}/LC_MESSAGES/ilutex.mo"
    MO_DST="${HOME}/.local/share/locale/${LANG_CODE}/LC_MESSAGES/ilutex.mo"
    mkdir -p "$(dirname "${MO_BUILD}")"
    msgfmt -o "${MO_BUILD}" "${MO_SRC}"
    echo "    .mo generado en ${MO_BUILD}"
    mkdir -p "$(dirname "${MO_DST}")"
    install -m644 "${MO_BUILD}" "${MO_DST}"
    echo "    locale instalado en ${MO_DST}"
  done
else
  echo "    aviso: msgfmt no disponible, se omite la compilación de los .mo (la GUI usará el idioma por defecto)" >&2
  echo "    pista: $(pkg_hint gettext)" >&2
fi

echo "==> ilutex: instalar schema GSettings"
SCHEMA_SRC="${ILUTEX_TREE}/gui/org.alexendros.ilutex.gschema.xml"
SCHEMA_DST_DIR="${HOME}/.local/share/glib-2.0/schemas"
if [ -f "$SCHEMA_SRC" ]; then
  mkdir -p "${SCHEMA_DST_DIR}"
  install -m644 "${SCHEMA_SRC}" "${SCHEMA_DST_DIR}/org.alexendros.ilutex.gschema.xml"
  if command -v glib-compile-schemas >/dev/null 2>&1; then
    glib-compile-schemas "${SCHEMA_DST_DIR}" || true
  else
    echo "    aviso: glib-compile-schemas no disponible, se omite la compilación de schemas" >&2
    echo "    pista: $(pkg_hint glib)" >&2
  fi
else
  echo "    aviso: sin schema GSettings en el árbol fuente" >&2
fi

echo "==> ilutex: instalar lanzador + icono"
mkdir -p "${DESK_DST}" "${ICON_DST}"
desk_tmp="$(mktemp)"
sed -e "s|^Exec=ilutex-gui\$|Exec=${BIN_DST}/ilutex-gui|" \
  "${ILUTEX_TREE}/packaging/desktop/ilutex.desktop" > "$desk_tmp"
if install_if_changed "$desk_tmp" "${DESK_DST}/ilutex.desktop" 644; then
  echo "    desktop actualizado (${DESK_DST}/ilutex.desktop)"
fi
rm -f "$desk_tmp"
if [ -f "${ILUTEX_TREE}/assets/icons/ilutex.svg" ]; then
  install_if_changed "${ILUTEX_TREE}/assets/icons/ilutex.svg" "${ICON_DST}/ilutex.svg" 644 || true
elif [ -f "${ILUTEX_TREE}/packaging/icons/ilutex.svg" ]; then
  install_if_changed "${ILUTEX_TREE}/packaging/icons/ilutex.svg" "${ICON_DST}/ilutex.svg" 644 || true
else
  echo "    aviso: sin icono ilutex.svg en el árbol fuente" >&2
fi

echo "==> ilutex: instalar unidades systemd de usuario"
mkdir -p "${UNIT_DST}"
unit_prev_of() {
  local unit="$1"
  systemctl --user is-enabled "$unit" 2>/dev/null || true
}
UNIT_PREV_RESTORE="$(unit_prev_of ilutex.service)"
UNIT_HAD_RESTORE=0
if [ -f "${UNIT_DST}/ilutex.service" ]; then
  UNIT_HAD_RESTORE=1
fi
UNIT_PREV_TRAY="$(unit_prev_of ilutex-tray.service)"
UNIT_HAD_TRAY=0
if [ -f "${UNIT_DST}/ilutex-tray.service" ]; then
  UNIT_HAD_TRAY=1
fi

# Las unidades de paquete apuntan a /usr/bin; en instalación local se reescriben
# al binario de ${BIN_DST}. (Las plantillas de npm usan __ILUTEX_BIN__ y las
# resuelve npm/install.js, no este script.)
units_changed=0
for unit in "${ILUTEX_TREE}/packaging/systemd"/*.service; do
  [ -f "$unit" ] || continue
  unit_tmp="$(mktemp)"
  sed -e "s|/usr/bin/ilutex-gui|${BIN_DST}/ilutex-gui|g" \
      -e "s|/usr/bin/ilutex|${BIN_DST}/ilutex|g" \
      "$unit" > "$unit_tmp"
  if install_if_changed "$unit_tmp" "${UNIT_DST}/$(basename "$unit")" 644; then
    units_changed=1
  fi
  rm -f "$unit_tmp"
done
if [ "$units_changed" = 1 ]; then
  systemctl --user daemon-reload 2>/dev/null || true
fi

enable_unit() {
  local unit="$1" label="$2" force="${3:-0}"
  local prev="" had=0
  case "$unit" in
    ilutex.service) prev="${UNIT_PREV_RESTORE:-}" had="${UNIT_HAD_RESTORE:-0}" ;;
    ilutex-tray.service) prev="${UNIT_PREV_TRAY:-}" had="${UNIT_HAD_TRAY:-0}" ;;
  esac
  case "$prev" in
    masked)
      echo "==> ilutex: ${label}: unidad enmascarada; no se toca"
      return 0 ;;
    enabled|enabled-runtime)
      return 0 ;;
    disabled)
      if [ "$had" = 1 ] && [ "$force" != "1" ]; then
        echo "==> ilutex: ${label} deshabilitada por el usuario; no se reactiva"
        return 0
      fi ;;
  esac
  if systemctl --user enable "$unit" 2>/dev/null; then
    echo "==> ilutex: ${label} habilitada (${unit})"
  else
    echo "    aviso: no se pudo habilitar ${unit}" >&2
  fi
}

enable_unit ilutex.service "restauración al inicio" "${ILUTEX_ENABLE_RESTORE:-0}"

if [ "${ILUTEX_NO_TRAY:-0}" = "1" ]; then
  echo "==> ilutex: bandeja desactivada (ILUTEX_NO_TRAY=1)"
else
  enable_unit ilutex-tray.service "bandeja al iniciar sesión" "${ILUTEX_ENABLE_TRAY:-0}"
  legacy_autostart="${XDG_CONFIG_HOME:-${HOME}/.config}/autostart/ilutex-tray.desktop"
  if [ -f "$legacy_autostart" ] && systemctl --user is-enabled ilutex-tray.service >/dev/null 2>&1; then
    mv "$legacy_autostart" "${legacy_autostart}.bak" 2>/dev/null \
      && echo "    autostart XDG retirado (la unidad ya arranca la bandeja)"
  fi
fi

echo "==> ilutex: comprobar dependencias de la GUI y la bandeja"
PY_GTK=""
for cand in python3 /usr/bin/python3; do
  command -v "$cand" >/dev/null 2>&1 || continue
  if "$cand" -c 'import gi' >/dev/null 2>&1; then
    PY_GTK="$cand"
    break
  fi
done
[ -n "$PY_GTK" ] || PY_GTK=python3
tray_ok=1
"$PY_GTK" -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gio, Gtk; import cairo' >/dev/null 2>&1 || tray_ok=0
gui_ok=1
"$PY_GTK" -c 'import gi; gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1"); from gi.repository import Gtk, Adw' >/dev/null 2>&1 || gui_ok=0
if [ "$gui_ok" = 0 ]; then
  echo "    aviso: la ventana no arrancará hasta instalar sus dependencias" >&2
  case "$(pkg_manager)" in
    pacman) echo "    pista: sudo pacman -S python-gobject gtk4 libadwaita" >&2 ;;
    dnf)    echo "    pista: sudo dnf install python3-gobject gtk4 libadwaita" >&2 ;;
    zypper) echo "    pista: sudo zypper install python3-gobject gtk4 libadwaita" >&2 ;;
    *)      echo "    pista: sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1" >&2 ;;
  esac
fi
if [ "$tray_ok" = 0 ]; then
  echo "    aviso: la bandeja (--tray) no estará disponible hasta instalar sus dependencias" >&2
  echo "    pista: $(pkg_hint tray)" >&2
fi

# Aparta una barra Waybar propia: en Omarchy la barra es Quickshell y tener
# las dos duplica la barra superior. Se mueve con respaldo (no se borra).
evict_foreign_waybar() {
  if [ -d "${HOME}/.config/waybar" ]; then
    local backup
    backup="${HOME}/.config/waybar.ilutex-backup-$(date +%Y%m%d%H%M%S)"
    mv "${HOME}/.config/waybar" "$backup" 2>/dev/null \
      && echo "    barra waybar apartada en $backup (Omarchy ya tiene la suya)"
  fi
  if pgrep -x waybar >/dev/null 2>&1; then
    pkill -x waybar 2>/dev/null && echo "    proceso waybar detenido (duplicaba la barra)"
  fi
}

tray_host_ok=1
if [ -d /usr/share/omarchy ]; then
  echo "==> ilutex: Omarchy detectado — la bandeja la pinta su shell (Quickshell)"
  shell_json="${HOME}/.config/omarchy/shell.json"
  if [ -f "$shell_json" ] && ! grep -q "omarchy.tray" "$shell_json"; then
    if command -v omarchy >/dev/null 2>&1 \
      && omarchy bar add omarchy.tray --section right >/dev/null 2>&1; then
      echo "    widget omarchy.tray añadido a la barra"
    else
      echo "    aviso: la barra no tiene el widget de bandeja" >&2
      echo "    pista: omarchy bar add omarchy.tray --section right" >&2
      tray_host_ok=0
    fi
  else
    echo "    el icono aparece en el widget omarchy.tray de la barra"
  fi
  evict_foreign_waybar
elif [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || [ "${XDG_CURRENT_DESKTOP:-}" = "Hyprland" ]; then
  echo "==> ilutex: Hyprland sin Omarchy — hace falta un host StatusNotifier"
  if ! command -v waybar >/dev/null 2>&1 && ! command -v quickshell >/dev/null 2>&1; then
    echo "    aviso: sin waybar ni quickshell, el icono de bandeja no se verá" >&2
    echo "    pista: instala waybar con un módulo 'tray' en su config" >&2
    tray_host_ok=0
  fi
fi

# Extensión GNOME: solo pista (sin sudo; el orquestador o el usuario la instalan).
gnome_desktop=0
[ "$(pkg_manager)" = pacman ] && [ ! -d /usr/share/omarchy ] \
  && [ "${XDG_CURRENT_DESKTOP:-}" != "Hyprland" ] && gnome_desktop=1
if [ "$tray_ok" = 0 ] && [ "$tray_host_ok" = 1 ] && [ "$gnome_desktop" = 1 ]; then
  echo "==> ilutex: en GNOME/Arch hace falta gnome-shell-extension-appindicator"
  echo "    pista: sudo pacman -S --needed gnome-shell-extension-appindicator" >&2
  echo "    Luego recarga GNOME Shell (Alt+F2 \"r\" + Enter) o reinicia sesión." >&2
fi

echo "OK: mesa de luz instalada. Prueba con: ilutex-gui"
