# Changelog

La fuente de verdad son los tags y `git-cliff`. Resumen:

## [Unreleased]

## [3.1.1] — 2026-11-18
- **Instalador veraz.** Si la sección root (udev/sysusers/tmpfiles) falla, el
  script sale distinto de 0 y no imprime `OK:` (evita el falso positivo con
  `sudo` sin TTY). Avisa si otro `ilutex` en el `PATH` sombrea el binario
  recién instalado con una versión distinta. Unidades de usuario y `.desktop`
  solo se reescriben si el contenido cambia (mtime estable; `daemon-reload`
  solo cuando hace falta).
- **Diagnóstico GUI.** `ilutex-gui --version` (lanzador y `gui/main.py`)
  imprime la versión sin cargar GTK. El smoke elige un Python con PyGObject
  (o declara `not_run` explícito).
- **Desktop con Exec absoluto** en la instalación de usuario y en los
  `package()` de AUR/omarchy; la plantilla del repo sigue siendo
  `Exec=ilutex-gui` para `desktop-file-validate`.
- **Gate de lo instalado.** `make check-installed` compara `Cargo.toml` con
  binarios, unidades y `.desktop` presentes.

## [3.1.0] — 2026-11-17
- **Instalación offline.** `ILUTEX_ROOT=/ruta ./scripts/install.sh` escenifica
  los ficheros root (udev, sysusers, tmpfiles) y el candado `run/ilutex/writer.lock`
  (modos `0770`/`0660`) en un root alternativo, sin sudo, sin `udevadm` y sin
  depender de systemd: pensado para contenedores, chroots e imágenes. La
  instalación viva no cambia.
- **Instalador más legible.** Los bloques repetitivos de `sudo install` pasan a
  `install_root_file`/`run_root`/`stage_writer_lock` y la sección root a
  `install_root_files()`. El smoke cubre el árbol offline.

## [3.0.4] — 2026-11-17
- **La bandeja la gestiona el instalador.** Nueva unidad de usuario
  `ilutex-tray.service` (`ilutex-gui --tray`), única fuente de arranque: el
  instalador la habilita y aparta el `.desktop` XDG antiguo, y el interruptor
  «Abrir al iniciar sesión» de Preferencias gestiona esa misma unidad en vez de
  crear un duplicado (dos bandejas en la barra).
- **Omarchy sin duplicar la barra.** Su barra es Quickshell y ya trae el widget
  `omarchy.tray`; el instalador lo comprueba (y lo añade si falta), deja de
  sugerir Waybar y aparta con respaldo cualquier `~/.config/waybar` propio,
  deteniendo el proceso si estaba duplicando la barra.
- **Arreglo de las unidades en instalación local.** Apuntaban a `/usr/bin` y el
  instalador solo sustituía el placeholder, así que `restore` y la bandeja
  fallaban en una instalación en `~/.local/bin`. Ahora reescribe también esas
  rutas.
- **Habilitar en instalación nueva.** `disabled` en una unidad recién instalada
  ya no se confunde con una decisión del usuario: la unidad se habilita salvo
  `masked` o desactivación explícita previa. Se elige un Python con PyGObject
  para las comprobaciones, así no hay avisos falsos de dependencias.
- Pruebas: cinco casos nuevos cubren la regla de fuente única de arranque.

## [3.0.3] — 2026-11-16
- **Barrido del nombre anterior.** Se eliminan los residuos de `keybackcon`:
  variables de entorno de pruebas y del postinstalador (`KEYBACKCON_*` →
  `ILUTEX_*`), placeholder de las unidades (`__KEYBACKCON_BIN__` →
  `__ILUTEX_BIN__`), clases de la GUI (`KeybackconClient/Error` →
  `IlutexClient/Error`) y decenas de rutas y nombres en la documentación y
  en `MANIFEST.txt`. Se corrige el App ID documentado
  (`org.iniciativas.*` → `org.alexendros.ilutex`).
- **Migración intacta y vigilada.** Se conserva la lectura del estado y los
  pidfiles heredados, los binarios antiguos reconocidos y los
  `conflicts/replaces` de los paquetes. Nuevo
  `scripts/check-legacy-names.py`, en `make smoke` y en el job `quality`, que
  rechaza cualquier residuo y comprueba que esas rutas heredadas siguen
  existiendo.
- Catálogos: cabeceras al día (versión y mantenedor) regeneradas con
  `make i18n`.

