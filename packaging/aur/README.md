# Paquete AUR de ilutex

`PKGBUILD` para [Arch Linux](https://archlinux.org) (AUR) que compila
`ilutex` y instala el binario, la GUI (`ilutex-gui`), el lanzador, el
icono, la regla udev, el candado (`tmpfiles.d`/`sysusers.d`), las unidades
de usuario de systemd y la licencia.

## Estado

La receta compila y el `sha256sums` apunta al tarball del tag vigente,
pero **el paquete no está publicado en AUR** y falta la prueba en un chroot
limpio. Hasta entonces el canal acreditado es el script local o el binario
de la release (ver `docs/compatibility/matriz.md`).

## Antes de publicar (obligatorio)

1. **Mantenedor**: ya configurado (`operaciones@alexendros.dev`). Si cambia,
   actualiza la primera línea de `PKGBUILD`.
2. **Sumas de verificación**: tras publicar el tag, el tarball de GitHub
   cambia de contenido (no es reproducible), así que recalcula siempre:

   ```sh
   updpkgsums
   ```

   Y no dejes `SKIP`: el checksum es lo único que ata la receta al código.
3. **`.SRCINFO`**: es un fichero generado que el AUR exige en cada push.
   No se edita a mano:

   ```sh
   makepkg --printsrcinfo > .SRCINFO
   ```

4. **Prueba local** en un sistema Arch limpio:

   ```sh
   makepkg -si
   ilutex info
   ilutex-gui
   ```

## Publicar en AUR

```sh
git clone ssh://aur@aur.archlinux.org/ilutex.git
cp PKGBUILD .SRCINFO ilutex/
cd ilutex && git add PKGBUILD .SRCINFO && git commit -m "ilutex <versión>-1" && git push
```

## Actualizar a una versión nueva

1. Cambia `pkgver` (y deja `pkgrel=1`).
2. Comprueba que el tag `v$pkgver` existe en GitHub.
3. `updpkgsums` y `makepkg --printsrcinfo > .SRCINFO`.
4. Prueba con `makepkg -si` y empuja `PKGBUILD` + `.SRCINFO` juntos.

## Notas

- `conflicts`/`replaces=('kbd-rgb' 'keybackcon')`: `ilutex` sustituye a los
  paquetes anteriores; el estado heredado en `~/.local/state` se sigue
  leyendo.
- Dependencias opcionales de la GUI (`ilutex-gui`): `python-gobject`,
  `gtk4`, `libadwaita`, `libayatana-appindicator` (solo necesarias para el
  panel gráfico; el CLI funciona sin ellas; `libayatana-appindicator` solo
  para el indicador de bandeja).
- Compilación aislada con `cargo build --release --locked` (sin red extra)
  más `msgfmt` (`gettext`, en `makedepends`) para compilar los catálogos
  (`/usr/share/locale/{es,en}/LC_MESSAGES/ilutex.mo`); el schema GSettings va
  a `/usr/share/glib-2.0/schemas/` y lo recompilan los hooks de
  glib2/pacman (sin scriptlets propios).
- **Instalar ≠ autorizar**: el paquete crea el grupo `ilutex` y el candado
  `/run/ilutex/writer.lock`, pero no añade al usuario al grupo.
