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

## UWSM y sin UWSM

- **Con UWSM:** deja que gestione el autostart XDG; no actives a la vez la
  unidad de usuario, el autostart XDG y una entrada `exec-once` del compositor.
- **Sin UWSM:** arranque manual o una sola línea opt-in en tu `hyprland.conf`,
  por ejemplo (sintaxis según tu versión de Hyprland):

```conf
# Opt-in; no lo añadimos nosotros.
exec-once = ilutex-gui --tray
```

Para restauración al login con systemd de usuario (si tu sesión lo expone):

```bash
systemctl --user enable --now ilutex.service
```

Comprueba que `systemctl --user` habla con el gestor de **tu** sesión gráfica;
tener el binario `systemctl` no basta.

## Polkit

El control cotidiano no necesita root tras instalar la regla udev. Un agente
(`hyprpolkitagent` u otro) solo hace falta para la reparación gráfica de
permisos. Si cancelas la autorización, no hay éxito ficticio.

## Qué no hacemos

- Sobrescribir `DISPLAY`, `WAYLAND_DISPLAY` o `XDG_CURRENT_DESKTOP`.
- Instalar un segundo agente polkit si ya hay uno.
- Ampliar permisos a `0666` ni pedir ejecutar la GUI como root.
