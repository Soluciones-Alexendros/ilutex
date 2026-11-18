#!/usr/bin/env bash
# Verifica que install.sh sale ≠ 0 y no imprime "OK:" cuando sudo falla.
# Antepone un sudo falso al PATH; HOME temporal para no tocar ~/.local.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_home="${HOME}"
fake_bin="$(mktemp -d)"
fake_home="$(mktemp -d)"
cleanup() {
  rm -rf "$fake_bin" "$fake_home"
}
trap cleanup EXIT

cat > "${fake_bin}/sudo" <<'EOF'
#!/bin/sh
echo "sudo: a terminal is required to read the password" >&2
exit 1
EOF
chmod +x "${fake_bin}/sudo"

# Binario ya compilado: evita rebuild lento; si falta, cargo build previo.
if [ ! -x "${REPO_DIR}/target/release/ilutex" ]; then
  if ! command -v cargo >/dev/null 2>&1; then
    echo "not_run: sin cargo ni target/release/ilutex (no se puede ejercitar install.sh)" >&2
    exit 0
  fi
  cargo build --release --manifest-path "${REPO_DIR}/Cargo.toml" >/dev/null
fi

# Stub de cargo: el job smoke de CI trae el artefacto pero no rustup.
# install.sh siempre llama a cargo build; con el binario ya presente basta.
real_cargo="$(command -v cargo || true)"
cat > "${fake_bin}/cargo" <<EOF
#!/bin/sh
if [ -x "${REPO_DIR}/target/release/ilutex" ]; then
  echo "    Finished \`release\` profile (stub: binario ya presente)" >&2
  exit 0
fi
if [ -n "${real_cargo}" ] && [ -x "${real_cargo}" ]; then
  exec "${real_cargo}" "\$@"
fi
echo "cargo: no disponible" >&2
exit 127
EOF
chmod +x "${fake_bin}/cargo"

# HOME falso aísla ~/.local; cargo/rustup siguen en el home real.
out="$(mktemp)"
err="$(mktemp)"
# XDG_* del host apuntarían a ~/.config real; forzar prefijos bajo fake_home.
set +e
run_install=(bash "${REPO_DIR}/scripts/install.sh")
if command -v stdbuf >/dev/null 2>&1; then
  run_install=(stdbuf -oL -eL bash "${REPO_DIR}/scripts/install.sh")
fi
HOME="$fake_home" \
  XDG_CONFIG_HOME="${fake_home}/.config" \
  XDG_DATA_HOME="${fake_home}/.local/share" \
  XDG_STATE_HOME="${fake_home}/.local/state" \
  CARGO_HOME="${CARGO_HOME:-${real_home}/.cargo}" \
  RUSTUP_HOME="${RUSTUP_HOME:-${real_home}/.rustup}" \
  PATH="${fake_bin}:${PATH}" \
  "${run_install[@]}" >"$out" 2>"$err"
rc=$?
set -e

fail=0
if [ "$rc" -eq 0 ]; then
  echo "FALLO: install.sh salió 0 con sudo falso" >&2
  fail=1
fi
if [ "$rc" -lt 1 ] || [ "$rc" -gt 2 ]; then
  echo "FALLO: código de salida esperado 1–2, obtuvo ${rc}" >&2
  fail=1
fi
if grep -q '^OK:' "$out"; then
  echo "FALLO: stdout contiene OK: pese a root fallido" >&2
  fail=1
fi
if ! grep -qE 'incompleta|FALLO:' "$err"; then
  echo "FALLO: stderr sin mensaje de instalación incompleta" >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "--- stdout ---" >&2
  cat "$out" >&2
  echo "--- stderr ---" >&2
  cat "$err" >&2
  rm -f "$out" "$err"
  exit 1
fi
rm -f "$out" "$err"
echo "ok: install.sh con sudo falso sale ${rc} sin OK:"
exit 0