## [3.0.2] — 2026-11-16
- **Arreglo del paquete npm.** Los índices de `ilutex-linux-x64` e
  `ilutex-linux-arm64` exportaban `bin/keybackcon` (nombre anterior al
  renombrado), así que el postinstalador no encontraba el binario y se
  saltaba udev y las unidades de usuario con un aviso engañoso. Ahora
  exportan `bin/ilutex`, que es lo que declara `files`.
- Nuevo `scripts/check-npm-platforms.py`, enganchado a `make smoke` y al job
  `quality`, que falla si un índice de plataforma no coincide con el
  binario declarado o menciona un nombre anterior.

## [3.0.1] — 2026-11-16
- **Otros teclados LampArray.** `ILUTEX_VID`, `ILUTEX_PID` e
  `ILUTEX_HID_SIGNATURE` sobrescriben la detección del AERO X16 sin
  recompilar; un valor inválido cae al de fábrica. Documentado en
  `README.md` y `docs/guides/desarrollo.md`.
- Calidad: cada `#[allow]` de clippy justifica su motivo y `save_state`
  documenta que es API pública, sin cambios de comportamiento. Cuatro
  pruebas nuevas cubren los overrides por entorno.
- AUR: `sha256sums` deja de ser `SKIP` y se añade el `.SRCINFO`
  generado, requisito para publicar la receta.

## [3.0.0] — 2026-11-14
- **Cambio de nombre: el producto pasa a llamarse iLutex.** El binario, el
  paquete, el app-id y las rutas cambian con él: `ilutex`, `ilutex-gui`,
  `org.alexendros.ilutex` (D-Bus y GSettings), grupo `ilutex`, candado
  `/run/ilutex/writer.lock`, estado en `~/.local/state/ilutex/state` y
  pidfile en `$XDG_RUNTIME_DIR/ilutex/animation.pid`. El estado de `kbd-rgb`
  y de `keybackcon` se sigue leyendo; `ilutex` sustituye a `keybackcon` al
  instalarse.
- Omarchy: el acento sale de `~/.local/state/omarchy/current/theme/colors.toml`
  y se vigila en vivo, así que cambiar de tema repinta la ventana sin
  reiniciar; nuevo filtro «Seguir escritorio» que aplica ese acento al
  teclado.
- Omarchy: el idioma se resuelve desde `~/.config/omarchy/language` (con el
  locale como respaldo), se vigila y re-traduce la ventana en vivo.
- Teclado: `?` abre la tabla de atajos, `Q` sale preguntando si hay un cambio
  pendiente y Enter/Espacio aplican luz continua.
- Accesibilidad: el estado es una live region, el movimiento forma un grupo
  radio, el brillo anuncia su valor al moverse, los filtros se recorren con
  las flechas y las pistas suben a contraste AA. Matriz en
  `docs/runbooks/accesibilidad.md`.
- Versionado: `scripts/check-version.sh` compara Cargo, npm, tag y CHANGELOG,
  y el release aborta si divergen; las dependencias opcionales de npm pasan a
  viajar en la misma versión que el paquete.
- Empaquetado: receta de `omacom/omarchy-pkgs` en `packaging/omarchy-pkgs/`,
  con tests de layout, udev, modos del candado, unidades y `.desktop`.
- GUI: constantes compartidas en `gui/constants.py`.

## [2.5.0] — 2026-10-18
- GUI i18n real: msgids en inglés (idioma fuente) y catálogos completos
  `es.po`/`en.po`; los nombres de color se traducen en el punto de uso (`N_`)
  y los errores de `client.py`/`backend.py` dejan de estar sin envolver.
  El `.pot` se regenera con `make i18n` y `make check-i18n` detecta deriva
  fuente → `.pot` → `.po` (ADR 14).
- Tests del control D-Bus de la ventana (`Toggle`/`Present`/`Quit`) con un
  bus de sesión privado, sin tocar el bus del usuario (66 tests de GUI).
- Release: `version.yml` idempotente cuando el PR de release ya existe y
  `gui/locale/` + `tasks/` fuera del árbol versionado.

## [2.4.1] — 2026-10-17
- `getgrnam` portable (aarch64); paquete npm publicado.

## [2.4.0] — 2026-10-17
- Un solo escritor HID con candado en `/run/keybackcon/writer.lock` (ADR 13);
  tag en la historia de `main` y release con `.deb` + tarball + SBOM.

