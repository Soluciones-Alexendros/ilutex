#!/usr/bin/env bash
# Compara la versión de Cargo.toml con artefactos instalados (usuario y sistema).
# Sin artefactos → not_applicable (exit 0). Drift → exit 1 con detalle por línea.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cargo_version=$(sed -nE 's/^version *= *"([^"]+)".*/\1/p' "${REPO_DIR}/Cargo.toml" | head -1)
[ -n "$cargo_version" ] || { echo "FALLO: Cargo.toml sin versión" >&2; exit 1; }

fail=0
seen=0

bin_version() {
  local bin="$1"
  "$bin" --version 2>/dev/null | awk '{print $NF}'
}

check_bin() {
  local path="$1" label="$2"
  [ -x "$path" ] || return 0
  seen=1
  local ver
  ver="$(bin_version "$path" || true)"
  if [ "$ver" = "$cargo_version" ]; then
    echo "ok: ${label} ${path} = ${ver}"
  else
    echo "drift: ${label} ${path} = ${ver:-?} (Cargo ${cargo_version})" >&2
    fail=1
  fi
}

# ExecStart=/ruta/ilutex … → comprobar que el binario del ExecStart coincide.
check_unit_exec() {
  local unit="$1"
  [ -f "$unit" ] || return 0
  seen=1
  local exec_line bin ver
  exec_line="$(grep -E '^ExecStart=' "$unit" | head -1 || true)"
  bin="${exec_line#ExecStart=}"
  bin="${bin%% *}"
  if [ -z "$bin" ] || [ ! -x "$bin" ]; then
    echo "drift: unidad ${unit} ExecStart=${bin:-vacío} no ejecutable" >&2
    fail=1
    return 0
  fi
  ver="$(bin_version "$bin" || true)"
  if [ "$ver" = "$cargo_version" ]; then
    echo "ok: unidad ${unit} → ${bin} = ${ver}"
  else
    echo "drift: unidad ${unit} → ${bin} = ${ver:-?} (Cargo ${cargo_version})" >&2
    fail=1
  fi
}

# Exec=/ruta/ilutex-gui → versionar vía lanzador --version.
check_desktop_exec() {
  local desk="$1"
  [ -f "$desk" ] || return 0
  seen=1
  local exec_line bin ver
  exec_line="$(grep -E '^Exec=' "$desk" | head -1 || true)"
  bin="${exec_line#Exec=}"
  bin="${bin%% *}"
  if [ -z "$bin" ]; then
    echo "drift: desktop ${desk} sin Exec=" >&2
    fail=1
    return 0
  fi
  # Ruta relativa (plantilla): no se puede comparar sin PATH; avisar.
  if [[ "$bin" != /* ]]; then
    echo "drift: desktop ${desk} Exec=${bin} no es ruta absoluta" >&2
    fail=1
    return 0
  fi
  if [ ! -x "$bin" ]; then
    echo "drift: desktop ${desk} Exec=${bin} no ejecutable" >&2
    fail=1
    return 0
  fi
  ver="$("$bin" --version 2>/dev/null | awk '{print $NF}' || true)"
  if [ "$ver" = "$cargo_version" ]; then
    echo "ok: desktop ${desk} → ${bin} = ${ver}"
  else
    echo "drift: desktop ${desk} → ${bin} = ${ver:-?} (Cargo ${cargo_version})" >&2
    fail=1
  fi
}

echo "Cargo.toml: ${cargo_version}"

check_bin "${HOME}/.local/bin/ilutex" "usuario"
check_bin /usr/bin/ilutex "sistema"

UNIT_DST="${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
for unit in ilutex.service ilutex-tray.service ilutex-animation@.service; do
  check_unit_exec "${UNIT_DST}/${unit}"
done

check_desktop_exec "${HOME}/.local/share/applications/ilutex.desktop"
check_desktop_exec /usr/share/applications/ilutex.desktop

if [ "$seen" -eq 0 ]; then
  echo "not_applicable: sin artefactos instalados (usuario ni sistema)"
  exit 0
fi

if [ "$fail" -ne 0 ]; then
  echo "FALLO: drift entre Cargo (${cargo_version}) y lo instalado" >&2
  exit 1
fi
echo "OK: artefactos instalados alineados con Cargo (${cargo_version})"
exit 0
