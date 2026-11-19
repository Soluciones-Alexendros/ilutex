//! Bench criterion del camino puro de `ilutex set` (sin ioctl ni hardware).
//!
//! Mide parseo de color, escala de brillo y construcción del informe HID
//! de color / autónomo. El presupuesto de 50 ms p95 de `ilutex set` contra
//! el AERO X16 es medición **manual** de hardware; este bench no la exige
//! y no debe fallar CI por ausencia de dispositivo.
//!
//! Ejecutar: `cargo bench --bench set_bench`.
//!
//! Nota: `cargo` habilita `cfg(test)` al compilar benches; los `#[cfg(test)]`
//! de los módulos incluidos con `#[path]` se compilan pero sus `#[test]` no
//! cuentan como usos → `unused_imports`. Se permite a nivel de crate del bench.

#![allow(dead_code)]
#![allow(missing_docs)]
#![allow(unused_imports)]

#[path = "../src/color.rs"]
mod color;
#[path = "../src/protocol.rs"]
mod protocol;

use std::hint::black_box;

use color::{parse_color, scale};
use criterion::{criterion_group, criterion_main, Criterion};
use protocol::{autonomous_report, color_report};

const COLORS: [&str; 4] = ["ff6400", "#00ff00", "cyan", "A1b2C3"];
const RGBS: [(u8, u8, u8); 4] = [(255, 100, 0), (0, 255, 128), (17, 34, 51), (255, 255, 255)];

fn set_pure_path(c: &mut Criterion) {
    let mut group = c.benchmark_group("set_pure");

    group.bench_function("parse_color", |b| {
        let mut t = 0u32;
        b.iter(|| {
            t = t.wrapping_add(1);
            let s = COLORS[usize::try_from(t % 4).unwrap()];
            parse_color(black_box(s)).unwrap()
        });
    });

    group.bench_function("scale_and_color_report", |b| {
        let mut t = 0u32;
        b.iter(|| {
            t = t.wrapping_add(1);
            let rgb = RGBS[usize::try_from(t % 4).unwrap()];
            let scaled = scale(black_box(rgb), black_box(t % 101));
            color_report(
                black_box(u16::try_from(t % 1024).unwrap().max(1)),
                black_box(scaled),
            )
        });
    });

    group.bench_function("autonomous_report", |b| {
        let mut t = 0u32;
        b.iter(|| {
            t = t.wrapping_add(1);
            autonomous_report(black_box(t.is_multiple_of(2)))
        });
    });

    group.finish();
}

criterion_group!(benches, set_pure_path);
criterion_main!(benches);
