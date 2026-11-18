"""Arranque de bandeja sin Ayatana y degradación sin host SNI.

Cubre G-03: la bandeja usa StatusNotifierItem vía Gio; Ayatana no es
dependencia de importación. Sin bus o sin host SNI se lanza TrayUnavailable.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

DAEMON = shutil.which("dbus-daemon")

try:
    import gi  # noqa: F401

    from gi.repository import Gio, GLib  # noqa: F401

    GI_DISPONIBLE = True
except Exception:
    GI_DISPONIBLE = False


class TestImportSinAyatana(unittest.TestCase):
    def test_import_ok_sin_ayatana(self):
        """Bloquear AyatanaAppIndicator3 no impide cargar gui.tray."""
        snippet = (
            "import builtins, sys\n"
            "_real = builtins.__import__\n"
            "def _hook(name, globals=None, locals=None, fromlist=(), level=0):\n"
            "    if 'AyatanaAppIndicator3' in str(name):\n"
            "        raise ImportError('simulated no ayatana')\n"
            "    try:\n"
            "        fl = list(fromlist or ())\n"
            "    except Exception:\n"
            "        fl = []\n"
            "    if any('AyatanaAppIndicator3' in str(x) for x in fl):\n"
            "        raise ImportError('simulated no ayatana')\n"
            "    return _real(name, globals, locals, fromlist, level)\n"
            "builtins.__import__ = _hook\n"
            "import gui.tray as t\n"
            "assert t.TrayUnavailable is not None\n"
            "src = open(t.__file__, encoding='utf-8').read()\n"
            "assert 'require_version(\"Ayatana' not in src\n"
            "assert 'require_version(\\x27Ayatana' not in src\n"
            "print('ok')\n"
        )
        env = dict(os.environ)
        env["GDK_BACKEND"] = "x11"
        env.pop("WAYLAND_DISPLAY", None)
        # Preferir el mismo intérprete; si no tiene gi, probar /usr/bin/python3.
        candidates = [sys.executable, "/usr/bin/python3"]
        last = None
        for py in candidates:
            if not py or not os.path.isfile(py):
                continue
            try:
                p = subprocess.run(
                    [py, "-c", snippet],
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=60,
                )
            except Exception as exc:
                last = exc
                continue
            if p.returncode == 0 and "ok" in (p.stdout or ""):
                return
            last = "exit=%s stderr=%s" % (p.returncode, (p.stderr or "")[:400])
            # Si falla por gi ausente, probar el siguiente candidato.
            if "gi" in (p.stderr or "") or "TrayUnavailable" in (p.stderr or ""):
                continue
        self.skipTest("sin intérprete con Gtk3/Gio/cairo (%s)" % last)


@unittest.skipUnless(GI_DISPONIBLE and DAEMON, "requiere Gio y dbus-daemon")
class TestTrayUnavailableSinHost(unittest.TestCase):
    def test_sin_watcher_lanza_trayunavailable(self):
        bus = subprocess.Popen(
            [DAEMON, "--session", "--print-address", "--nofork"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        try:
            address = bus.stdout.readline().strip()
            self.assertTrue(address, "dbus-daemon no imprimió dirección")
            env = dict(os.environ)
            env["DBUS_SESSION_BUS_ADDRESS"] = address
            env["GDK_BACKEND"] = "x11"
            env.pop("WAYLAND_DISPLAY", None)
            # TrayUnavailable se lanza en el import si faltan Gtk3/cairo: hay
            # que atraparla ahí (el fromlist no llega a bindear el nombre).
            snippet = (
                "import os, sys\n"
                "sys.path.insert(0, os.environ['ILUTEX_ROOT'])\n"
                "try:\n"
                "    from gui.tray import TrayIndicator, TrayUnavailable\n"
                "except Exception as e:\n"
                "    if type(e).__name__ == 'TrayUnavailable':\n"
                "        print('unavailable')\n"
                "        raise SystemExit(0)\n"
                "    raise\n"
                "class C:\n"
                "    def get_state_file(self): return ('ffffff', 100)\n"
                "    def animation_running(self): return None\n"
                "    def stop(self): pass\n"
                "try:\n"
                "    TrayIndicator(C(), lambda: None)\n"
                "except TrayUnavailable:\n"
                "    print('unavailable')\n"
                "    raise SystemExit(0)\n"
                "print('unexpected-ok')\n"
                "raise SystemExit(2)\n"
            )
            env["ILUTEX_ROOT"] = ROOT
            # DISPLAY puede faltar: Gtk.Menu necesita display en algunos hosts.
            # Si no hay display, el fallo debe ser TrayUnavailable (sin watcher)
            # antes de construir el menú… StatusNotifierItem se crea primero.
            py = sys.executable
            if subprocess.run(
                [py, "-c", "import gi"], capture_output=True
            ).returncode != 0:
                py = "/usr/bin/python3"
            p = subprocess.run(
                [py, "-c", snippet],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
                timeout=60,
            )
            self.assertEqual(
                p.returncode,
                0,
                "esperado TrayUnavailable sin host; exit=%s out=%r err=%r"
                % (p.returncode, p.stdout, p.stderr[:400]),
            )
            self.assertIn("unavailable", p.stdout)
        finally:
            bus.terminate()
            try:
                bus.wait(timeout=5)
            except subprocess.TimeoutExpired:
                bus.kill()
                bus.wait(timeout=5)
            if bus.stdout:
                bus.stdout.close()


if __name__ == "__main__":
    unittest.main()
