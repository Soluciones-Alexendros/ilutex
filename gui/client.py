import hashlib
import json
import os
import shutil
import signal
import subprocess

try:
    from gui import api
except ImportError:  # ejecución directa: gui/ en sys.path
    import sys

    _here = os.path.dirname(os.path.abspath(__file__))
    _root = os.path.dirname(_here)
    if _root not in sys.path:
        sys.path.insert(0, _root)
    from gui import api

_load, log_exc, _gettext_func = api(__file__)
_ = _gettext_func()

# SHA-256 de packaging/udev/70-ilutex.rules (fuente de verdad del repo).
UDEV_RULES_SHA256 = (
    "58ab5db677ec3c199641db578942b802bd2ad8adc20625db18f08f9e6d8d983b"
)
UDEV_PACKAGED_SRC = "/usr/lib/udev/rules.d/70-ilutex.rules"
UDEV_DEST = "/etc/udev/rules.d/70-ilutex.rules"
PKEXEC_BIN = "/usr/bin/pkexec"
INSTALL_BIN = "/usr/bin/install"
UDEVADM_BIN = "/usr/bin/udevadm"
# Rutas absolutas permitidas en cualquier argv de pkexec que construya gui/.
UDEV_PKEXEC_ALLOWED_PATHS = frozenset(
    {
        PKEXEC_BIN,
        INSTALL_BIN,
        UDEVADM_BIN,
        UDEV_PACKAGED_SRC,
        UDEV_DEST,
    }
)


def find_binary():
    for cand in (
        shutil.which("ilutex"),
        os.path.expanduser("~/.local/bin/ilutex"),
        shutil.which("keybackcon"),  # legado: binario anterior, compatibilidad
        os.path.expanduser("~/.local/bin/keybackcon"),  # legado: ruta anterior
        shutil.which("kbd-rgb"),  # legado: binario anterior, compatibilidad
        os.path.expanduser("~/.local/bin/kbd-rgb"),  # legado: ruta anterior
    ):
        if cand and os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return "ilutex"


def udev_rules_digest(path: str) -> str | None:
    """SHA-256 hex del fichero, o None si no se puede leer."""
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return None


def udev_source_verified(path: str = UDEV_PACKAGED_SRC) -> bool:
    """True solo si el origen empaquetado existe y coincide el hash canónico."""
    digest = udev_rules_digest(path)
    return digest is not None and digest == UDEV_RULES_SHA256


def udev_install_argv() -> list[str] | None:
    """Argv absoluto de ``pkexec install``; None si el origen no verifica."""
    if not udev_source_verified():
        return None
    return [
        PKEXEC_BIN,
        INSTALL_BIN,
        "-m",
        "0644",
        UDEV_PACKAGED_SRC,
        UDEV_DEST,
    ]


def udev_reload_argv() -> list[str]:
    return [PKEXEC_BIN, UDEVADM_BIN, "control", "--reload"]


def udev_trigger_argv() -> list[str]:
    return [PKEXEC_BIN, UDEVADM_BIN, "trigger", "--subsystem-match=hidraw"]


def udev_pkexec_commands() -> list[list[str]] | None:
    """Tres llamadas pkexec (install, reload, trigger), o None si no hay origen."""
    install = udev_install_argv()
    if install is None:
        return None
    return [install, udev_reload_argv(), udev_trigger_argv()]


def udev_pkexec_argv_ok(argv: list[str]) -> bool:
    """True si cada argumento con forma de ruta es absoluto y está en allowlist."""
    if not argv or argv[0] != PKEXEC_BIN:
        return False
    for arg in argv:
        if arg.startswith("/") and arg not in UDEV_PKEXEC_ALLOWED_PATHS:
            return False
        if arg in ("sh", "-c") or arg.endswith("/sh"):
            return False
    return True


def _absolute_or_none(path: str | None) -> str | None:
    if not path or not str(path).strip():
        return None
    p = os.path.expanduser(str(path).strip())
    if not os.path.isabs(p):
        return None
    return p


# Debe coincidir con ``SCHEMA_VERSION`` en ``src/state.rs`` (KBC-16).
SCHEMA_VERSION = 1


