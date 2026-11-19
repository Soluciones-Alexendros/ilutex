//! Dispositivo `LampArray`: localiza el hidraw por firma y perfil USB,
//! transporta informes con `HidTransport` (`HidRaw` es el único punto con FFI
//! ioctl) y expone atributos, color y efectos autónomos.

use std::fs;
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};

use crate::protocol::{
    autonomous_report, color_report, hid_ioctl_request, parse_attrs, ATTRS_REPORT_LEN,
    HIDIOCGFEATURE_NR, HIDIOCSFEATURE_NR, REPORT_DESCRIPTOR_SUBPATH, REPORT_ID_ATTRS,
};

// SAFETY: `ioctl` es libc con ABI estable.
unsafe extern "C" {
    fn ioctl(fd: i32, request: u64, arg: *mut u8) -> i32;
}

/// Mensaje de error cuando el teclado se desconecta durante la animación.
pub const DEVICE_GONE_MSG: &str = "el teclado parece haberse desconectado";

/// VID/PID del AERO X16 admitido (coinciden con la regla udev).
pub const SUPPORTED_VID: u16 = 0x0414;
pub const SUPPORTED_PID: u16 = 0x8104;
/// Variables de entorno para sobrescribir VID/PID.
#[allow(dead_code)]
const ENV_VID: &str = "ILUTEX_VID";
#[allow(dead_code)]
const ENV_PID: &str = "ILUTEX_PID";

/// Devuelve el VID a usar. Lee `ILUTEX_VID` (hex u16) si esta definida; si no, `SUPPORTED_VID`.
/// Formato aceptado: hex con o sin prefijo 0x (ej: 0414 o 0x0414).
#[allow(dead_code)]
pub fn supported_vid() -> u16 {
    std::env::var(ENV_VID)
        .ok()
        .and_then(|s| parse_u16_hex(&s).ok())
        .unwrap_or(SUPPORTED_VID)
}

/// Devuelve el PID a usar. Lee `ILUTEX_PID` (hex u16) si esta definida; si no, `SUPPORTED_PID`.
/// Formato aceptado: hex con o sin prefijo 0x (ej: 8104 o 0x8104).
#[allow(dead_code)]
pub fn supported_pid() -> u16 {
    std::env::var(ENV_PID)
        .ok()
        .and_then(|s| parse_u16_hex(&s).ok())
        .unwrap_or(SUPPORTED_PID)
}

/// Parsea hex string a u16. Acepta prefijo 0x opcional.
#[allow(dead_code)]
fn parse_u16_hex(s: &str) -> Result<u16, &'static str> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    u16::from_str_radix(s, 16).map_err(|_| "u16 hex invalido")
}

const ENODEV: i32 = 19;
const ENXIO: i32 = 6;
const ENOENT: i32 = 2;

/// Error de informe que conserva el errno original bajo un mensaje legible.
#[derive(Debug)]
struct DeviceReportError {
    code: Option<i32>,
    msg: String,
}

impl std::fmt::Display for DeviceReportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.msg)
    }
}

impl std::error::Error for DeviceReportError {}

/// Indica si `e` corresponde a un dispositivo desaparecido
/// (ENODEV/ENXIO/ENOENT), incluso tras envolver el mensaje.
pub fn is_device_gone(e: &io::Error) -> bool {
    if matches!(e.raw_os_error(), Some(ENODEV | ENXIO | ENOENT)) {
        return true;
    }
    e.get_ref()
        .and_then(|r| r.downcast_ref::<DeviceReportError>())
        .is_some_and(|d| matches!(d.code, Some(ENODEV | ENXIO | ENOENT)))
}

fn report_error(path: &Path, action: &str, id: u8, e: &io::Error) -> io::Error {
    let msg = format!(
        "no se pudo {action} el informe {id} de {}: {e}",
        path.display()
    );
    let code = e.raw_os_error();
    io::Error::new(e.kind(), DeviceReportError { code, msg })
}

