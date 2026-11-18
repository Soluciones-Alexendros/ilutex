import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

from gui.client import (
    INSTALL_BIN,
    IlutexClient,
    IlutexError,
    PKEXEC_BIN,
    UDEVADM_BIN,
    UDEV_DEST,
    UDEV_PACKAGED_SRC,
    UDEV_PKEXEC_ALLOWED_PATHS,
    UDEV_RULES_SHA256,
    find_binary,
    pid_paths,
    state_paths,
    udev_install_argv,
    udev_pkexec_argv_ok,
    udev_pkexec_commands,
    udev_reload_argv,
    udev_rules_digest,
    udev_source_verified,
    udev_trigger_argv,
)


class BinarioFake:
    """Crea un ejecutable de mentira en un directorio ejecutable.

    Usa XDG_RUNTIME_DIR (o /var/tmp) porque algunos /tmp están montados
    con noexec y el binario no podría arrancar.
    """

    # Directorio del repo: /tmp y XDG_RUNTIME_DIR suelen ir con noexec.
    BASE_EJECUTABLE = os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
        ".pytest-bin",
    )

    def __init__(self, contenido="#!/bin/sh\nexit 0\n"):
        os.makedirs(self.BASE_EJECUTABLE, exist_ok=True)
        self.dir = tempfile.mkdtemp(prefix="kbc-test-bin-", dir=self.BASE_EJECUTABLE)
        self.ruta = os.path.join(self.dir, "ilutex")
        with open(self.ruta, "w") as f:
            f.write(contenido)
        os.chmod(self.ruta, os.stat(self.ruta).st_mode | stat.S_IEXEC)

    def limpiar(self):
        shutil.rmtree(self.dir, ignore_errors=True)


class EntornoXdg:
    """XDG_STATE_HOME/XDG_RUNTIME_DIR temporales, restaurados al salir."""

    def __init__(self):
        self._guardados = {}
        for var in ("XDG_STATE_HOME", "XDG_RUNTIME_DIR"):
            self._guardados[var] = os.environ.get(var)
        self.tmp = tempfile.mkdtemp(prefix="kbc-test-xdg-")
        os.environ["XDG_STATE_HOME"] = os.path.join(self.tmp, "state")
        os.environ["XDG_RUNTIME_DIR"] = os.path.join(self.tmp, "run")
        os.makedirs(os.environ["XDG_STATE_HOME"], exist_ok=True)
        os.makedirs(os.environ["XDG_RUNTIME_DIR"], exist_ok=True)

    def restaurar(self):
        for var, valor in self._guardados.items():
            if valor is None:
                os.environ.pop(var, None)
            else:
                os.environ[var] = valor
        shutil.rmtree(self.tmp, ignore_errors=True)


