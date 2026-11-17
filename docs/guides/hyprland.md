# Ilutex en Hyprland

### Propósito

Integración de sesión Wayland en Hyprland **sin** editar automáticamente
`hyprland.conf` ni la barra del escritorio. Copia solo lo que necesites.

Estado: **experimental** hasta completar los perfiles HY-A…HY-D con evidencias
registradas. Ver [`docs/compatibility/matriz.md`](../compatibility/matriz.md).

## Perfiles

| Perfil | Ventana | Bandeja | Arranque |
|---|---|---|---|
| HY-A · UWSM + bandeja del escritorio | Wayland nativo | Indicador | Un mecanismo de sesión |
| HY-B · sin UWSM + bandeja del escritorio | Wayland nativo | Indicador | Manual u opt-in documentado |
| HY-C · sin host de bandeja | Completa | No | Manual; aviso si falta bandeja |
| HY-D · sin agente polkit | Completa si hay permisos | Según host | Reparación de permisos explicada |

## Wayland

No fuerces `GDK_BACKEND=x11` en el uso normal. Identidad de aplicación:
`org.alexendros.ilutex` (no cambiar sin plan de migración).

```bash
ilutex-gui
# o solo bandeja, si hay host StatusNotifier:
ilutex-gui --tray
```

## Bandeja: usa la que ya trae tu escritorio

No instalamos ni configuramos una segunda barra: el icono LED es un
`StatusNotifierItem` (Ayatana) y lo pinta el host de bandeja que ya tengas.

### Omarchy (Quickshell)

La barra de Omarchy es **Quickshell**, no Waybar. El icono aparece en el
widget `omarchy.tray` de la sección derecha, y el desplegable nativo
(colores, brillo, animaciones y "Open window") sale del propio indicador.

Comprueba que el widget esté en la barra:

```bash
grep -q omarchy.tray ~/.config/omarchy/shell.json && echo "tray OK"
# si falta:
omarchy bar add omarchy.tray --section right
```

No hace falta Waybar instalado: si está corriendo una segunda barra, es un
duplicado. Detén la ajena (`pkill waybar`) y deja la de Omarchy.

### Hyprland sin Omarchy

Necesita un host StatusNotifier: Waybar con un módulo `tray`, o Quickshell.
Sin host, la ventana (`ilutex-gui`) sigue siendo completa; solo falta el icono.

> **Nota:** el icono se renderiza a 64×64 con canal alfa en
> `~/.cache/ilutex/tray-<color>-<modo>.png`; el host lo escala a su tamaño
> (≈20 px) sin perder calidad.

## Arranque al iniciar sesión (lo pone el instalador)

No hay que editar `hyprland.conf` ni tocar autostart a mano: `scripts/install.sh`
instala y habilita la unidad de usuario:

| Unidad | Para qué |
|---|---|
| `ilutex-tray.service` | la bandeja (`ilutex-gui --tray`) al iniciar sesión |
| `ilutex.service` | `ilutex restore --on-login` (respeta `restore_policy`) |

La unidad, y no un `.desktop` XDG, es la **única** fuente de arranque. Si
tuvieras un autostart antiguo, el instalador lo aparta; tener los dos arrancaría
dos bandejas. Para dejarla desactivada, usa `systemctl --user disable
ilutex-tray.service` (el instalador no la reactiva) o instala con
`ILUTEX_NO_TRAY=1`.

El interruptor «Abrir al iniciar sesión» de Preferencias gestiona esa misma
unidad, así que nunca crea un duplicado. Con UWSM no hace falta nada más: no
añadas además un `exec-once` del compositor.

Comprueba que el gestor de usuario habla con **tu** sesión gráfica; tener el
binario instalado no basta.

## Polkit

El control cotidiano no necesita root tras instalar la regla udev. Un agente
(`hyprpolkitagent` u otro) solo hace falta para la reparación gráfica de
permisos. Si cancelas la autorización, no hay éxito ficticio.

## Qué no hacemos

- Sobrescribir `DISPLAY`, `WAYLAND_DISPLAY` o `XDG_CURRENT_DESKTOP`.
- Instalar un segundo agente polkit si ya hay uno.
- Ampliar permisos a `0666` ni pedir ejecutar la GUI como root.
