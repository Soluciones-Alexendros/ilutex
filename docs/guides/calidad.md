# Guía: calidad y jobs de CI

## Jobs del pipeline principal

| Job | Qué hace |
| --- | -------- |
| `quality` | `gitleaks` CLI (binario pinado + checksum SHA256) + `gitleaks/gitleaks-action` pinado por SHA si existe el secret `GITLEAKS_LICENSE` (requerido en orgs); `cargo fmt --check`; `clippy --all-targets -D warnings` (+ `clippy::cognitive_complexity`); rustdoc `-D warnings`; `cargo audit` (versión pinada); `cargo tarpaulin --fail-under 70` (pinado; excluye `packaging/`/`examples/`/`benches/`/`src/main.rs`); lockfile: versión `ilutex` alineada y `[dependencies]` vacío (ADR 2; el lock MAY incluir el árbol de `criterion` en `[dev-dependencies]`); `py_compile gui/*.py`; `scripts/check-gui-imports.py` + unittest del checker; shellcheck; i18n; suite GUI con `HOME` temporal, `unshare -rn`, `dbus-run-session` y xvfb |
| `test` | `cargo test --locked -- --test-threads=1` y `cargo run --release --example bench_colors` (sale 0; sin umbral de tiempo) |
| `test-arm64` | `cargo test --locked` en `ubuntu-24.04-arm` (entra en `ci-gate`) |
| `build` | `cargo build --release --locked` y artefacto del binario |
| `smoke` | `scripts/smoke.sh`: `--version`/`--help`, GUI, udev, systemd, i18n, schema |
| `ci-gate` | Agrega `quality` + `test` + `test-arm64` + `msrv` + `build` + `smoke`; falla si alguno no es `success` o si el PR lleva etiqueta `hold` |

El job extra `msrv` comprueba toolchain 1.87. No es required-name del canon; se conserva porque el crate declara `rust-version = "1.87"`.

Disparadores: `pull_request` (todas las ramas), `push` solo a `main`, y `workflow_dispatch`. Así un push a la rama de un PR no abre un segundo run paralelo al del evento `pull_request`. La concurrencia agrupa por SHA del head.

Workflows aparte (no bloquean `ci-gate`):

| Workflow | Qué hace |
| --- | -------- |
| `benchmark.yml` | `cargo bench` (criterion) de camino puro; en PRs compara baseline contra `main` si esa rama ya tiene los benches. **No** exige AERO X16 ni el presupuesto p95 de 50 ms de `ilutex set` (medición manual; ver [`desarrollo.md`](desarrollo.md)) |
| Code Scanning (default setup) | CodeQL del repo (GitHub), cron semanal, incluye `rust`. Es el camino activo hoy. |
| `codeql.yml` | Advanced CodeQL para Rust (SHA pinados, cron semanal). **Choca con default setup**: solo corre si `vars.CODEQL_ADVANCED=1` tras desactivar default setup. |
| `scorecard.yml` | OpenSSF Scorecard en `main` y cron semanal (`publish_results: true` hacia OpenSSF; sin upload SARIF a Code Scanning — choca con default setup) |

`release.yml` (tag `v*`) sigue aparte: `cargo test/build --locked`, suite Python (unittest + xvfb como `quality`), smoke, `.deb`, SBOM, `SHA256SUMS` + firma GPG (`SHA256SUMS.asc`) + cosign keyless (`SHA256SUMS.sigstore.json`), attestation de procedencia. Exporta `SOURCE_DATE_EPOCH` desde el commit del tag (no afirma builds bit a bit).

## Complejidad cognitiva

`clippy::cognitive_complexity` está **activado** en el job `quality` (`-W clippy::cognitive_complexity` junto a `-D warnings`). El árbol en el momento de activarlo pasaba sin avisos.

## Hooks pre-commit

[`.pre-commit-config.yaml`](../../.pre-commit-config.yaml) combina:

- `doublify/pre-commit-rust` (`rev: v1.0`): `fmt --check`, `cargo-check`, `clippy -D warnings`
- `shellcheck-py/shellcheck-py` (`rev: v0.10.0.1`): `shellcheck` sobre ficheros shell del commit
- hooks `repo: local`: `cargo fmt --check` y `shellcheck` acotado a `scripts/` y `packaging/`

Instalación: `pre-commit install` (documentado en [`CONTRIBUTING.md`](../../CONTRIBUTING.md)). Clippy en CI (`quality`) sigue siendo el gate de flota.

## Cobertura

El job `quality` ejecuta `cargo tarpaulin --fail-under 70` (versión pinada en el workflow). Se excluyen `packaging/`, `examples/`, `benches/` y el entrypoint `src/main.rs` del denominador. No se baja el umbral: si cae, se añaden tests. Badge de cobertura: opcional, no requerido.

Fachada local: `make lint`, `make test`, `make smoke`, `make validate`.
