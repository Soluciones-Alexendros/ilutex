//! Bench criterion del camino puro de `ilutex info` (sin ioctl ni hardware).
//!
//! Mide parseo del informe de atributos y la construcción de la petición
//! `HIDIOCGFEATURE`. No abre `/dev/hidraw*` ni exige el AERO X16.
//!
//! Ejecutar: `cargo bench --bench info_bench`.
//!
//! Nota: ver `set_bench.rs` sobre `cfg(test)` + `#[path]` y `unused_imports`.

#![allow(dead_code)]
#![allow(missing_docs)]
#![allow(unused_imports)]

#[path = "../src/color.rs"]
mod color;
#[path = "../src/protocol.rs"]
mod protocol;

use std::hint::black_box;

use criterion::{criterion_group, criterion_main, Criterion};
use protocol::{
    hid_ioctl_request, parse_attrs, ATTRS_LAMP_COUNT_OFFSET, ATTRS_LAMP_KIND_OFFSET,
    ATTRS_REPORT_LEN, HIDIOCGFEATURE_NR,
};

fn attrs_buf(count: u16, kind: u32) -> Vec<u8> {
    let mut b = vec![0u8; ATTRS_REPORT_LEN];
    b[ATTRS_LAMP_COUNT_OFFSET..=ATTRS_LAMP_COUNT_OFFSET + 1].copy_from_slice(&count.to_le_bytes());
    b[ATTRS_LAMP_KIND_OFFSET..ATTRS_LAMP_KIND_OFFSET + 4].copy_from_slice(&kind.to_le_bytes());
    b
}

fn info_pure_path(c: &mut Criterion) {
    let mut group = c.benchmark_group("info_pure");
    let sample = attrs_buf(1, 0x1122_3344);

    group.bench_function("parse_attrs", |b| {
        b.iter(|| parse_attrs(black_box(sample.as_slice())).unwrap());
    });

    group.bench_function("hid_ioctl_request_get_feature", |b| {
        let mut t = 0u32;
        b.iter(|| {
            t = t.wrapping_add(1);
            hid_ioctl_request(
                black_box(HIDIOCGFEATURE_NR),
                black_box(usize::try_from(t % 64 + 1).unwrap()),
            )
            .unwrap()
        });
    });

    group.finish();
}

criterion_group!(benches, info_pure_path);
criterion_main!(benches);
