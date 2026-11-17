#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DST="${HOME}/.local/bin"
UNIT_DST="${HOME}/.config/systemd/user"
DESK_DST="${HOME}/.local/share/applications"
ICON_DST="${HOME}/.local/share/icons/hicolor/scalable/apps"

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
    apt:tray)       echo "sudo apt install gir1.2-ayatanaappindicator3-0.1 python3-cairo gnome-shell-extension-appindicator" ;;
    pacman:gettext) echo "sudo pacman -S gettext" ;;
    pacman:glib)    echo "sudo pacman -S glib2" ;;
    pacman:tray)    echo "sudo pacman -S libayatana-appindicator python-cairo" ;;
    dnf:gettext)    echo "sudo dnf install gettext" ;;
    dnf:glib)       echo "sudo dnf install glib2" ;;
    dnf:tray)       echo "sudo dnf install libayatana-appindicator-gtk3 python3-cairo gnome-shell-extension-appindicator" ;;
    zypper:gettext) echo "sudo zypper install gettext" ;;
    zypper:glib)    echo "sudo zypper install glib2" ;;
    zypper:tray)    echo "sudo zypper install libayatana-appindicator3-1 python3-cairo gnome-shell-extension-appindicator" ;;
    *:gettext)      echo "instala gettext con tu gestor de paquetes" ;;
    *:glib)         echo "instala glib2 (glib-compile-schemas) con tu gestor de paquetes" ;;
    *:tray)         echo "instala AyatanaAppIndicator3, pycairo y gnome-shell-extension-appindicator con tu gestor de paquetes" ;;
    *)              echo "instala '$1' con tu gestor de paquetes" ;;
  esac
}

# ¿El usuario actual ya está en el grupo ilutex? Se consulta dos veces: al
# instalar el candado y al resumir el resultado.
in_ilutex_group() {
  id -nG "${USER}" 2>/dev/null | tr ' ' '\n' | grep -qx ilutex
}

echo "==> ilutex: compilar (release)"
cargo build --release --manifest-path "${REPO_DIR}/Cargo.toml"

echo "==> ilutex: instalar binario en ${BIN_DST}/ilutex"
mkdir -p "${BIN_DST}"
install -m755 "${REPO_DIR}/target/release/ilutex" "${BIN_DST}/ilutex"