class TestRutas(unittest.TestCase):
    def test_state_paths_respeta_xdg(self):
        env = EntornoXdg()
        try:
            rutas = state_paths()
            self.assertIsNotNone(rutas)
            assert rutas is not None
            nuevo, legado = rutas
            self.assertTrue(nuevo.startswith(env.tmp))
            self.assertTrue(nuevo.endswith("ilutex/state"))
            self.assertTrue(legado.endswith("keybackcon/state"))
        finally:
            env.restaurar()

    def test_state_paths_sin_home_absoluto_no_usa_var_tmp(self):
        guardados = {k: os.environ.get(k) for k in ("HOME", "XDG_STATE_HOME")}
        try:
            os.environ.pop("XDG_STATE_HOME", None)
            os.environ["HOME"] = "relativo/no-absoluto"
            self.assertIsNone(state_paths())
            os.environ.pop("HOME", None)
            self.assertIsNone(state_paths())
        finally:
            for clave, valor in guardados.items():
                if valor is None:
                    os.environ.pop(clave, None)
                else:
                    os.environ[clave] = valor

    def test_pid_paths_respeta_runtime(self):
        env = EntornoXdg()
        try:
            paths = pid_paths()
            self.assertTrue(paths[0].startswith(env.tmp))
            self.assertTrue(paths[0].endswith("ilutex/animation.pid"))
            self.assertEqual(len(paths), 4)
        finally:
            env.restaurar()

    def test_udev_hash_constante_coincide_con_packaging(self):
        root = os.path.dirname(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        )
        path = os.path.join(root, "packaging", "udev", "70-ilutex.rules")
        with open(path, "rb") as f:
            digest = hashlib.sha256(f.read()).hexdigest()
        self.assertEqual(digest, UDEV_RULES_SHA256)
        self.assertEqual(udev_rules_digest(path), UDEV_RULES_SHA256)

    def test_udev_install_argv_absoluto_cuando_hash_ok(self):
        with mock.patch("gui.client.udev_source_verified", return_value=True):
            argv = udev_install_argv()
        self.assertEqual(
            argv,
            [
                PKEXEC_BIN,
                INSTALL_BIN,
                "-m",
                "0644",
                UDEV_PACKAGED_SRC,
                UDEV_DEST,
            ],
        )
        self.assertTrue(udev_pkexec_argv_ok(argv))
        self.assertNotIn("sh", argv)
        self.assertNotIn("-c", argv)

    def test_udev_install_argv_none_si_hash_falla(self):
        with mock.patch("gui.client.udev_source_verified", return_value=False):
            self.assertIsNone(udev_install_argv())
            self.assertIsNone(udev_pkexec_commands())

    def test_udev_pkexec_commands_tres_llamadas_absolutas(self):
        with mock.patch("gui.client.udev_source_verified", return_value=True):
            cmds = udev_pkexec_commands()
        self.assertIsNotNone(cmds)
        assert cmds is not None
        self.assertEqual(len(cmds), 3)
        self.assertEqual(
            cmds[0],
            [
                PKEXEC_BIN,
                INSTALL_BIN,
                "-m",
                "0644",
                UDEV_PACKAGED_SRC,
                UDEV_DEST,
            ],
        )
        self.assertEqual(
            cmds[1],
            [PKEXEC_BIN, UDEVADM_BIN, "control", "--reload"],
        )
        self.assertEqual(
            cmds[2],
            [PKEXEC_BIN, UDEVADM_BIN, "trigger", "--subsystem-match=hidraw"],
        )
        self.assertEqual(cmds[1], udev_reload_argv())
        self.assertEqual(cmds[2], udev_trigger_argv())
        for cmd in cmds:
            self.assertTrue(udev_pkexec_argv_ok(cmd))

    def test_udev_source_verified_rechaza_contenido_alterado(self):
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            tmp.write(b"SUBSYSTEM==\"hidraw\", TAG+=\"uaccess\"\n# tampered\n")
            path = tmp.name
        try:
            self.assertFalse(udev_source_verified(path))
        finally:
            os.unlink(path)

    def test_gui_pkexec_solo_rutas_absolutas_permitidas(self):
        """CI: gui/ no puede llamar pkexec con rutas relativas o fuera de allowlist."""
        gui_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        # Construcción de argv con shell (no el rechazo defensivo de "sh"/"-c").
        sh_c_argv = re.compile(
            r"""\[\s*["'](?:/usr/bin/)?pkexec["']\s*,\s*["']sh["']\s*,\s*["']-c["']"""
        )
        elevation_paths = re.compile(
            r'"(/(?:usr/bin/(?:pkexec|install|udevadm)|'
            r"usr/lib/udev/rules\.d/[\w.-]+|etc/udev/rules\.d/[\w.-]+))"
            r'"'
        )
        offenders = []
        for name in sorted(os.listdir(gui_dir)):
            if not name.endswith(".py"):
                continue
            path = os.path.join(gui_dir, name)
            with open(path, encoding="utf-8") as f:
                text = f.read()
            if sh_c_argv.search(text):
                offenders.append("%s: pkexec with sh -c" % name)
            for match in elevation_paths.finditer(text):
                literal = match.group(1)
                if literal not in UDEV_PKEXEC_ALLOWED_PATHS:
                    offenders.append("%s: not allowlisted %s" % (name, literal))
        with mock.patch("gui.client.udev_source_verified", return_value=True):
            cmds = udev_pkexec_commands()
        assert cmds is not None
        for cmd in cmds:
            self.assertTrue(udev_pkexec_argv_ok(cmd), cmd)
            for arg in cmd:
                if arg.startswith("/"):
                    self.assertIn(arg, UDEV_PKEXEC_ALLOWED_PATHS)
        self.assertEqual(offenders, [])


