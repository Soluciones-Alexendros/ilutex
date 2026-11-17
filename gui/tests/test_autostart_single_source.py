"""Autostart de la bandeja: una sola fuente de arranque.

La unidad de usuario `ilutex-tray.service` manda cuando está instalada; el
`.desktop` XDG queda como respaldo en sistemas sin systemd. Tener los dos
activos arrancaría dos bandejas, que es justo lo que estas pruebas impiden.
"""

import os
import tempfile
import unittest
from unittest import mock

from gui import settings


class TestAutostartUnaSolaFuente(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self._env = mock.patch.dict(
            os.environ, {"XDG_CONFIG_HOME": self._tmp.name}, clear=False
        )
        self._env.start()

    def tearDown(self):
        self._env.stop()
        self._tmp.cleanup()

    def _desktop(self):
        return os.path.join(self._tmp.name, "autostart", settings.AUTOSTART_NAME)

    def test_con_unidad_manda_systemctl(self):
        with mock.patch.object(settings, "_unit_installed", return_value=True), \
             mock.patch.object(
                 settings, "_systemctl", return_value=(True, "enabled")
             ) as fake:
            self.assertTrue(settings.is_autostart_enabled())
            fake.assert_called_with("is-enabled", settings.TRAY_UNIT)

    def test_desactivar_usa_la_unidad_y_borra_el_desktop(self):
        os.makedirs(os.path.dirname(self._desktop()), exist_ok=True)
        with open(self._desktop(), "w") as f:
            f.write(settings._autostart_content())
        with mock.patch.object(settings, "_unit_installed", return_value=True), \
             mock.patch.object(
                 settings, "_systemctl", return_value=(True, "")
             ) as fake:
            self.assertFalse(settings.set_autostart_enabled(False))
            fake.assert_called_with("disable", settings.TRAY_UNIT)
        self.assertFalse(os.path.exists(self._desktop()))

    def test_activar_con_unidad_no_crea_desktop(self):
        with mock.patch.object(settings, "_unit_installed", return_value=True), \
             mock.patch.object(settings, "_systemctl", return_value=(True, "")):
            self.assertTrue(settings.set_autostart_enabled(True))
        self.assertFalse(
            os.path.exists(self._desktop()),
            "la unidad ya arranca la bandeja: el .desktop sería un duplicado",
        )

    def test_sin_unidad_se_usa_el_desktop(self):
        with mock.patch.object(settings, "_unit_installed", return_value=False):
            self.assertTrue(settings.set_autostart_enabled(True))
            self.assertTrue(os.path.exists(self._desktop()))
            self.assertTrue(settings.is_autostart_enabled())
            self.assertFalse(settings.set_autostart_enabled(False))
            self.assertFalse(os.path.exists(self._desktop()))
            self.assertFalse(settings.is_autostart_enabled())

    def test_si_falla_systemctl_cae_al_desktop(self):
        with mock.patch.object(settings, "_unit_installed", return_value=True), \
             mock.patch.object(settings, "_systemctl", return_value=(False, "")):
            self.assertTrue(
                settings.set_autostart_enabled(True),
                "sin systemd útil debe quedar el respaldo XDG",
            )
        self.assertTrue(os.path.exists(self._desktop()))


if __name__ == "__main__":
    unittest.main()
