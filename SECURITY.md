# Política de seguridad

## Versiones soportadas

| Versión        | Soportada                          |
| -------------- | ---------------------------------- |
| 3.1.x (`main`) | Sí                                 |
| 3.0.x / 2.x    | Solo histórico                     |

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
| Crítica   | Ejecución de código remoto o elevación de privilegios vía udev/HID | 14 días naturales |
| Alta      | Impacto grave sin llegar a RCE/elevación udev/HID | 30 días naturales |
| Resto     | Media, baja u otras | En la release siguiente |

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
- Instalación udev vía `pkexec`: las rutas van por `$1`/`$2`, no interpoladas en `sh -c`.
- Candado de escritura `/run/ilutex/writer.lock` (`root:ilutex` `0660`): el paquete **no** añade usuarios al grupo; la habilitación es explícita (`usermod`).
- Estado en `$XDG_STATE_HOME/ilutex/state` y pidfile en `$XDG_RUNTIME_DIR`.
- Renovate (`.github/renovate.json`) cubre `cargo` y `github-actions`. No hay Dependabot de version-updates.

## Firma GPG de release y rotación

Los artefactos de release incluyen `SHA256SUMS` firmado (`SHA256SUMS.asc`). La clave pública de firma vive en `packaging/keys/` (p. ej. `ilutex-release.asc`).

Procedimiento de rotación:

1. Clave **dedicada** solo a firmar releases (no la clave personal cotidiana).
2. Rotación **anual** o **ante sospecha** de compromiso.
3. La clave retirada se conserva en `packaging/keys/` con la **fecha** de retiro documentada (nombre o nota junto al `.asc`).
4. La **release siguiente** se firma **solo** con la clave nueva; las sumas antiguas siguen verificables con la clave retirada archivada.

## Alcance

Este repositorio es una CLI/GUI local para un teclado concreto. No opera un SaaS ni almacena datos de terceros. Las vulnerabilidades del firmware del teclado no son de este proyecto, salvo que el defecto esté en cómo hablamos con el dispositivo.