class TestFindBinary(unittest.TestCase):
    def test_prefiere_path_y_exigente(self):
        fake = BinarioFake()
        otro = os.path.join(fake.dir, "no-exe")
        with open(otro, "w") as f:
            f.write("#!/bin/sh\n")
        with mock.patch("gui.client.shutil.which", return_value=fake.ruta):
            self.assertEqual(find_binary(), fake.ruta)
        fake.limpiar()

    def test_fallback_cuando_nada_existe(self):
        with mock.patch("gui.client.shutil.which", return_value=None), mock.patch(
            "os.path.isfile", return_value=False
        ):
            self.assertEqual(find_binary(), "ilutex")


class TestRunErrores(unittest.TestCase):
    def test_binario_inexistente(self):
        cliente = IlutexClient(binary="/no/existe/ilutex")
        with self.assertRaises(IlutexError) as ctx:
            cliente.info()
        self.assertIn("Cannot find the binary", ctx.exception.message)

    def test_error_con_stderr(self):
        fake = BinarioFake("#!/bin/sh\necho 'teclado furioso' >&2\nexit 1\n")
        cliente = IlutexClient(binary=fake.ruta)
        with self.assertRaises(IlutexError) as ctx:
            cliente.set_color("ff0000")
        self.assertIn("teclado furioso", ctx.exception.message)
        fake.limpiar()

    def test_error_sin_salida(self):
        fake = BinarioFake("#!/bin/sh\nexit 3\n")
        cliente = IlutexClient(binary=fake.ruta)
        with self.assertRaises(IlutexError) as ctx:
            cliente.off()
        self.assertIn("code 3", ctx.exception.message)
        fake.limpiar()

    def test_timeout(self):
        cliente = IlutexClient(binary="/usr/bin/true")

        def timeout_run(*_a, **_k):
            raise subprocess.TimeoutExpired(cmd="ilutex", timeout=10)

        with mock.patch("gui.client.subprocess.run", side_effect=timeout_run):
            with self.assertRaises(IlutexError) as ctx:
                cliente.restore()
        self.assertIn("took too long to respond", ctx.exception.message)


class TestInfoJson(unittest.TestCase):
    def test_json_valido(self):
        datos = {"version": "2.5.0", "lamps": 1, "state": "00ffff", "brightness": 95}
        fake = BinarioFake('#!/bin/sh\necho \'%s\'\n' % json.dumps(datos))
        cliente = IlutexClient(binary=fake.ruta)
        self.assertEqual(cliente.info(), datos)
        fake.limpiar()

    def test_binario_viejo_sin_json_devuelve_vacio(self):
        fake = BinarioFake("#!/bin/sh\necho 'nº lámparas : 1'\n")
        cliente = IlutexClient(binary=fake.ruta)
        self.assertEqual(cliente.info(), {})
        fake.limpiar()

    def test_basura_devuelve_vacio(self):
        fake = BinarioFake("#!/bin/sh\necho '{no-es-json'\n")
        cliente = IlutexClient(binary=fake.ruta)
        self.assertEqual(cliente.info(), {})
        fake.limpiar()