## [2.3.0] — 2026-09-25
- Núcleo: parada de animación sin bloqueos (reap de zombies, semántica de
  stop unificada), estado persistente atómico, validación estricta de
  argumentos, `info --json` estable para la GUI y cap de FPS a 60.
- GUI: ventana Adwaita reestructurada (grupos Movimiento/Brillo/Color,
  píldora de estado), apertura instantánea desde la bandeja vía control
  D-Bus y bandeja rediseñada con cierre limpio.
- Calidad: 33 tests Rust y 47 tests unitarios de la GUI (`gui/tests/`),
  integrados en `smoke.sh` y CI; `gui/compat.py` con preflight
  multi-distribución (apt/pacman/dnf/zypper).
- Packaging: `ExecStopPost=keybackcon stop`, `Restart=on-failure` en la
  unidad de restauración e `install.sh` respeta la unidad desactivada.
- CI/CD: autoversionado con git-cliff (bump desde commits convencionales,
  PR de release en auto-merge y tag), publicación npm (`keybackcon` +
  `keybackcon-linux-x64`/`linux-arm64`) y org migrada a
  Soluciones-Alexendros.

## [2.2.1] — 2026-09-24
- Unidades systemd del paquete apuntan a `/usr/bin/keybackcon` (restore al
  iniciar sesión en `.deb`/AUR); `install.sh` las reescribe a `~/.local/bin`.
- Instalación udev vía `pkexec` pasa rutas por `$1`/`$2` (sin interpolar en
  `sh -c`).
- CLI: `firmware-effects` solo acepta `on`/`off`; brillo relativo `+N`/`-N`
  rechaza sufijos no numéricos (`+`/`-` solos siguen siendo ±10).
- CI: job MSRV con toolchain 1.87 además de stable.

## [2.2.0] — 2026-09-14
- Comando `restore`: detiene animación y reaplica color+brillo guardados;
  el servicio de usuario lo ejecuta al iniciar sesión para restaurar el color.
- Lanzador GUI por paquete (`packaging/keybackcon-gui`): localiza `gui/` y lo
  ejecuta; mismo esquema en `.deb`, AUR, `install.sh` y release.
- GUI acabada: bandeja Ayatana (`--tray`) con menú e icono dinámico, temas
  claro/oscuro, vista previa con partículas, ajustes, autostart opt-in e i18n
  en castellano (gettext).
- Calidad/empaquetado: MSRV 1.87 declarada, GUI a `optdepends` en AUR y
  `hid_ioctl_request` acotado a 0x3FFF (14 bits de `_IOC_SIZEBITS`).

## [2.1.0] — 2026-09-14
- Robustez HID: transporte abstracto testeable, ioctls con longitud validada
  y `SAFETY`, pidfile atómico, parada limpia por SIGINT/SIGTERM y aviso de
  desconexión del dispositivo.
- CLI estructurada sin dependencias (`Command`/`Error`), mismos comandos,
  alias, mensajes y códigos de salida; tests movidos junto a su módulo.
- Protocolo LampArray centralizado en `src/protocol.rs` (constantes,
  constructores y parser) con la spec documentada.
- Calidad: rustdoc, `clippy::pedantic`, 24 tests (property tests
  deterministas) y bench std-only (`examples/bench_colors.rs`).
- Empaquetado: `cargo-deb` + postinst/prerm, release con `.deb`, SBOM
  CycloneDX, `SHA256SUMS` y attestation; `PKGBUILD` de AUR listo (pendiente
  de publicar).

## [2.0.0] — 2026-09-14
- Renombrado a `keybackcon` ("Keyboard Backlight Controls"), repo
  `Soluciones-Alexendros/ilutex`, App ID `org.iniciativas.keybackcon`.
- CLI migrado a Cargo por módulos (`lamp/color/state/animation/cli`), cero
  dependencias, mismos comandos + alias `bright/auto/anim`, rutas nuevas con
  migración heredada `kbd-rgb`.
- GUI rediseñada: mesa de luz con light-stage, filtros + tono propio,
  intensidad −/+, movimiento Fijar/Respirar/Arcoíris, estado vivo, toasts,
  atajos y respeto a `gtk-enable-animations`.
- Packaging (`packaging/`), icono, `scripts/install.sh` idempotente y
  `scripts/smoke.sh`; systemd/udev/desktop con el nombre nuevo.
- CI (fmt+clippy+test+smoke) y release por tag con binario adjunto.