echo "==> ilutex: instalar GUI en ${BIN_DST}/ilutex-gui"
GUI_DST="${HOME}/.local/share/ilutex/gui"
mkdir -p "${GUI_DST}"
install -m644 "${REPO_DIR}"/gui/*.py "${GUI_DST}/"
install -m644 "${REPO_DIR}/packaging/udev/70-ilutex.rules" "${HOME}/.local/share/ilutex/70-ilutex.rules"
install -m755 "${REPO_DIR}/packaging/ilutex-gui" "${BIN_DST}/ilutex-gui"

echo "==> ilutex: compilar traducciones (es, en)"
MO_SRC_DIR="${REPO_DIR}/po"
if command -v msgfmt >/dev/null 2>&1; then
  for MO_SRC in "${MO_SRC_DIR}"/*.po; do
    [ -f "${MO_SRC}" ] || continue
    LANG_CODE="$(basename "${MO_SRC}" .po)"
    MO_BUILD="${REPO_DIR}/gui/locale/${LANG_CODE}/LC_MESSAGES/ilutex.mo"
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
SCHEMA_SRC="${REPO_DIR}/gui/org.alexendros.ilutex.gschema.xml"
SCHEMA_DST_DIR="${HOME}/.local/share/glib-2.0/schemas"
mkdir -p "${SCHEMA_DST_DIR}"
install -m644 "${SCHEMA_SRC}" "${SCHEMA_DST_DIR}/org.alexendros.ilutex.gschema.xml"
if command -v glib-compile-schemas >/dev/null 2>&1; then
  glib-compile-schemas "${SCHEMA_DST_DIR}" || true
else
  echo "    aviso: glib-compile-schemas no disponible, se omite la compilación de schemas" >&2
  echo "    pista: $(pkg_hint glib)" >&2
fi
# Nota: el arranque de la bandeja lo gobierna ilutex-tray.service (más abajo).
# gui/settings.py usa esa unidad y solo cae al autostart XDG si no hay systemd.

echo "==> ilutex: instalar lanzador + icono"
mkdir -p "${DESK_DST}" "${ICON_DST}"
install -m644 "${REPO_DIR}/packaging/desktop/ilutex.desktop" "${DESK_DST}/ilutex.desktop"
install -m644 "${REPO_DIR}/assets/icons/ilutex.svg" "${ICON_DST}/ilutex.svg"

echo "==> ilutex: instalar unidades systemd de usuario"
mkdir -p "${UNIT_DST}"
# Estado previo por unidad: distinguir «unidad nueva» (sin fichero) de «el
# usuario la desactivó». Se muestrea antes de instalar; si no, una unidad nueva
# nunca se habilitaba.
declare -A UNIT_PREV=()
declare -A UNIT_HAD=()
record_unit_state() {
  local unit="$1"
  UNIT_PREV["$unit"]="$(systemctl --user is-enabled "$unit" 2>/dev/null || true)"
  UNIT_HAD["$unit"]=false
  [ -f "${UNIT_DST}/${unit}" ] && UNIT_HAD["$unit"]=true
}
for unit in ilutex.service ilutex-tray.service; do
  record_unit_state "$unit"
done

# Las unidades de paquete apuntan a /usr/bin; en instalación local se reescriben
# al binario de ${BIN_DST}. (Las plantillas de npm usan __ILUTEX_BIN__ y las
# resuelve npm/install.js, no este script.)
for unit in "${REPO_DIR}/packaging/systemd"/*.service; do
  [ -f "$unit" ] || continue
  sed -e "s|/usr/bin/ilutex-gui|${BIN_DST}/ilutex-gui|g" \
      -e "s|/usr/bin/ilutex|${BIN_DST}/ilutex|g" \
      "$unit" > "${UNIT_DST}/$(basename "$unit")"
done
systemctl --user daemon-reload 2>/dev/null || true

# Habilita una unidad respetando lo que el usuario ya decidió: `masked` no se
# toca, `disabled` con fichero previo no se reactiva, y una unidad nueva se
# habilita salvo que el entorno pida lo contrario.
enable_unit() {
  local unit="$1" label="$2" force="${3:-0}"
  local prev="${UNIT_PREV[$unit]:-}" had="${UNIT_HAD[$unit]:-false}"
  case "$prev" in
    masked)
      echo "==> ilutex: ${label}: unidad enmascarada; no se toca"
      return 0 ;;
    enabled|enabled-runtime)
      return 0 ;;
    disabled)
      if [ "$had" = true ] && [ "$force" != "1" ]; then
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

# Restauración al login.
enable_unit ilutex.service "restauración al inicio" "${ILUTEX_ENABLE_RESTORE:-0}"

# Bandeja: una sola fuente de arranque (unidad de usuario, no autostart XDG).
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

echo "==> ilutex: regla udev (opcional, root)"
if [ "${ILUTEX_SKIP_UDEV:-0}" = "1" ]; then
  echo "    omitida (ILUTEX_SKIP_UDEV=1)"
else
  udev_ok=1
  if ! sudo install -D -m644 "${REPO_DIR}/packaging/udev/70-ilutex.rules" /etc/udev/rules.d/70-ilutex.rules; then
    echo "    error: no se pudo instalar udev/70-ilutex.rules" >&2
    udev_ok=0
  fi
  if ! sudo udevadm control --reload; then
    echo "    error: udevadm control --reload falló" >&2
    udev_ok=0
  fi
  if ! sudo udevadm trigger --subsystem-match=hidraw; then
    echo "    error: udevadm trigger falló" >&2
    udev_ok=0
  fi
  if [ "$udev_ok" = 1 ]; then
    echo "==> ilutex: regla udev instalada (root)"
  else
    echo "==> ilutex: regla udev incompleta" >&2
  fi
fi

echo "==> ilutex: candado de escritura (root)"
writer_lock_ok=1
if ! sudo install -D -m644 "${REPO_DIR}/packaging/sysusers.d/ilutex.conf" /usr/lib/sysusers.d/ilutex.conf; then
  echo "    error: no se pudo instalar sysusers.d/ilutex.conf" >&2
  writer_lock_ok=0
fi
if ! sudo install -D -m644 "${REPO_DIR}/packaging/tmpfiles.d/ilutex.conf" /usr/lib/tmpfiles.d/ilutex.conf; then
  echo "    error: no se pudo instalar tmpfiles.d/ilutex.conf" >&2
  writer_lock_ok=0
fi
if command -v systemd-sysusers >/dev/null 2>&1; then
  if ! sudo systemd-sysusers ilutex.conf; then
    echo "    error: systemd-sysusers ilutex.conf falló" >&2
    writer_lock_ok=0
  fi
else
  echo "    aviso: systemd-sysusers no disponible; crea el grupo ilutex a mano" >&2
  writer_lock_ok=0
fi
if command -v systemd-tmpfiles >/dev/null 2>&1; then
  if ! sudo systemd-tmpfiles --create ilutex.conf; then
    echo "    error: systemd-tmpfiles --create ilutex.conf falló" >&2
    writer_lock_ok=0
  fi
else
  echo "    aviso: systemd-tmpfiles no disponible; crea /run/ilutex a mano" >&2
  writer_lock_ok=0
fi
if [ ! -d /run/ilutex ] || [ ! -e /run/ilutex/writer.lock ]; then
  echo "    error: falta /run/ilutex/writer.lock tras tmpfiles" >&2
  writer_lock_ok=0
fi
if [ "$writer_lock_ok" = 1 ]; then
  echo "==> ilutex: candado instalado (root:ilutex 0660; dir 0770)"
else
  echo "==> ilutex: candado incompleto; sin él el CLI no escribe" >&2
fi
# Instalar ≠ autorizar: no añadimos usuarios al grupo automáticamente.
if in_ilutex_group; then
  echo "==> ilutex: ${USER} ya está en el grupo ilutex"
else
  echo "==> ilutex: autorización de escritura pendiente"
  echo "    Instalar no te mete en el grupo. Para poder escribir:"
  echo "      sudo usermod -aG ilutex ${USER}"
  echo "    Luego cierra sesión y vuelve a entrar (o: newgrp ilutex)."
fi

echo "==> ilutex: migrar estado heredado kbd-rgb/keybackcon (si existe)"
for d in "${XDG_STATE_HOME:-${HOME}/.local/state}" "${HOME}/.local/state"; do
  # kbd-rgb -> ilutex
  if [ -f "$d/kbd-rgb/state" ] && [ ! -f "$d/ilutex/state" ]; then
    mkdir -p "$d/ilutex"
    cp "$d/kbd-rgb/state" "$d/ilutex/state"
    echo "    migrado $d/kbd-rgb/state -> $d/ilutex/state"
    break
  fi
  # keybackcon -> ilutex
  if [ -f "$d/keybackcon/state" ] && [ ! -f "$d/ilutex/state" ]; then
    mkdir -p "$d/ilutex"
    cp "$d/keybackcon/state" "$d/ilutex/state"
    echo "    migrado $d/kbd-rgb/state -> $d/ilutex/state"
    break
  fi
done

echo "==> ilutex: comprobar dependencias de la GUI y la bandeja"
# El binario necesita un Python con PyGObject: el primero que lo tenga.
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
"$PY_GTK" -c 'import gi; gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1"); from gi.repository import AyatanaAppIndicator3; import cairo' >/dev/null 2>&1 || tray_ok=0
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
    local backup="${HOME}/.config/waybar.ilutex-backup-$(date +%Y%m%d%H%M%S)"
    mv "${HOME}/.config/waybar" "$backup" 2>/dev/null \
      && echo "    barra waybar apartada en $backup (Omarchy ya tiene la suya)"
  fi
  if pgrep -x waybar >/dev/null 2>&1; then
    pkill -x waybar 2>/dev/null && echo "    proceso waybar detenido (duplicaba la barra)"
  fi
}

# ¿Hay un host de bandeja para el icono? Se ajusta por escritorio.
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

# Extensión GNOME solo fuera de Omarchy/Hyprland (allí la bandeja es del shell).
gnome_desktop=0
[ "$(pkg_manager)" = pacman ] && [ ! -d /usr/share/omarchy ] \
  && [ "${XDG_CURRENT_DESKTOP:-}" != "Hyprland" ] && gnome_desktop=1
if [ "$tray_ok" = 0 ] && [ "$tray_host_ok" = 1 ] && [ "$gnome_desktop" = 1 ]; then
  echo "==> ilutex: instalar gnome-shell-extension-appindicator (root)"
  if sudo pacman -S --needed --noconfirm gnome-shell-extension-appindicator; then
    echo "==> ilutex: extensión AppIndicator instalada; recarga GNOME Shell (Alt+F2 \"r\" + Enter) o reinicia sesión" >&2
  else
    echo "    aviso: no se pudo instalar gnome-shell-extension-appindicator" >&2
  fi
fi

if in_ilutex_group; then
  echo "OK: ilutex instalado. Prueba con: ilutex info"
else
  echo "OK: ilutex instalado (binarios/udev/candado)."
  echo "    Escritura HID pendiente de autorización (grupo ilutex). Ver mensajes arriba."
  echo "    Consulta sin escribir: ilutex info"
fi