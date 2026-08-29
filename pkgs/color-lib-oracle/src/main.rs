// Reference implementation of the color operations that lib/color-lib/
// implements in pure Nix. Builds as an ordinary native binary -- no WASM, no
// Determinate Nix, no builtins.wasm.
//
// This exists to generate lib/color-lib/golden.json, the fixture the pure-Nix
// implementation is tested against. The math here comes from the `palette`
// crate, which is what the previous WASM implementation wrapped, so the golden
// values carry over the same semantics that produced the committed theme.
//
// Usage: color-lib-oracle < cases.json > golden.json
//
// Input is a JSON array of case objects, each { id, op, ... }. Output is the
// same array with a "expected" field added to every case. Keeping the case
// list in a separate file means regenerating the fixture never depends on
// this program's notion of what should be tested.

use palette::{color_difference::Wcag21RelativeContrast, FromColor, IntoColor, Okhsl, Okhsv, Srgb};
use serde_json::{json, Map, Value};
use std::io::Read;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Space {
    Srgb,
    Okhsl,
    Okhsv,
}

#[derive(Clone)]
struct Color {
    space: Space,
    c1: f64,
    c2: f64,
    c3: f64,
    alpha: f64,
}

impl Color {
    fn to_srgb(&self) -> Color {
        let (r, g, b) = match self.space {
            Space::Srgb => (self.c1, self.c2, self.c3),
            Space::Okhsl => {
                let hsl: Okhsl<f64> = Okhsl::new(self.c1 * 360.0, self.c2, self.c3);
                let rgb: Srgb<f64> = Srgb::from_color(hsl);
                (rgb.red, rgb.green, rgb.blue)
            }
            Space::Okhsv => {
                let hsv: Okhsv<f64> = Okhsv::new(self.c1 * 360.0, self.c2, self.c3);
                let rgb: Srgb<f64> = Srgb::from_color(hsv);
                (rgb.red, rgb.green, rgb.blue)
            }
        };
        Color {
            space: Space::Srgb,
            c1: r.clamp(0.0, 1.0),
            c2: g.clamp(0.0, 1.0),
            c3: b.clamp(0.0, 1.0),
            alpha: self.alpha,
        }
    }

    fn to_okhsl(&self) -> Color {
        let s = self.to_srgb();
        let hsl: Okhsl<f64> = Srgb::new(s.c1, s.c2, s.c3).into_color();
        Color {
            space: Space::Okhsl,
            c1: hsl.hue.into_positive_degrees() / 360.0,
            c2: hsl.saturation,
            c3: hsl.lightness,
            alpha: self.alpha,
        }
    }

    fn to_okhsv(&self) -> Color {
        let s = self.to_srgb();
        let hsv: Okhsv<f64> = Srgb::new(s.c1, s.c2, s.c3).into_color();
        Color {
            space: Space::Okhsv,
            c1: hsv.hue.into_positive_degrees() / 360.0,
            c2: hsv.saturation,
            c3: hsv.value,
            alpha: self.alpha,
        }
    }

    fn get(&self, ch: &str) -> f64 {
        match (self.space, ch) {
            (_, "h") => self.c1,
            (Space::Srgb, "r") => self.c1,
            (Space::Srgb, "g") => self.c2,
            (Space::Srgb, "b") => self.c3,
            (Space::Okhsl, "s") | (Space::Okhsv, "s") => self.c2,
            (Space::Okhsl, "l") => self.c3,
            (Space::Okhsv, "v") => self.c3,
            (_, "a") => self.alpha,
            _ => panic!("bad channel '{ch}' for this space"),
        }
    }

    fn set(&self, ch: &str, v: f64) -> Color {
        let mut c = self.clone();
        match (self.space, ch) {
            (_, "h") => c.c1 = v,
            (Space::Srgb, "r") => c.c1 = v,
            (Space::Srgb, "g") => c.c2 = v,
            (Space::Srgb, "b") => c.c3 = v,
            (Space::Okhsl, "s") | (Space::Okhsv, "s") => c.c2 = v,
            (Space::Okhsl, "l") => c.c3 = v,
            (Space::Okhsv, "v") => c.c3 = v,
            (_, "a") => c.alpha = v,
            _ => panic!("bad channel '{ch}' for this space"),
        }
        c
    }
}

