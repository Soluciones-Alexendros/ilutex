# Runbook: dispositivo HID y udev

| Síntoma | Comprobación | Acción |
| --- | --- | --- |
| No encuentra el teclado | `ilutex info`; USB conectado; descriptor `05 59 09 01 A1 01` | Revisa el cable; solo AERO X16 (LampArray). Spec en [`../architecture/protocol.md`](../architecture/protocol.md). |
| Permiso denegado en `/dev/hidraw*` | `ls -l /dev/hidraw*`; regla `packaging/udev/70-ilutex.rules` | `sudo udevadm trigger` y **vuelve a iniciar sesión**. El paquete instala la regla; `install.sh` también. |
| Permiso denegado al candado / «Instalar no autoriza» | `id -nG`; `ls -ld /run/ilutex /run/ilutex/writer.lock` | Instalar el paquete **no** te mete en el grupo. `sudo usermod -aG ilutex $USER` y sesión nueva (o `newgrp ilutex`). Dir `0770` root:ilutex; fichero `0660` root:ilutex. |
| La animación no para | Pidfile `$XDG_RUNTIME_DIR/ilutex/animation.pid` | `ilutex stop`. Si el pidfile está huérfano, el CLI lo reclama (ADR 3). |
| «ya hay una escritura» | `/run/ilutex/writer.lock` y grupo `ilutex` | Otro comando del producto tiene el candado. Si el directorio no existe, reinstala el paquete (`tmpfiles.d` / `sysusers.d`) y entra en una sesión donde el grupo ya esté activo. |
| Color no sobrevive al reinicio | Unidad `ilutex.service` (usuario) | El `.deb`/AUR apunta a `/usr/bin/ilutex restore`. Tras `install.sh`, las unidades usan `~/.local/bin`. |

La GUI nunca toca hidraw: habla con el CLI por subproceso (ADR 9).