def state_paths() -> tuple[str, str] | None:
    """Rutas de estado, o None si no hay XDG absoluto.

    Sin ``XDG_STATE_HOME`` absoluto y sin ``HOME`` absoluto no hay ruta
    compartida: no se usa ``/var/tmp``.
    """
    base = _absolute_or_none(os.environ.get("XDG_STATE_HOME"))
    if base is None:
        home = _absolute_or_none(os.environ.get("HOME"))
        if home is None:
            return None
        base = os.path.join(home, ".local/state")
    return (
        os.path.join(base, "ilutex/state"),
        os.path.join(base, "keybackcon/state"),
    )


def _clamp_brightness(value) -> int:
    try:
        n = int(value)
    except (TypeError, ValueError):
        raise ValueError("brightness")
    return max(0, min(100, n))


def _looks_versioned(raw: str) -> bool:
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, _ = line.partition("=")
        if key.strip() == "schema_version":
            return True
    return False


def _parse_legacy_line(raw: str) -> tuple[str, int] | None:
    parts = raw.split()
    if not parts:
        return None
    color = parts[0].lstrip("#").lower()
    if len(color) != 6:
        return None
    try:
        int(color, 16)
    except ValueError:
        return None
    pct = 100 if len(parts) < 2 else _clamp_brightness(parts[1])
    return color, pct


def parse_state_text(raw: str) -> tuple[str, object]:
    """Oráculo compartido con ``src/state.rs`` (KBC-12 / KBC-16).

    Devuelve ``("ok", (color_hex, brightness))``, ``("corrupt", None)`` o
    ``("unsupported", version)``.
    """
    if _looks_versioned(raw):
        color, pct = "ffffff", 100
        saw_version = False
        for line in raw.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip()
            if key == "schema_version":
                try:
                    ver = int(value)
                except ValueError:
                    return "corrupt", None
                if ver == 0 or ver > SCHEMA_VERSION:
                    return "unsupported", ver
                saw_version = True
            elif key == "base_color":
                color = value.lstrip("#").lower()
                if len(color) != 6:
                    return "corrupt", None
                try:
                    int(color, 16)
                except ValueError:
                    return "corrupt", None
            elif key == "brightness":
                try:
                    pct = _clamp_brightness(value)
                except ValueError:
                    return "corrupt", None
        if not saw_version:
            return "corrupt", None
        return "ok", (color, pct)
    legacy = _parse_legacy_line(raw)
    if legacy is not None:
        return "ok", legacy
    return "corrupt", None


def pid_paths():
    base = _absolute_or_none(os.environ.get("XDG_RUNTIME_DIR"))
    if base is None:
        base = f"/tmp/ilutex-{os.getuid()}"
    return (
        os.path.join(base, "ilutex/animation.pid"),
        os.path.join(base, "keybackcon/animation.pid"),
        os.path.join(base, "keybackcon/anim.pid"),
        os.path.join(base, "kbd-rgb/anim.pid"),
    )