fn hex_to_srgb(hex: &str) -> Color {
    let hex = hex.strip_prefix('#').unwrap_or(hex).to_ascii_uppercase();
    let expanded = match hex.len() {
        3 | 4 => hex.chars().flat_map(|c| [c, c]).collect::<String>(),
        6 | 8 => hex.clone(),
        n => panic!("invalid hex length {n}: '{hex}'"),
    };
    let byte = |i: usize| -> f64 {
        u8::from_str_radix(&expanded[i..i + 2], 16).expect("bad hex byte") as f64 / 255.0
    };
    Color {
        space: Space::Srgb,
        c1: byte(0),
        c2: byte(2),
        c3: byte(4),
        alpha: if expanded.len() == 8 { byte(6) } else { 1.0 },
    }
}

fn srgb_to_hex(c: &Color) -> String {
    let s = c.to_srgb();
    // Round-half-up to match the previous implementation exactly.
    let b = |v: f64| -> u8 { (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8 };
    let (r, g, bl, a) = (b(s.c1), b(s.c2), b(s.c3), b(s.alpha));
    if a == 255 {
        format!("{r:02X}{g:02X}{bl:02X}")
    } else {
        format!("{r:02X}{g:02X}{bl:02X}{a:02X}")
    }
}

fn contrast(a: &Color, b: &Color) -> f64 {
    let (a, b) = (a.to_srgb(), b.to_srgb());
    Srgb::new(a.c1, a.c2, a.c3).relative_contrast(Srgb::new(b.c1, b.c2, b.c3))
}

/// Space a channel name belongs to. Mirrors the pure-Nix API, where the
/// operation name encodes the space (setOkhslLightness -> okhsl/l).
fn space_of(name: &str) -> (Space, &'static str) {
    match name {
        "okhsl_h" => (Space::Okhsl, "h"),
        "okhsl_s" => (Space::Okhsl, "s"),
        "okhsl_l" => (Space::Okhsl, "l"),
        "okhsv_h" => (Space::Okhsv, "h"),
        "okhsv_s" => (Space::Okhsv, "s"),
        "okhsv_v" => (Space::Okhsv, "v"),
        _ => panic!("unknown channel spec '{name}'"),
    }
}

fn to_space(c: &Color, s: Space) -> Color {
    match s {
        Space::Srgb => c.to_srgb(),
        Space::Okhsl => c.to_okhsl(),
        Space::Okhsv => c.to_okhsv(),
    }
}

fn f(c: &Map<String, Value>, k: &str) -> f64 {
    c.get(k)
        .unwrap_or_else(|| panic!("case missing '{k}'"))
        .as_f64()
        .unwrap_or_else(|| panic!("'{k}' is not a number"))
}

fn s<'a>(c: &'a Map<String, Value>, k: &str) -> &'a str {
    c.get(k)
        .unwrap_or_else(|| panic!("case missing '{k}'"))
        .as_str()
        .unwrap_or_else(|| panic!("'{k}' is not a string"))
}

