# Contribuir a ilutex

Idioma: este fichero, `README.md` y `docs/guides|runbooks` en español.

Lee también [AGENTS.md](AGENTS.md), [ARCHITECTURE.md](ARCHITECTURE.md) y [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Setup

```bash
# Rust ≥ 1.87 (MSRV) + rustfmt + clippy
# Python 3 (GUI; py_compile no necesita GTK en CI)
make lint && make test
```

Hooks opcionales (fmt/clippy/shellcheck locales + repos del informe):

```bash
pre-commit install
```

Detalle en [`docs/guides/desarrollo.md`](docs/guides/desarrollo.md).

## Flujo de trabajo

Rama `feat/*` / `fix/*` / `docs/*` / `chore/*` → PR → squash → merge a `main`. Los tags `vX.Y.Z` los lanza el mantenedor; `release.yml` publica artefactos.

### Política de merge (H-08)

- `main` está **protegida**: no se hace push directo de trabajo ordinario.
- Todo cambio entra por **pull request** con **review** del owner en [`.github/CODEOWNERS`](.github/CODEOWNERS) (`* @Alexendros`) y con los checks de CI en verde (`quality`, `test`, `build`, `smoke`; más `msrv` cuando aplique).
- El merge preferido es **squash**. La hoja de ruta publicada vive en [`docs/ROADMAP.md`](docs/ROADMAP.md).

**Bloqueo CODEOWNERS:** el informe pedía un segundo login de GitHub como CODEOWNER. Sin un handle real confirmado por el operador, [`.github/CODEOWNERS`](.github/CODEOWNERS) permanece en `* @Alexendros` (no se inventa un segundo owner).

La protección de rama y los required checks se configuran en GitHub (settings del repo); este documento declara la política, no inspecciona el panel.

## Antes de un PR

```bash
make validate
```

Equivale a `lint` + `test` + `smoke`. El job `build` del CI es `cargo build --release`.

## Reglas

- Tocar `src/protocol.rs`, ioctl o informes HID → ADR en [`docs/architecture/decisions/DECISIONS.md`](docs/architecture/decisions/DECISIONS.md).
- No añadas crates de producción al CLI (`[dependencies]`; ADR 2) sin
  confirmación. `criterion` en `[dev-dependencies]` es la única excepción
  documentada (ADR 2/10 enmendados).
- Coverage: no hay gate `llvm-cov`; no lo inventes. Los 27 tests + smoke son el contrato.
- No commitear `target/`, `__pycache__/`, `TASKS.md` ni secretos.
- Nuevos comandos CLI → documentar en `README.md` y, si cambia el contrato, ADR.
- Vulnerabilidades: [SECURITY.md](SECURITY.md), no un issue público.
