#!/usr/bin/env bash
# Instala el CLI (binario) y ficheros root: udev, sysusers, tmpfiles.
# Requiere sudo en instalación viva. Sin sudo con ILUTEX_ROOT=/ruta (offline).
# No instala GUI ni unidades de usuario (ver install-gui.sh).
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/install-common.sh
. "${SCRIPTS_DIR}/install-common.sh"
resolve_install_paths "$SCRIPTS_DIR"

BIN_DST="${HOME}/.local/bin"

# Copia un fichero root con `install -D`. En instalación viva usa sudo; en
# modo offline (stage_root) escribe bajo el root alternativo como este usuario.
install_root_file() {
  local src="$1" dst="$2" label="$3"
  if [ -n "$stage_root" ]; then
    if ! install -D -m644 "$src" "${stage_root}${dst}"; then
      echo "    error: no se pudo instalar ${label}" >&2
      return 1
    fi
  elif ! sudo install -D -m644 "$src" "$dst"; then
    echo "    error: no se pudo instalar ${label}" >&2
    return 1
  fi
}

run_root() {
  local label="$1"
  shift
  if ! sudo "$@"; then
    echo "    error: ${label} falló" >&2
    return 1
  fi
}

# Crea el candado en el root offline, sin chown: la propiedad root:ilutex la
# fija después quien instale el root como root. Funciona sin systemd.
stage_writer_lock() {
  install -d -m770 "$stage_root/run/ilutex"
  install -m660 /dev/null "$stage_root/run/ilutex/writer.lock"
}

install_root_files() {
  # Origen privilegiado para pkexec (GUI): /usr/lib/udev/rules.d/70-ilutex.rules.
  # Destino activo: /etc/udev/rules.d/70-ilutex.rules. No se usa ~/.local para elevar.
  local udev_src="${ILUTEX_TREE}/packaging/udev/70-ilutex.rules"
  echo "==> ilutex: regla udev (opcional, root)"
  if [ "${ILUTEX_SKIP_UDEV:-0}" = "1" ]; then
    echo "    omitida (ILUTEX_SKIP_UDEV=1)"
    udev_ok=1
  else
    udev_ok=1
    install_root_file \
      "$udev_src" \
      /usr/lib/udev/rules.d/70-ilutex.rules \
      "udev/70-ilutex.rules (packaged /usr/lib)" || udev_ok=0
    install_root_file \
      "$udev_src" \
      /etc/udev/rules.d/70-ilutex.rules \
      "udev/70-ilutex.rules (/etc)" || udev_ok=0
    if [ -z "$stage_root" ]; then
      run_root "udevadm control --reload" udevadm control --reload || udev_ok=0
      run_root "udevadm trigger" udevadm trigger --subsystem-match=hidraw || udev_ok=0
    fi
    if [ "$udev_ok" = 1 ]; then
      echo "==> ilutex: regla udev instalada (root; origen /usr/lib + activo /etc)"
    else
      echo "==> ilutex: regla udev incompleta" >&2
    fi
  fi

  echo "==> ilutex: candado de escritura (root)"
  writer_lock_ok=1
  install_root_file \
    "${ILUTEX_TREE}/packaging/sysusers.d/ilutex.conf" \
    /usr/lib/sysusers.d/ilutex.conf \
    "sysusers.d/ilutex.conf" || writer_lock_ok=0
  install_root_file \
    "${ILUTEX_TREE}/packaging/tmpfiles.d/ilutex.conf" \
    /usr/lib/tmpfiles.d/ilutex.conf \
    "tmpfiles.d/ilutex.conf" || writer_lock_ok=0
  if [ -n "$stage_root" ]; then
    if command -v systemd-sysusers >/dev/null 2>&1; then
      systemd-sysusers --root="$stage_root" ilutex.conf >/dev/null 2>&1 || true
    fi
    stage_writer_lock
  else
    if command -v systemd-sysusers >/dev/null 2>&1; then
      run_root "systemd-sysusers ilutex.conf" systemd-sysusers ilutex.conf || writer_lock_ok=0
    else
      echo "    aviso: systemd-sysusers no disponible; crea el grupo ilutex a mano" >&2
      writer_lock_ok=0
    fi
    if command -v systemd-tmpfiles >/dev/null 2>&1; then
      run_root "systemd-tmpfiles --create ilutex.conf" systemd-tmpfiles --create ilutex.conf || writer_lock_ok=0
    else
      echo "    aviso: systemd-tmpfiles no disponible; crea /run/ilutex a mano" >&2
      writer_lock_ok=0
    fi
  fi
  if [ -n "$stage_root" ]; then
    if [ ! -d "$stage_root/run/ilutex" ] || [ ! -e "$stage_root/run/ilutex/writer.lock" ]; then
      echo "    error: falta run/ilutex/writer.lock en ILUTEX_ROOT" >&2
      writer_lock_ok=0
    fi
  else
    if [ ! -d /run/ilutex ] || [ ! -e /run/ilutex/writer.lock ]; then
      echo "    error: falta /run/ilutex/writer.lock tras tmpfiles" >&2
      writer_lock_ok=0
    fi
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
}