/// Acceso a feature reports HID; permite probar `Lamp` sin hardware.
pub trait HidTransport {
    /// Lee hasta `len` bytes del informe `id` (`get_feature`).
    fn get_feature(&mut self, id: u8, len: usize) -> io::Result<Vec<u8>>;
    /// Escribe un informe completo (`set_feature`).
    fn set_feature(&mut self, report: &[u8]) -> io::Result<()>;
}

/// Transporte real sobre `/dev/hidrawN` (único punto con ioctl FFI).
pub struct HidRaw {
    file: fs::File,
    path: PathBuf,
}

impl HidRaw {
    /// Abre `path` en lectura/escritura.
    pub fn open(path: PathBuf) -> io::Result<Self> {
        let file = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .map_err(|e| {
                io::Error::new(
                    e.kind(),
                    format!(
                        "no se pudo abrir {}: {e} (puede que la regla udev uaccess no funcione)",
                        path.display()
                    ),
                )
            })?;
        Ok(HidRaw { file, path })
    }
}

impl HidTransport for HidRaw {
    fn get_feature(&mut self, id: u8, len: usize) -> io::Result<Vec<u8>> {
        let request = hid_ioctl_request(HIDIOCGFEATURE_NR, len)
            .map_err(|e| report_error(&self.path, "leer", id, &e))?;
        let mut buf = vec![0u8; len];
        buf[0] = id;
        // SAFETY: buffer de `len` bytes; la petición codifica ese `len`.
        let r = unsafe { ioctl(self.file.as_raw_fd(), request, buf.as_mut_ptr()) };
        if r < 0 {
            return Err(report_error(
                &self.path,
                "leer",
                id,
                &io::Error::last_os_error(),
            ));
        }
        #[allow(clippy::cast_sign_loss)]
        let got = r as usize;
        if got == 0 || got > len {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "longitud de informe inválida ({got}) al leer id {id} de {}",
                    self.path.display()
                ),
            ));
        }
        buf.truncate(got);
        if buf.first().copied() != Some(id) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "el informe leído de {} no tiene el id {id} esperado",
                    self.path.display()
                ),
            ));
        }
        Ok(buf)
    }

    fn set_feature(&mut self, report: &[u8]) -> io::Result<()> {
        let id = report.first().copied().unwrap_or(0);
        let request = hid_ioctl_request(HIDIOCSFEATURE_NR, report.len())
            .map_err(|e| report_error(&self.path, "escribir", id, &e))?;
        // SAFETY: petición = report.len(); el kernel solo lee el buffer.
        let r = unsafe { ioctl(self.file.as_raw_fd(), request, report.as_ptr().cast_mut()) };
        if r < 0 {
            return Err(report_error(
                &self.path,
                "escribir",
                id,
                &io::Error::last_os_error(),
            ));
        }
        Ok(())
    }
}

/// Dispositivo `LampArray` con su transporte y número de lámparas.
pub struct Lamp<T: HidTransport = HidRaw> {
    dev: T,
    count: u16,
}

/// Lee VID/PID USB del hidraw vía uevent (`HID_ID=bustype:vid:pid`).
fn usb_ids_for_hidraw(sys_hidraw: &Path, hidraw_name: &str) -> Option<(u16, u16)> {
    let uevent = sys_hidraw.join(hidraw_name).join("device/uevent");
    let text = fs::read_to_string(uevent).ok()?;
    for line in text.lines() {
        let Some(rest) = line.strip_prefix("HID_ID=") else {
            continue;
        };
        // Formato típico: 0003:00000414:00008104
        let parts: Vec<&str> = rest.split(':').collect();
        if parts.len() < 3 {
            continue;
        }
        let vid = u16::try_from(u32::from_str_radix(parts[1], 16).ok()?).ok()?;
        let pid = u16::try_from(u32::from_str_radix(parts[2], 16).ok()?).ok()?;
        return Some((vid, pid));
    }
    None
}

fn matches_supported_profile(sys_hidraw: &Path, hidraw_name: &str) -> bool {
    match usb_ids_for_hidraw(sys_hidraw, hidraw_name) {
        Some((vid, pid)) => vid == SUPPORTED_VID && pid == SUPPORTED_PID,
        // Sin uevent legible: no escribir informes específicos.
        None => false,
    }
}

