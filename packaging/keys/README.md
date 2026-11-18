# Claves de firma de release

El workflow [`.github/workflows/release.yml`](../../.github/workflows/release.yml)
firma `dist/SHA256SUMS` con GPG y publica `SHA256SUMS.asc` junto al tarball,
el `.deb` y el SBOM.

## Checklist antes del primer tag tras merge

Bloqueante: sin ambos, el job de release falla o el consumidor no puede
verificar.

1. Secret de repositorio `ILUTEX_RELEASE_GPG_KEY` con la clave **privada**
   ASCII-armor (ver abajo: **sin passphrase**).
2. Commit de la pública en `packaging/keys/ilutex-release.asc` en la rama
   que el tag apuntará.

## Qué debe hacer el operador

1. Crear un par GPG **dedicado** a releases de ilutex (no reutilizar la clave
   personal de commits), **sin passphrase** (el runner firma con
   `--pinentry-mode loopback` y no hay secret de passphrase: si la clave
   pide PIN, el job falla).
2. Guardar la clave **privada** como secret de repositorio
   `ILUTEX_RELEASE_GPG_KEY` (ASCII-armor completo exportado con
   `gpg --export-secret-keys --armor <fpr>`). Sin ese secret el job de
   release falla a propósito: no se publica un `SHA256SUMS` sin firma.
3. Colocar aquí la clave **pública** como `ilutex-release.asc`:

   ```bash
   gpg --export --armor <fpr> > packaging/keys/ilutex-release.asc
   ```

4. Rotación: anual o ante sospecha de compromiso. Conservar la clave retirada
   en este directorio con la fecha en el nombre (p. ej.
   `ilutex-release-YYYY-MM-DD-retired.asc`). La release siguiente se firma solo
   con la clave nueva.

## Qué no va en el repo

- La clave privada.
- Un `.asc` inventado o de relleno: si aún no hay par real, deja solo este
  README hasta que el operador genere y publique la pública.

## Verificación (consumidor)

Con la pública importada:

```bash
gpg --import packaging/keys/ilutex-release.asc
gpg --verify SHA256SUMS.asc SHA256SUMS
gh attestation verify ilutex-vX.Y.Z-linux-x86_64.tar.gz --repo Soluciones-Alexendros/ilutex
```