class IlutexError(Exception):
    message: str

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class IlutexClient:
    def __init__(self, binary: str | None = None):
        self._bin = binary if binary else find_binary()
        self._proc = None

    def _run(self, args: list) -> subprocess.CompletedProcess:
        try:
            proc = subprocess.run(
                [self._bin] + args,
                capture_output=True,
                text=True,
                timeout=10,
            )
        except FileNotFoundError:
            raise IlutexError(
                _("Cannot find the binary ({bin}). Install it first.").format(
                    bin=self._bin
                )
            )
        except subprocess.TimeoutExpired:
            raise IlutexError(_("The keyboard took too long to respond."))
        except OSError as e:
            raise IlutexError(_("The keyboard did not respond: {e}").format(e=e))
        if proc.returncode != 0:
            err = (proc.stderr or proc.stdout or "").strip()
            if err:
                raise IlutexError(err)
            raise IlutexError(
                _("The keyboard did not respond (code {code}).").format(
                    code=proc.returncode
                )
            )
        return proc

    def stop_animation(self) -> None:
        """Mata el proceso de animación lanzado, con tope de ~1 s.

        La animación arranca en su propio grupo de procesos
        (``start_new_session``), así que aquí se mata el grupo entero.
        """
        proc = self._proc
        self._proc = None
        if proc is None:
            return
        try:
            pgid = os.getpgid(proc.pid)
        except (ProcessLookupError, OSError):
            pgid = None
        # Solo matamos el grupo si el hijo es líder de sesión (es decir,
        # lo lanzamos nosotros con start_new_session); si no, terminate().
        propio_grupo = pgid is not None and pgid == proc.pid
        try:
            if propio_grupo:
                os.killpg(pgid, signal.SIGTERM)
            elif proc.poll() is None:
                proc.terminate()
        except (ProcessLookupError, PermissionError, OSError):
            pass  # carrera de salida: el proceso ya no existe
        try:
            proc.wait(timeout=1)
            return
        except subprocess.TimeoutExpired:
            pass  # sobrevive al TERM: escalamos a SIGKILL
        except (ChildProcessError, OSError):
            return  # zombie ya cosechado por otro waiter
        try:
            if propio_grupo:
                os.killpg(pgid, signal.SIGKILL)
            elif proc.poll() is None:
                proc.kill()
        except (ProcessLookupError, PermissionError, OSError):
            pass  # carrera de salida: el proceso ya no existe
        try:
            proc.wait(timeout=1)
        except Exception:
            log_exc("cosechar animación")  # el kernel recogerá el zombie

    def info(self) -> dict:
        """`info --json` como dict. Lanza IlutexError si el binario falla.

        Si el binario es viejo y no habla JSON, devuelve {} para que la
        interfaz muestre «desconocido» en vez de romperse.
        """
        proc = self._run(["info", "--json"])
        try:
            lineas = (proc.stdout or "").strip().splitlines()
            data = json.loads(lineas[-1])
        except (ValueError, IndexError):
            return {}
        if not isinstance(data, dict):
            return {}
        return data

    def set_color(self, hex: str) -> None:
        self._run(["set", hex])

    def set_brightness(self, pct: int) -> None:
        self._run(["brightness", str(pct)])

    def animation(self, mode: str) -> None:
        self.stop_animation()
        self._run(["firmware-effects", "off"])
        try:
            self._proc = subprocess.Popen(
                [self._bin, "animation", mode],
                start_new_session=True,
            )
        except FileNotFoundError:
            raise IlutexError(
                _("Cannot find the binary ({bin}). Install it first.").format(
                    bin=self._bin
                )
            )
        except OSError as e:
            raise IlutexError(_("The keyboard did not respond: {e}").format(e=e))

    def stop(self) -> str:
        self.stop_animation()
        proc = self._run(["stop"])
        return proc.stdout.strip()

    def restore(self) -> str:
        self.stop_animation()
        proc = self._run(["restore"])
        return proc.stdout.strip()

    def off(self) -> None:
        self._run(["off"])

    def firmware_effects(self, on: bool) -> None:
        self._run(["firmware-effects", "on" if on else "off"])

    def get_state_file(self) -> tuple[str, int]:
        """Lee color/brillo con el mismo oráculo que Rust (KBC-16).

        Ausencia → defaults. Primario presente pero corrupto/futuro → defaults
        de solo lectura (no se escribe; el CLI fallará al RMW y conserva el
        original, KBC-12). No se cae al legado si el primario existe.
        """
        paths = state_paths()
        if paths is None:
            return "ffffff", 100
        primary, legacy = paths
        for path, is_primary in ((primary, True), (legacy, False)):
            try:
                with open(path) as f:
                    raw = f.read()
            except FileNotFoundError:
                continue
            except OSError:
                if is_primary:
                    return "ffffff", 100
                continue
            kind, payload = parse_state_text(raw)
            if kind == "ok":
                return payload  # type: ignore[return-value]
            # Primario ilegible: no consultar legado (alineado con load_persisted).
            return "ffffff", 100
        return "ffffff", 100

    def animation_running(self) -> int | None:
        for path in pid_paths():
            try:
                with open(path) as f:
                    pid = int(f.read().strip())
                if pid <= 0:
                    continue
                # /proc en lugar de kill(0): algunos sandboxes bloquean señales.
                if not os.path.exists(f"/proc/{pid}"):
                    os.unlink(path)
                    continue
                with open(f"/proc/{pid}/cmdline", "rb") as cf:
                    cmd = cf.read().decode(errors="ignore")
                if "ilutex" in cmd or "keybackcon" in cmd or "kbd-rgb" in cmd:
                    return pid
                os.unlink(path)
            except Exception:
                continue
        return None