fn lamp_not_found() -> io::Error {
    io::Error::new(
        io::ErrorKind::NotFound,
        "no se encontró el dispositivo LampArray admitido (VID 0414 / PID 8104); \
         ¿está cargada la regla udev? mira con 'ilutex info'",
    )
}

/// Barrido de `sys_hidraw` (normalmente `/sys/class/hidraw`) buscando firma
/// `LampArray` y VID/PID admitidos. Inyectable en tests sin sysfs real.
fn find_in(sys_hidraw: &Path) -> io::Result<PathBuf> {
    let mut found: Vec<PathBuf> = Vec::new();
    // Sin el directorio (p. ej. contenedores sin sysfs HID) → mismo NotFound
    // con LampArray que el barrido vacío; no filtrar el errno crudo.
    let entries = match fs::read_dir(sys_hidraw) {
        Ok(it) => it,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Err(lamp_not_found()),
        Err(e) => return Err(e),
    };
    for e in entries {
        let e = e?;
        let name = e.file_name().to_string_lossy().into_owned();
        if !name.starts_with("hidraw") {
            continue;
        }
        if !matches_supported_profile(sys_hidraw, &name) {
            continue;
        }
        let desc = e.path().join(REPORT_DESCRIPTOR_SUBPATH);
        if let Ok(d) = fs::read(&desc) {
            let sig = crate::protocol::device_signature();
            if d.windows(sig.len()).any(|w| w == sig.as_slice()) {
                found.push(PathBuf::from(format!("/dev/{name}")));
            }
        }
    }
    found.sort();
    found.into_iter().next().ok_or_else(lamp_not_found)
}

impl Lamp<HidRaw> {
    /// Busca el hidraw con firma `LampArray` y VID/PID admitidos.
    pub fn find() -> io::Result<PathBuf> {
        find_in(Path::new("/sys/class/hidraw"))
    }

    /// Localiza, abre y consulta los atributos del dispositivo.
    pub fn open() -> io::Result<Self> {
        let path = Self::find()?;
        let mut lamp = Self::with_transport(HidRaw::open(path)?);
        lamp.count = lamp.attrs()?.0.max(1);
        Ok(lamp)
    }
}

impl<T: HidTransport> Lamp<T> {
    /// Crea un `Lamp` con un transporte inyectado (tests y usos internos).
    pub(crate) fn with_transport(dev: T) -> Self {
        Lamp { dev, count: 1 }
    }

