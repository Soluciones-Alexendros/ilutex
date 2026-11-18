# Runbook: empaquetado y release

## Preflight

1. `make validate` verde.
2. Versión en `Cargo.toml` = tag `vX.Y.Z` (el workflow lo exige).
3. CHANGELOG: `git-cliff` es la fuente; no edites a mano en el release.

## Tag

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

`.github/workflows/release.yml` publica tarball, `.deb`, SBOM CycloneDX,
`SHA256SUMS`, la firma `SHA256SUMS.asc` y attestation de procedencia.
Exporta `SOURCE_DATE_EPOCH` con la fecha del commit del tag (no afirma
builds bit a bit). Requiere el secret `ILUTEX_RELEASE_GPG_KEY`; sin él el
job falla. La pública va en `packaging/keys/ilutex-release.asc` (ver
[`packaging/keys/README.md`](../../packaging/keys/README.md)).

Verificación del consumidor:

```bash
gpg --import packaging/keys/ilutex-release.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
gh attestation verify ilutex-vX.Y.Z-linux-x86_64.tar.gz --owner Alexendros
```

## Fallos típicos

| Síntoma | Qué mirar |
| --- | --- |
| Tag no coincide con Cargo.toml | El job de release falla a propósito. Alinea versión y retaguea. |
| Falta `.mo` en el `.deb` | El workflow corre `msgfmt` antes de `cargo deb` para cada `po/*.po`. En local: `make i18n` (regenera el `.pot` y compila `gui/locale/<idioma>/LC_MESSAGES/ilutex.mo`). |
| `.pot` desincronizado del código | `make check-i18n` compara `.pot` y `.po` (msgids, vacíos, duplicados). `make i18n` regenera con `xgettext` (`--keyword=_ --keyword=N_`). |
| AUR sin `sha256sums` | `updpkgsums` y `makepkg --printsrcinfo` antes de publicar (ver `packaging/aur/README.md`). |
| Unidades systemd en `~/.local` | `install.sh` reescribe `/usr/bin` → `%h/.local/bin`. El paquete debe quedar en `/usr/bin`. |
| `ilutex --version` viejo tras `install.sh` | Shim mise o `/usr/bin` delante de `~/.local/bin`. El instalador avisa (`AVISO: … sombrea …`). Quita el shim o alinea el paquete de sistema. |
| Menú abre GUI rota | El `.desktop` de usuario usa `Exec` absoluto a `~/.local/bin/ilutex-gui`. El de sistema (`package()`) usa `/usr/bin/ilutex-gui`. |
| Drift versión instalada vs repo | `make check-installed` compara `Cargo.toml` con binarios, unidades y `.desktop` presentes. |

## Precedencia de canales

Orden típico en el shell: shim de mise → `/usr/bin` → `~/.local/bin`. Una
instalación de usuario 3.1.x no surte efecto si un paquete de sistema o un
shim antiguo gana. El instalador avisa cuando las versiones difieren; el
`.desktop` de usuario no depende del `PATH`.

Tras publicar el tag `vX.Y.Z`, recalcula checksums de AUR/omarchy con
`updpkgsums` (el tarball de GitHub no es reproducible).

## Instalación offline (ILUTEX_ROOT)

Para escenificar solo los ficheros root en un root alternativo —imágenes,
chroots, contenedores sin systemd— sin compilar ni tocar la sesión:

```bash
ILUTEX_ROOT=/ruta/al/root ./scripts/install.sh
```

Deja, bajo `$ILUTEX_ROOT`: `etc/udev/rules.d/70-ilutex.rules`,
`usr/lib/sysusers.d/ilutex.conf`, `usr/lib/tmpfiles.d/ilutex.conf` y el candado
`run/ilutex/writer.lock` (modos `0770`/`0660`).

- Sin `ILUTEX_ROOT` (o relativa), el instalador funciona en vivo como siempre.
- El modo offline **no usa sudo** ni `udevadm` y no depende de systemd: el
  candado se crea directamente. La propiedad `root:ilutex` la fija quien
  instale ese root como root (p. ej. el empaquetador).
- `systemd-sysusers --root` se usa si está disponible para dejar el grupo
  `ilutex` en `$ILUTEX_ROOT/etc/group` (best-effort).
