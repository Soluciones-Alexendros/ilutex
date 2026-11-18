# Guía: calidad y jobs de CI

## Jobs del pipeline principal

| Job | Qué hace |
| --- | -------- |
| `quality` | `gitleaks` CLI (binario pinado + checksum SHA256; sin `gitleaks-action` ni licencia org); `cargo fmt --check`; `clippy --all-targets -D warnings` (+ `clippy::cognitive_complexity`); rustdoc `-D warnings`; `cargo audit` (versión pinada en el runner); lockfile solo-`ilutex` (ADR 2); `py_compile gui/*.py`; `scripts/check-gui-imports.py` + unittest del checker; shellcheck; i18n; suite GUI con xvfb |
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
| Code Scanning (default setup) | CodeQL del repo (GitHub); no hay `codeql.yml` advanced — choca con default setup |
| `scorecard.yml` | OpenSSF Scorecard en `main` y cron semanal (`publish_results: true` hacia OpenSSF; sin upload SARIF a Code Scanning — choca con default setup) |

`release.yml` (tag `v*`) sigue aparte: `cargo test/build --locked`, suite Python (unittest + xvfb como `quality`), smoke, `.deb`, SBOM, `SHA256SUMS` + firma GPG (`SHA256SUMS.asc`), attestation de procedencia. Exporta `SOURCE_DATE_EPOCH` desde el commit del tag (no afirma builds bit a bit).

## Complejidad cognitiva

`clippy::cognitive_complexity` está **activado** en el job `quality` (`-W clippy::cognitive_complexity` junto a `-D warnings`). El árbol en el momento de activarlo pasaba sin avisos.

## Hooks locales

[`.pre-commit-config.yaml`](../../.pre-commit-config.yaml) solo usa hooks `repo: local`: `cargo fmt --check` y `shellcheck` sobre `scripts/` y `packaging/`. Clippy no va en pre-commit (sigue en CI).

## Cobertura

No hay `llvm-cov` ni umbral porcentual en CI (cero dependencias, ADR 2 y 10). El mínimo de flota (≥ 70 %) se cubre con los tests de `cargo test` más el smoke. No se baja la barra de clippy/rustdoc para “arreglar” un porcentaje.

Fachada local: `make lint`, `make test`, `make smoke`, `make validate`.