    /// Lee el informe de atributos: `(LampCount, LampArrayKind)`.
    pub fn attrs(&mut self) -> io::Result<(u16, u32)> {
        let b = self.dev.get_feature(REPORT_ID_ATTRS, ATTRS_REPORT_LEN)?;
        if b.len() < ATTRS_REPORT_LEN.min(19) {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("informe de atributos demasiado corto ({} bytes)", b.len()),
            ));
        }
        parse_attrs(&b)
    }

    /// Activa o desactiva los efectos autónomos del firmware.
    pub fn autonomous(&mut self, on: bool) -> io::Result<()> {
        self.dev.set_feature(&autonomous_report(on))
    }

    /// Escribe el color de la zona completa con la intensidad máxima.
    pub fn color(&mut self, rgb: crate::color::Rgb) -> io::Result<()> {
        self.dev.set_feature(&color_report(self.count, rgb))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fake {
        attrs: Vec<u8>,
        writes: Vec<Vec<u8>>,
        get_len: Option<usize>,
    }

    impl Fake {
        fn new(attrs: Vec<u8>) -> Self {
            Fake {
                attrs,
                writes: Vec::new(),
                get_len: None,
            }
        }
    }

    impl HidTransport for Fake {
        fn get_feature(&mut self, _id: u8, len: usize) -> io::Result<Vec<u8>> {
            if let Some(got) = self.get_len {
                if got == 0 || got > len {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "longitud de informe inválida",
                    ));
                }
                let mut b = vec![0u8; got];
                let n = self.attrs.len().min(got);
                b[..n].copy_from_slice(&self.attrs[..n]);
                return Ok(b);
            }
            let mut b = vec![0u8; len];
            let n = self.attrs.len().min(len);
            b[..n].copy_from_slice(&self.attrs[..n]);
            Ok(b)
        }

        fn set_feature(&mut self, report: &[u8]) -> io::Result<()> {
            self.writes.push(report.to_vec());
            Ok(())
        }
    }

    fn attrs_buf(count: u16, kind: u32) -> Vec<u8> {
        let mut b = vec![0u8; 23];
        b[0] = REPORT_ID_ATTRS;
        b[1..3].copy_from_slice(&count.to_le_bytes());
        b[15..19].copy_from_slice(&kind.to_le_bytes());
        b
    }

    #[test]
    fn attrs_consulta_el_informe_1() {
        let mut lamp = Lamp::with_transport(Fake::new(attrs_buf(5, 1)));
        assert_eq!(lamp.attrs().unwrap(), (5, 1));
    }

    #[test]
    fn color_reporta_una_sola_zona() {
        let mut lamp = Lamp::with_transport(Fake::new(attrs_buf(1, 0)));
        lamp.color((0x11, 0x22, 0x33)).unwrap();
        assert_eq!(
            lamp.dev.writes.last().unwrap(),
            &[5, 1, 0, 0, 0, 0, 0x11, 0x22, 0x33, 0xff]
        );
    }

    #[test]
    fn color_usa_count_menos_uno_en_la_ultima_lampara() {
        let mut lamp = Lamp::with_transport(Fake::new(attrs_buf(3, 0)));
        lamp.count = 3;
        lamp.color((0xaa, 0xbb, 0xcc)).unwrap();
        assert_eq!(
            lamp.dev.writes.last().unwrap(),
            &[5, 1, 0, 0, 2, 0, 0xaa, 0xbb, 0xcc, 0xff]
        );
    }

    #[test]
    fn autonomous_escribe_el_reporte_6() {
        let mut lamp = Lamp::with_transport(Fake::new(attrs_buf(1, 0)));
        lamp.autonomous(true).unwrap();
        assert_eq!(lamp.dev.writes.last().unwrap(), &[6, 1]);
        lamp.autonomous(false).unwrap();
        assert_eq!(lamp.dev.writes.last().unwrap(), &[6, 0]);
    }

    #[test]
    fn clasifica_desconexion_por_errno() {
        for code in [19, 6, 2] {
            assert!(is_device_gone(&io::Error::from_raw_os_error(code)));
        }
        assert!(!is_device_gone(&io::Error::from_raw_os_error(13)));
        assert!(!is_device_gone(&io::Error::other("sin errno")));
    }

    #[test]
    fn clasifica_desconexion_tras_envolver_mensaje() {
        let original = io::Error::from_raw_os_error(ENODEV);
        let wrapped = report_error(Path::new("/dev/hidraw0"), "escribir", 5, &original);
        assert!(is_device_gone(&wrapped));
        assert!(wrapped.to_string().contains("hidraw0"));
    }

    #[test]
    fn informe_corto_se_rechaza_en_attrs() {
        let mut fake = Fake::new(attrs_buf(1, 0));
        fake.get_len = Some(5);
        let mut lamp = Lamp::with_transport(fake);
        let err = lamp.attrs().unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn hidraw_open_ruta_inexistente_explica_udev() {
        let Err(err) = HidRaw::open(PathBuf::from("/dev/ilutex-no-existe-xyz")) else {
            panic!("se esperaba error al abrir ruta inexistente");
        };
        let msg = err.to_string();
        assert!(msg.contains("no se pudo abrir"), "{msg}");
        assert!(msg.contains("ilutex-no-existe-xyz"), "{msg}");
    }

    #[test]
    fn find_sin_aero_x16_es_not_found_o_hidraw() {
        // En CI sin el teclado: NotFound (cubre el barrido de sysfs). Con
        // hardware real: Ok bajo /dev/hidraw*. Ambos cierran el camino.
        match Lamp::find() {
            Err(e) => {
                assert_eq!(e.kind(), io::ErrorKind::NotFound, "{e}");
                assert!(e.to_string().contains("LampArray"), "{e}");
            }
            Ok(p) => {
                let s = p.to_string_lossy();
                assert!(s.contains("hidraw"), "{s}");
            }
        }
    }

    fn fixture_sys_hidraw(tag: &str) -> PathBuf {
        let dir = PathBuf::from(format!(
            "/tmp/ilutex-hidraw-{}-{}-{tag}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write_hidraw_node(sys: &Path, name: &str, hid_id: Option<&str>, desc: Option<&[u8]>) {
        let node = sys.join(name).join("device");
        fs::create_dir_all(&node).unwrap();
        if let Some(id) = hid_id {
            fs::write(
                node.join("uevent"),
                format!("DRIVER=hid-generic\nHID_ID={id}\nHID_NAME=fixture\n"),
            )
            .unwrap();
        }
        if let Some(bytes) = desc {
            fs::write(node.join("report_descriptor"), bytes).unwrap();
        }
    }

    #[test]
    fn find_in_sin_directorio_es_not_found_lamparray() {
        let missing = PathBuf::from(format!(
            "/tmp/ilutex-hidraw-missing-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        let _ = fs::remove_dir_all(&missing);
        let err = find_in(&missing).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::NotFound, "{err}");
        assert!(err.to_string().contains("LampArray"), "{err}");
    }

    #[test]
    fn find_in_vacio_y_nodos_ajenos_es_not_found() {
        let sys = fixture_sys_hidraw("empty");
        fs::create_dir_all(sys.join("other")).unwrap();
        write_hidraw_node(
            &sys,
            "hidraw0",
            Some("0003:00009999:00009999"),
            Some(&[0x00, 0x01]),
        );
        write_hidraw_node(&sys, "hidraw1", Some("0003:bad"), Some(&[0x05, 0x59]));
        write_hidraw_node(
            &sys,
            "hidraw2",
            None,
            Some(crate::protocol::DEVICE_SIGNATURE),
        );
        let err = find_in(&sys).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::NotFound, "{err}");
        assert!(err.to_string().contains("LampArray"), "{err}");
        let _ = fs::remove_dir_all(&sys);
    }

    #[test]
    fn find_in_elige_hidraw_con_vid_pid_y_firma() {
        let _guard = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        unsafe {
            std::env::remove_var("ILUTEX_HID_SIGNATURE");
        }

        let sys = fixture_sys_hidraw("match");
        // Candidato válido pero sin firma → se ignora.
        write_hidraw_node(
            &sys,
            "hidraw3",
            Some("0003:00000414:00008104"),
            Some(&[0xaa, 0xbb]),
        );
        // Firma correcta y VID/PID admitidos → gana (menor nombre tras sort).
        let mut desc = vec![0x00, 0xff];
        desc.extend_from_slice(crate::protocol::DEVICE_SIGNATURE);
        desc.push(0x11);
        write_hidraw_node(&sys, "hidraw9", Some("0003:00000414:00008104"), Some(&desc));
        write_hidraw_node(&sys, "hidraw8", Some("0003:00000414:00008104"), Some(&desc));
        // Líneas uevent basura + HID_ID válido al final (menor nombre gana).
        write_hidraw_node(&sys, "hidraw7", Some("0003:00000414:00008104"), Some(&desc));
        fs::write(
            sys.join("hidraw7/device/uevent"),
            "FOO=1\nHID_ID=0003:00000414:00008104\n",
        )
        .unwrap();

        let path = find_in(&sys).unwrap();
        assert_eq!(path, PathBuf::from("/dev/hidraw7"));
        assert!(matches_supported_profile(&sys, "hidraw7"));
        assert_eq!(
            usb_ids_for_hidraw(&sys, "hidraw7"),
            Some((SUPPORTED_VID, SUPPORTED_PID))
        );
        assert_eq!(usb_ids_for_hidraw(&sys, "hidraw_ausente"), None);
        let _ = fs::remove_dir_all(&sys);
    }

    #[test]
    fn usb_ids_rechaza_hid_id_mal_formado() {
        let sys = fixture_sys_hidraw("uevent");
        write_hidraw_node(&sys, "hidraw0", Some("solo-dos:partes"), None);
        assert_eq!(usb_ids_for_hidraw(&sys, "hidraw0"), None);
        write_hidraw_node(&sys, "hidraw1", Some("0003:gggg:00008104"), None);
        assert_eq!(usb_ids_for_hidraw(&sys, "hidraw1"), None);
        write_hidraw_node(&sys, "hidraw2", Some("0003:00000414:zzzz"), None);
        assert_eq!(usb_ids_for_hidraw(&sys, "hidraw2"), None);
        assert!(!matches_supported_profile(&sys, "hidraw2"));
        let _ = fs::remove_dir_all(&sys);
    }

    #[test]
    fn hidraw_get_feature_falla_en_dispositivo_no_hid() {
        // /dev/zero abre en RW pero no habla HID: cubre el errno de ioctl.
        let Ok(mut h) = HidRaw::open(PathBuf::from("/dev/zero")) else {
            return;
        };
        let err = h
            .get_feature(REPORT_ID_ATTRS, ATTRS_REPORT_LEN)
            .unwrap_err();
        assert!(!err.to_string().is_empty(), "{err}");
        let err = h.set_feature(&[REPORT_ID_ATTRS, 0]).unwrap_err();
        assert!(!err.to_string().is_empty(), "{err}");
    }
}

#[cfg(test)]
mod vid_pid_override_tests {
    use super::*;

    #[test]
    fn vid_override_env_var() {
        let _guard = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);

        // Test 1: sin env var -> valor por defecto
        unsafe {
            std::env::remove_var("ILUTEX_VID");
        }
        assert_eq!(supported_vid(), SUPPORTED_VID);

        // Test 2: con env var valido (hex sin 0x)
        unsafe {
            std::env::set_var("ILUTEX_VID", "1234");
        }
        assert_eq!(supported_vid(), 0x1234);

        // Test 3: con env var con prefijo 0x
        unsafe {
            std::env::set_var("ILUTEX_VID", "0x1234");
        }
        assert_eq!(supported_vid(), 0x1234);

        // Test 4: env var invalido -> fallback a default
        unsafe {
            std::env::set_var("ILUTEX_VID", "gggg");
        }
        assert_eq!(supported_vid(), SUPPORTED_VID);

        unsafe {
            std::env::remove_var("ILUTEX_VID");
        }
    }

    #[test]
    fn pid_override_env_var() {
        let _guard = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);

        // Test 1: sin env var -> valor por defecto
        unsafe {
            std::env::remove_var("ILUTEX_PID");
        }
        assert_eq!(supported_pid(), SUPPORTED_PID);

        // Test 2: con env var valido (hex sin 0x)
        unsafe {
            std::env::set_var("ILUTEX_PID", "5678");
        }
        assert_eq!(supported_pid(), 0x5678);

        // Test 3: con env var con prefijo 0x
        unsafe {
            std::env::set_var("ILUTEX_PID", "0x5678");
        }
        assert_eq!(supported_pid(), 0x5678);

        // Test 4: env var invalido -> fallback a default
        unsafe {
            std::env::set_var("ILUTEX_PID", "zzzz");
        }
        assert_eq!(supported_pid(), SUPPORTED_PID);

        unsafe {
            std::env::remove_var("ILUTEX_PID");
        }
    }

    #[test]
    fn default_values_sin_env() {
        let _guard = crate::TEST_ENV_LOCK
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);

        unsafe {
            std::env::remove_var("ILUTEX_VID");
            std::env::remove_var("ILUTEX_PID");
        }
        assert_eq!(supported_vid(), SUPPORTED_VID);
        assert_eq!(supported_pid(), SUPPORTED_PID);
    }
}
