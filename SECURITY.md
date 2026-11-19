# Política de seguridad

## Versiones soportadas

| Versión | Soportada |
| ------- | --------- |
| 3.1.x (`main`) | Sí (soporte completo) |
| 3.0.x | Solo parches de seguridad |
| &lt; 3.0 | No soportada |

La versión vive en `Cargo.toml`. El tag `vX.Y.Z` debe coincidir.

## Cómo reportar una vulnerabilidad

**No abras un issue público** si el hallazgo puede elevar privilegios (udev/`pkexec`), inyectar rutas o hablar con el HID de forma inesperada.

1. Preferible: [GitHub Security Advisory](https://github.com/Soluciones-Alexendros/ilutex/security/advisories/new) en este repositorio.
2. Alternativa: correo a [operaciones@alexendros.dev](mailto:operaciones@alexendros.dev).

Incluye: versión o commit, comando reproducido, distro, y un descriptor **mínimo** (nunca dumps con datos personales). Acusaremos recibo en un plazo máximo de 7 días naturales. El advisory coordinado se publica vía [GitHub Security Advisories](https://github.com/Soluciones-Alexendros/ilutex/security/advisories).

## Plazos de remediación

Tras el acuse, el objetivo de parcheo según severidad es:

| Severidad | Criterio (ejemplos) | Plazo objetivo |
| --------- | ------------------- | -------------- |
| Crítica   | Ejecución de código remoto o elevación de privilegios vía udev/HID | 7 días naturales |
| Alta      | Impacto grave sin llegar a RCE/elevación udev/HID | 30 días naturales |
| Media     | Impacto acotado o mitigable | 90 días naturales |
| Baja      | Bajo impacto / endurecimiento | En la release siguiente |

Estos plazos son objetivos de respuesta, no un compromiso contractual.

## Ámbito local y endurecimiento

ilutex es una CLI/GUI **local** para un teclado concreto: no abre red hacia terceros ni almacena datos de terceros. El objetivo de endurecimiento es equivalente a los controles **aplicables** de [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/) nivel L1 sobre esa superficie (p. ej. validación de entradas CLI, rutas udev, ioctl HID acotados, permisos del candado y del estado en XDG).

Quedan **explícitamente N/A** (no hay superficie que cubrir):

- Sesión web / autenticación de aplicación
- Tokens de API o de sesión de usuario
- Almacén o procesamiento de datos de terceros

Esto **no** afirma certificación ASVS ni auditoría formal contra el estándar.

## Superficie relevante

- Transporte HID (`src/lamp.rs`, `src/protocol.rs`): ioctl `HIDIOC{G,S}FEATURE` con longitud acotada.
- Instalación udev vía `pkexec` (`gui/client.py`): argv absolutos allowlistados (`/usr/bin/pkexec`, `/usr/bin/install`, `/usr/bin/udevadm`, origen `/usr/lib/udev/rules.d/70-ilutex.rules`, destino `/etc/udev/rules.d/70-ilutex.rules`); sin `sh -c`. El origen solo se instala si su SHA-256 coincide con `UDEV_RULES_SHA256` (misma suma que `packaging/udev/70-ilutex.rules`).
- Candado de escritura `/run/ilutex/writer.lock` (`root:ilutex` `0660`): el paquete **no** añade usuarios al grupo; la habilitación es explícita (`usermod`).
- Estado en `$XDG_STATE_HOME/ilutex/state` y pidfile en `$XDG_RUNTIME_DIR`.
- Renovate (`.github/renovate.json`) cubre `cargo` y `github-actions`. No hay Dependabot de version-updates.

## Signing Key Management

Los artefactos de release incluyen `SHA256SUMS` firmado con GPG (`SHA256SUMS.asc`) y, además, una firma **cosign keyless** (Sigstore) del mismo `SHA256SUMS` (`SHA256SUMS.sigstore.json`). La verificación publicada para usuarios sigue siendo GPG; cosign es capa adicional. El secret `ILUTEX_RELEASE_GPG_KEY` y la clave pública en `packaging/keys/` no se retiran.

### Política de la clave GPG de release

1. Algoritmo: **ed25519** o **RSA-4096**.
2. Caducidad: **2 años** desde la creación.
3. Uso: clave **dedicada** solo a firmar releases (no la clave personal cotidiana).
4. Rotación: **anual**, con **30 días de solape** entre la clave saliente y la entrante; también ante sospecha de compromiso.
5. Publicación de la pública: [keys.openpgp.org](https://keys.openpgp.org) y copia en `packaging/keys/` (p. ej. `ilutex-release.asc`).
6. Revocación: generar y publicar certificado de revocación en keys.openpgp.org; archivar la pública retirada en `packaging/keys/` con la **fecha** de retiro en el nombre o nota; la release siguiente se firma solo con la clave nueva (las sumas antiguas siguen verificables con la clave archivada).

Procedimiento operativo: [`packaging/keys/README.md`](packaging/keys/README.md).

### Cosign keyless (Sigstore)

En cada tag `v*`, `release.yml` firma `dist/SHA256SUMS` con `cosign sign-blob` vía OIDC de GitHub Actions (`id-token: write`). No hay clave cosign de larga duración que rotar. La identidad esperada al verificar es el workflow de release de este repositorio y el emisor `https://token.actions.githubusercontent.com`.

## Alcance

Este repositorio es una CLI/GUI local para un teclado concreto. No opera un SaaS ni almacena datos de terceros. Las vulnerabilidades del firmware del teclado no son de este proyecto, salvo que el defecto esté en cómo hablamos con el dispositivo.