fn run(case: &Map<String, Value>) -> Value {
    let op = s(case, "op");
    match op {
        // Channel reads return a float; everything else returns a hex string.
        "get" => {
            let (sp, ch) = space_of(s(case, "channel"));
            json!(to_space(&hex_to_srgb(s(case, "hex")), sp).get(ch))
        }
        "set" | "adjust" | "scale" => {
            let (sp, ch) = space_of(s(case, "channel"));
            let c = to_space(&hex_to_srgb(s(case, "hex")), sp);
            let old = c.get(ch);
            let new = match op {
                "set" => f(case, "value"),
                // Hue wraps; every other channel clamps.
                "adjust" => {
                    let v = old + f(case, "amount");
                    if ch == "h" { v.rem_euclid(1.0) } else { v.clamp(0.0, 1.0) }
                }
                _ => {
                    let v = old * f(case, "factor");
                    if ch == "h" { v.rem_euclid(1.0) } else { v.clamp(0.0, 1.0) }
                }
            };
            json!(srgb_to_hex(&c.set(ch, new)))
        }
        "mix" => {
            let (a, b) = (
                hex_to_srgb(s(case, "a")).to_okhsl(),
                hex_to_srgb(s(case, "b")).to_okhsl(),
            );
            let t = f(case, "factor");
            // Shortest hue path around the 0..1 circle.
            let d = b.c1 - a.c1;
            let (h1, h2) = if d.abs() > 0.5 {
                if d > 0.0 { (a.c1 + 1.0, b.c1) } else { (a.c1, b.c1 + 1.0) }
            } else {
                (a.c1, b.c1)
            };
            json!(srgb_to_hex(&Color {
                space: Space::Okhsl,
                c1: (h1 * (1.0 - t) + h2 * t).rem_euclid(1.0),
                c2: a.c2 * (1.0 - t) + b.c2 * t,
                c3: a.c3 * (1.0 - t) + b.c3 * t,
                alpha: a.alpha * (1.0 - t) + b.alpha * t,
            }))
        }
        "contrast" => json!(contrast(&hex_to_srgb(s(case, "a")), &hex_to_srgb(s(case, "b")))),
        "ensureContrast" => {
            let (text, bg) = (hex_to_srgb(s(case, "text")), hex_to_srgb(s(case, "bg")));
            let min = f(case, "minRatio");
            if contrast(&text, &bg) >= min {
                return json!(srgb_to_hex(&text));
            }
            let t = text.to_okhsl();
            // Dark backgrounds push the text lighter, light backgrounds darker.
            let lighter = bg.to_okhsl().c3 < 0.5;
            let (mut lo, mut hi) = if lighter { (t.c3, 1.0) } else { (0.0, t.c3) };
            // 24 iterations -> lightness resolution ~6e-8, far below one 8-bit step.
            for _ in 0..24 {
                let mid = (lo + hi) / 2.0;
                let cand = Color { space: Space::Okhsl, c1: t.c1, c2: t.c2, c3: mid, alpha: t.alpha };
                let ok = contrast(&cand, &bg) >= min;
                // Converge toward the original lightness while staying compliant.
                if ok == lighter { hi = mid } else { lo = mid }
            }
            json!(srgb_to_hex(&Color {
                space: Space::Okhsl,
                c1: t.c1,
                c2: t.c2,
                c3: (lo + hi) / 2.0,
                alpha: t.alpha,
            }))
        }
        "hexToRgb" => {
            let c = hex_to_srgb(s(case, "hex"));
            json!({ "r": c.c1, "g": c.c2, "b": c.c3, "alpha": c.alpha })
        }
        "rgbToHex" => json!(srgb_to_hex(&Color {
            space: Space::Srgb,
            c1: f(case, "r"),
            c2: f(case, "g"),
            c3: f(case, "b"),
            alpha: case.get("alpha").and_then(|v| v.as_f64()).unwrap_or(1.0),
        })),
        other => panic!("unknown op '{other}'"),
    }
}

fn main() {
    let mut input = String::new();
    std::io::stdin()
        .read_to_string(&mut input)
        .expect("failed to read stdin");
    let cases: Vec<Value> = serde_json::from_str(&input).expect("input is not a JSON array");

    let out: Vec<Value> = cases
        .into_iter()
        .map(|c| {
            let mut m = c.as_object().expect("case is not an object").clone();
            let expected = run(&m);
            m.insert("expected".to_string(), expected);
            Value::Object(m)
        })
        .collect();

    println!(
        "{}",
        serde_json::to_string_pretty(&Value::Array(out)).expect("failed to serialize")
    );
}