# Instalación offline: solo ficheros root, sin compilar ni tocar la sesión.
if [ -n "$stage_root" ]; then
  echo "==> ilutex: instalación offline en ${stage_root} (solo ficheros root)"
  install_root_files
  if [ "${writer_lock_ok:-0}" = 1 ] && [ "${udev_ok:-1}" = 1 ]; then
    echo "OK: ficheros root instalados en ${stage_root}"
    exit 0
  fi
  echo "FALLO: instalación offline incompleta" >&2
  exit 1
fi

if [ -n "${ILUTEX_RELEASE_DIR:-}" ]; then
  if [ ! -x "${ILUTEX_BIN_SRC}" ]; then
    echo "error: falta binario precompilado en ${ILUTEX_BIN_SRC}" >&2
    exit 1
  fi
  echo "==> ilutex: usar binario de release (${ILUTEX_BIN_SRC})"
else
  echo "==> ilutex: compilar (release)"
  cargo build --release --manifest-path "${ILUTEX_TREE}/Cargo.toml"
fi

echo "==> ilutex: instalar binario en ${BIN_DST}/ilutex"
mkdir -p "${BIN_DST}"
install -m755 "${ILUTEX_BIN_SRC}" "${BIN_DST}/ilutex"

# Aviso si otro ilutex gana en PATH (shim mise, /usr/bin, …) con otra versión.
warn_shadowed_ilutex() {
  local resolved path_ver installed_ver
  resolved="$(command -v ilutex 2>/dev/null || true)"
  [ -n "$resolved" ] || return 0
  if [ "$(readlink -f "$resolved" 2>/dev/null || echo "$resolved")" = \
       "$(readlink -f "${BIN_DST}/ilutex" 2>/dev/null || echo "${BIN_DST}/ilutex")" ]; then
    return 0
  fi
  installed_ver="$("${BIN_DST}/ilutex" --version 2>/dev/null | awk '{print $NF}' || true)"
  path_ver="$("$resolved" --version 2>/dev/null | awk '{print $NF}' || true)"
  [ -n "$installed_ver" ] && [ -n "$path_ver" ] || return 0
  if [ "$path_ver" != "$installed_ver" ]; then
    echo "AVISO: ilutex ${path_ver} en ${resolved} sombrea ${BIN_DST}/ilutex ${installed_ver}" >&2
  fi
}
warn_shadowed_ilutex

install_root_files

# Instalación viva: root incompleto → exit ≠ 0 y sin "OK:" (evita falso positivo).
# ILUTEX_SKIP_UDEV=1 y «no estar en el grupo ilutex» no cuentan como fallo.
if [ "${writer_lock_ok:-0}" != 1 ] || [ "${udev_ok:-1}" != 1 ]; then
  echo "FALLO: instalación incompleta (sección root)" >&2
  echo "    Revisa sudo (udev/sysusers/tmpfiles) o usa ILUTEX_ROOT=/ruta para offline." >&2
  exit 1
fi

echo "==> ilutex: migrar estado heredado kbd-rgb/keybackcon (si existe)"
for d in "${XDG_STATE_HOME:-${HOME}/.local/state}" "${HOME}/.local/state"; do
  if [ -f "$d/kbd-rgb/state" ] && [ ! -f "$d/ilutex/state" ]; then
    mkdir -p "$d/ilutex"
    cp "$d/kbd-rgb/state" "$d/ilutex/state"
    echo "    migrado $d/kbd-rgb/state -> $d/ilutex/state"
    break
  fi
  if [ -f "$d/keybackcon/state" ] && [ ! -f "$d/ilutex/state" ]; then
    mkdir -p "$d/ilutex"
    cp "$d/keybackcon/state" "$d/ilutex/state"
    echo "    migrado $d/keybackcon/state -> $d/ilutex/state"
    break
  fi
done

if in_ilutex_group; then
  echo "OK: ilutex CLI instalado. Prueba con: ilutex info"
else
  echo "OK: ilutex CLI instalado (binario/udev/candado)."
  echo "    Escritura HID pendiente de autorización (grupo ilutex). Ver mensajes arriba."
  echo "    Consulta sin escribir: ilutex info"
fi