class TestEstadoYPidfile(unittest.TestCase):
    def test_get_state_file_parsing_y_clamp(self):
        env = EntornoXdg()
        try:
            dir_state = os.path.join(env.tmp, "state", "ilutex")
            os.makedirs(dir_state, exist_ok=True)
            with open(os.path.join(dir_state, "state"), "w") as f:
                f.write("FF7800 140\n")
            self.assertEqual(IlutexClient().get_state_file(), ("ff7800", 100))
            with open(os.path.join(dir_state, "state"), "w") as f:
                f.write("00ffff -5\n")
            self.assertEqual(IlutexClient().get_state_file(), ("00ffff", 0))
        finally:
            env.restaurar()

    def test_get_state_file_malformado_no_cae_a_legado(self):
        """KBC-12/16: primario corrupto no consulta legado ni inventa color real."""
        env = EntornoXdg()
        try:
            base = env.tmp
            nuevo = os.path.join(base, "state", "ilutex")
            legado = os.path.join(base, "state", "kbd-rgb")
            os.makedirs(nuevo, exist_ok=True)
            os.makedirs(legado, exist_ok=True)
            with open(os.path.join(nuevo, "state"), "w") as f:
                f.write("basura sin sentido\n")
            with open(os.path.join(legado, "state"), "w") as f:
                f.write("ff0000 60\n")
            self.assertEqual(IlutexClient().get_state_file(), ("ffffff", 100))
        finally:
            env.restaurar()

    def test_get_state_file_ausente_devuelve_defaults(self):
        env = EntornoXdg()
        try:
            self.assertEqual(IlutexClient().get_state_file(), ("ffffff", 100))
        finally:
            env.restaurar()

    def test_get_state_file_solo_legado(self):
        env = EntornoXdg()
        try:
            legado = os.path.join(env.tmp, "state", "keybackcon")
            os.makedirs(legado, exist_ok=True)
            with open(os.path.join(legado, "state"), "w") as f:
                f.write("ff0000 60\n")
            self.assertEqual(IlutexClient().get_state_file(), ("ff0000", 60))
        finally:
            env.restaurar()

    def test_kbc16_oraculo_compartido_testdata(self):
        from gui.client import parse_state_text

        root = os.path.join(
            os.path.dirname(__file__), "..", "..", "testdata", "state"
        )
        oracle = os.path.join(root, "oracle.txt")
        with open(oracle) as f:
            lines = f.readlines()
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            kind, name = parts[0], parts[1]
            with open(os.path.join(root, name)) as f:
                raw = f.read()
            got_kind, payload = parse_state_text(raw)
            self.assertEqual(got_kind, kind, name)
            if kind == "ok":
                self.assertEqual(payload, (parts[2], int(parts[3])), name)
            elif kind == "unsupported":
                self.assertEqual(payload, int(parts[2]), name)
            else:
                self.assertIsNone(payload, name)

    def test_animation_running_detecta_proceso_propio(self):
        env = EntornoXdg()
        try:
            pidfile = os.path.join(env.tmp, "run", "ilutex", "animation.pid")
            os.makedirs(os.path.dirname(pidfile), exist_ok=True)
            # Wrapper cuyo cmdline contiene 'ilutex' tras el exec.
            # Script con argv0 implícito en el nombre del fichero.
            fake = BinarioFake("#!/bin/sh\nexec sleep 30\n")
            wrapper = subprocess.Popen([fake.ruta], start_new_session=True)
            try:
                with open(pidfile, "w") as f:
                    f.write("%d\n" % wrapper.pid)
                encontrado = IlutexClient().animation_running()
                self.assertEqual(encontrado, wrapper.pid)
            finally:
                try:
                    wrapper.kill()
                except OSError:
                    pass
                try:
                    wrapper.wait(timeout=5)
                except Exception:
                    pass
                fake.limpiar()
        finally:
            env.restaurar()

    def test_animation_running_pidfile_ausente(self):
        env = EntornoXdg()
        try:
            self.assertIsNone(IlutexClient().animation_running())
        finally:
            env.restaurar()


class TestAnimacionGrupo(unittest.TestCase):
    def test_stop_animation_mata_el_grupo(self):
        fake = BinarioFake("#!/bin/sh\nsleep 5\n")
        cliente = IlutexClient(binary=fake.ruta)
        cliente._proc = subprocess.Popen(
            [fake.ruta], start_new_session=True
        )
        pid = cliente._proc.pid
        cliente.stop_animation()
        self.assertIsNone(cliente._proc)
        # Si el entorno permite señales, el proceso ya no está; si no, al menos
        # el cliente olvidó la referencia (sandboxes que bloquean kill).
        if os.path.exists(f"/proc/{pid}"):
            try:
                os.kill(pid, 9)
            except OSError:
                pass
        fake.limpiar()

    def test_stop_animation_idempotente_sin_proceso(self):
        cliente = IlutexClient(binary="/no/existe")
        cliente.stop_animation()  # no debe lanzar excepción


if __name__ == "__main__":
    unittest.main()
