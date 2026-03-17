use nix_wasm_rust::Value;
use palette::{FromColor, IntoColor, Okhsl, Okhsv, Srgb};

// Color string format:  "space:c1:c2:c3:alpha"
//
//   srgb   c1=r  c2=g  c3=b   all 0‑1
//   okhsl  c1=h  c2=s  c3=l   h 0‑1 (turns), s 0‑1, l 0‑1
//   okhsv  c1=h  c2=s  c3=v   h 0‑1 (turns), s 0‑1, v 0‑1
//
// Alpha is always 0‑1.
// All floats use full f64 precision in the string.

#[derive(Clone)]
struct Color {
    space: ColorSpace,
    c1: f64,
    c2: f64,
    c3: f64,
    alpha: f64,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ColorSpace {
    Srgb,
    Okhsl,
    Okhsv,
}

impl ColorSpace {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Srgb => "srgb",
            Self::Okhsl => "okhsl",
            Self::Okhsv => "okhsv",
        }
    }

    fn parse(s: &str) -> Self {
        match s {
            "srgb" => Self::Srgb,
            "okhsl" => Self::Okhsl,
            "okhsv" => Self::Okhsv,
            _ => nix_wasm_rust::panic(&format!("unknown color space: '{s}'")),
        }
    }
}

impl Color {
    fn parse(s: &str) -> Self {
        let parts: Vec<&str> = s.split(':').collect();
        if parts.len() != 5 {
            nix_wasm_rust::panic(&format!(
                "color string must have 5 colon-separated fields, got {}: '{s}'",
                parts.len()
            ));
        }
        let pf = |i: usize| -> f64 {
            parts[i]
                .parse()
                .unwrap_or_else(|e| nix_wasm_rust::panic(&format!("bad float '{}': {e}", parts[i])))
        };
        Color {
            space: ColorSpace::parse(parts[0]),
            c1: pf(1),
            c2: pf(2),
            c3: pf(3),
            alpha: pf(4),
        }
    }

    fn format(&self) -> String {
        // Use enough precision to survive a round-trip through string repr.
        format!(
            "{}:{:.17}:{:.17}:{:.17}:{:.17}",
            self.space.as_str(),
            self.c1,
            self.c2,
            self.c3,
            self.alpha,
        )
    }

    /// Convert any color to sRGB (0‑1 per channel).
    fn to_srgb(&self) -> Color {
        match self.space {
            ColorSpace::Srgb => self.clone(),
            ColorSpace::Okhsl => {
                let okhsl: Okhsl<f64> = Okhsl::new(self.c1 * 360.0, self.c2, self.c3);
                let rgb: Srgb<f64> = Srgb::from_color(okhsl);
                Color {
                    space: ColorSpace::Srgb,
                    c1: rgb.red.clamp(0.0, 1.0),
                    c2: rgb.green.clamp(0.0, 1.0),
                    c3: rgb.blue.clamp(0.0, 1.0),
                    alpha: self.alpha,
                }
            }
            ColorSpace::Okhsv => {
                let okhsv: Okhsv<f64> = Okhsv::new(self.c1 * 360.0, self.c2, self.c3);
                let rgb: Srgb<f64> = Srgb::from_color(okhsv);
                Color {
                    space: ColorSpace::Srgb,
                    c1: rgb.red.clamp(0.0, 1.0),
                    c2: rgb.green.clamp(0.0, 1.0),
                    c3: rgb.blue.clamp(0.0, 1.0),
                    alpha: self.alpha,
                }
            }
        }
    }

    fn to_okhsl(&self) -> Color {
        let srgb = self.to_srgb();
        let rgb = Srgb::new(srgb.c1, srgb.c2, srgb.c3);
        let okhsl: Okhsl<f64> = rgb.into_color();
        Color {
            space: ColorSpace::Okhsl,
            c1: okhsl.hue.into_positive_degrees() / 360.0,
            c2: okhsl.saturation,
            c3: okhsl.lightness,
            alpha: self.alpha,
        }
    }

    fn to_okhsv(&self) -> Color {
        let srgb = self.to_srgb();
        let rgb = Srgb::new(srgb.c1, srgb.c2, srgb.c3);
        let okhsv: Okhsv<f64> = rgb.into_color();
        Color {
            space: ColorSpace::Okhsv,
            c1: okhsv.hue.into_positive_degrees() / 360.0,
            c2: okhsv.saturation,
            c3: okhsv.value,
            alpha: self.alpha,
        }
    }

    fn to_space(&self, target: ColorSpace) -> Color {
        match target {
            ColorSpace::Srgb => self.to_srgb(),
            ColorSpace::Okhsl => self.to_okhsl(),
            ColorSpace::Okhsv => self.to_okhsv(),
        }
    }

    // -- channel access ----------------------------------------------------

    /// Channel names by space:
    ///   srgb:  r g b
    ///   okhsl: h s l
    ///   okhsv: h s v
    fn channel_index(space: ColorSpace, name: &str) -> usize {
        match (space, name) {
            (ColorSpace::Srgb, "r") => 1,
            (ColorSpace::Srgb, "g") => 2,
            (ColorSpace::Srgb, "b") => 3,
            (ColorSpace::Okhsl, "h") => 1,
            (ColorSpace::Okhsl, "s") => 2,
            (ColorSpace::Okhsl, "l") => 3,
            (ColorSpace::Okhsv, "h") => 1,
            (ColorSpace::Okhsv, "s") => 2,
            (ColorSpace::Okhsv, "v") => 3,
            _ => nix_wasm_rust::panic(&format!(
                "no channel '{name}' in space '{}'",
                space.as_str()
            )),
        }
    }

    fn get(&self, idx: usize) -> f64 {
        match idx {
            1 => self.c1,
            2 => self.c2,
            3 => self.c3,
            _ => nix_wasm_rust::panic("channel index out of range"),
        }
    }

    fn set(&self, idx: usize, val: f64) -> Color {
        let mut c = self.clone();
        match idx {
            1 => c.c1 = val,
            2 => c.c2 = val,
            3 => c.c3 = val,
            _ => nix_wasm_rust::panic("channel index out of range"),
        }
        c
    }
}

fn hex_to_srgb(hex: &str) -> Color {
    let hex = hex.strip_prefix('#').unwrap_or(hex);
    let hex = hex.to_ascii_uppercase();
    let expanded = match hex.len() {
        3 => {
            let cs: Vec<u8> = hex.bytes().collect();
            format!(
                "{0}{0}{1}{1}{2}{2}",
                cs[0] as char, cs[1] as char, cs[2] as char
            )
        }
        4 => {
            let cs: Vec<u8> = hex.bytes().collect();
            format!(
                "{0}{0}{1}{1}{2}{2}{3}{3}",
                cs[0] as char, cs[1] as char, cs[2] as char, cs[3] as char
            )
        }
        6 | 8 => hex.clone(),
        _ => nix_wasm_rust::panic(&format!("invalid hex length {}: '{hex}'", hex.len())),
    };

    let byte = |i: usize| -> f64 {
        let s = &expanded[i..i + 2];
        u8::from_str_radix(s, 16)
            .unwrap_or_else(|_| nix_wasm_rust::panic(&format!("bad hex byte '{s}'"))) as f64
            / 255.0
    };

    Color {
        space: ColorSpace::Srgb,
        c1: byte(0),
        c2: byte(2),
        c3: byte(4),
        alpha: if expanded.len() == 8 { byte(6) } else { 1.0 },
    }
}

fn srgb_to_hex(c: &Color) -> String {
    let srgb = c.to_srgb();
    let to_byte = |v: f64| -> u8 { (v.clamp(0.0, 1.0) * 255.0 + 0.5) as u8 };
    let r = to_byte(srgb.c1);
    let g = to_byte(srgb.c2);
    let b = to_byte(srgb.c3);
    let a = to_byte(srgb.alpha);
    if a == 255 {
        format!("{r:02X}{g:02X}{b:02X}")
    } else {
        format!("{r:02X}{g:02X}{b:02X}{a:02X}")
    }
}

// Exported WASM functions

/// hex string -> color string (srgb)
#[no_mangle]
pub extern "C" fn hex_to_color(arg: Value) -> Value {
    let hex = arg.get_string();
    let color = hex_to_srgb(&hex);
    Value::make_string(&color.format())
}

/// color string -> hex string
#[no_mangle]
pub extern "C" fn color_to_hex(arg: Value) -> Value {
    let color = Color::parse(&arg.get_string());
    Value::make_string(&srgb_to_hex(&color))
}

/// color string -> okhsl color string
#[no_mangle]
pub extern "C" fn to_okhsl(arg: Value) -> Value {
    let color = Color::parse(&arg.get_string());
    Value::make_string(&color.to_okhsl().format())
}

/// color string -> okhsv color string
#[no_mangle]
pub extern "C" fn to_okhsv(arg: Value) -> Value {
    let color = Color::parse(&arg.get_string());
    Value::make_string(&color.to_okhsv().format())
}

/// color string -> srgb color string
#[no_mangle]
pub extern "C" fn to_srgb(arg: Value) -> Value {
    let color = Color::parse(&arg.get_string());
    Value::make_string(&color.to_srgb().format())
}

/// { color, channel } -> float
/// Get a channel value from a color in its current space.
#[no_mangle]
pub extern "C" fn get_channel(arg: Value) -> Value {
    let color_str = arg
        .get_attr("color")
        .unwrap_or_else(|| nix_wasm_rust::panic("get_channel: missing 'color' attr"))
        .get_string();
    let channel = arg
        .get_attr("channel")
        .unwrap_or_else(|| nix_wasm_rust::panic("get_channel: missing 'channel' attr"))
        .get_string();
    let color = Color::parse(&color_str);
    let idx = Color::channel_index(color.space, &channel);
    Value::make_float(color.get(idx))
}

/// { color, channel, value } -> color string
/// Set a channel to a specific value.
#[no_mangle]
pub extern "C" fn set_channel(arg: Value) -> Value {
    let color_str = arg
        .get_attr("color")
        .unwrap_or_else(|| nix_wasm_rust::panic("set_channel: missing 'color' attr"))
        .get_string();
    let channel = arg
        .get_attr("channel")
        .unwrap_or_else(|| nix_wasm_rust::panic("set_channel: missing 'channel' attr"))
        .get_string();
    let value = arg
        .get_attr("value")
        .unwrap_or_else(|| nix_wasm_rust::panic("set_channel: missing 'value' attr"))
        .get_float();
    let color = Color::parse(&color_str);
    let idx = Color::channel_index(color.space, &channel);
    Value::make_string(&color.set(idx, value).format())
}

/// { color, channel, amount } -> color string
/// Adjust a channel by a delta. Hue wraps around 0‑1, others clamp to 0‑1.
#[no_mangle]
pub extern "C" fn adjust_channel(arg: Value) -> Value {
    let color_str = arg
        .get_attr("color")
        .unwrap_or_else(|| nix_wasm_rust::panic("adjust_channel: missing 'color' attr"))
        .get_string();
    let channel = arg
        .get_attr("channel")
        .unwrap_or_else(|| nix_wasm_rust::panic("adjust_channel: missing 'channel' attr"))
        .get_string();
    let amount = arg
        .get_attr("amount")
        .unwrap_or_else(|| nix_wasm_rust::panic("adjust_channel: missing 'amount' attr"))
        .get_float();
    let color = Color::parse(&color_str);
    let idx = Color::channel_index(color.space, &channel);
    let old = color.get(idx);
    let is_hue = channel == "h";
    let new_val = if is_hue {
        (old + amount).rem_euclid(1.0)
    } else {
        (old + amount).clamp(0.0, 1.0)
    };
    Value::make_string(&color.set(idx, new_val).format())
}

/// { color, channel, factor } -> color string
/// Scale a channel by a factor, clamped to 0‑1.
#[no_mangle]
pub extern "C" fn scale_channel(arg: Value) -> Value {
    let color_str = arg
        .get_attr("color")
        .unwrap_or_else(|| nix_wasm_rust::panic("scale_channel: missing 'color' attr"))
        .get_string();
    let channel = arg
        .get_attr("channel")
        .unwrap_or_else(|| nix_wasm_rust::panic("scale_channel: missing 'channel' attr"))
        .get_string();
    let factor = arg
        .get_attr("factor")
        .unwrap_or_else(|| nix_wasm_rust::panic("scale_channel: missing 'factor' attr"))
        .get_float();
    let color = Color::parse(&color_str);
    let idx = Color::channel_index(color.space, &channel);
    let new_val = (color.get(idx) * factor).clamp(0.0, 1.0);
    Value::make_string(&color.set(idx, new_val).format())
}

// -- Mixing ----------------------------------------------------------------

/// { a, b, factor } -> color string
/// Linear mix in Okhsl space (shortest hue path). Factor 0.0 = a, 1.0 = b.
#[no_mangle]
pub extern "C" fn mix(arg: Value) -> Value {
    let a_str = arg
        .get_attr("a")
        .unwrap_or_else(|| nix_wasm_rust::panic("mix: missing 'a' attr"))
        .get_string();
    let b_str = arg
        .get_attr("b")
        .unwrap_or_else(|| nix_wasm_rust::panic("mix: missing 'b' attr"))
        .get_string();
    let t = arg
        .get_attr("factor")
        .unwrap_or_else(|| nix_wasm_rust::panic("mix: missing 'factor' attr"))
        .get_float();

    let a = Color::parse(&a_str).to_okhsl();
    let b = Color::parse(&b_str).to_okhsl();

    // Interpolate hue via shortest path
    let h1 = a.c1;
    let h2 = b.c1;
    let diff = h2 - h1;
    let (h1a, h2a) = if diff.abs() > 0.5 {
        if diff > 0.0 {
            (h1 + 1.0, h2)
        } else {
            (h1, h2 + 1.0)
        }
    } else {
        (h1, h2)
    };
    let h = (h1a * (1.0 - t) + h2a * t).rem_euclid(1.0);
    let s = a.c2 * (1.0 - t) + b.c2 * t;
    let l = a.c3 * (1.0 - t) + b.c3 * t;
    let alpha = a.alpha * (1.0 - t) + b.alpha * t;

    let result = Color {
        space: ColorSpace::Okhsl,
        c1: h,
        c2: s,
        c3: l,
        alpha,
    };
    Value::make_string(&result.format())
}

// -- Contrast & utility ----------------------------------------------------

/// { a, b } -> float
/// Approximate luminance-based contrast ratio between two colors.
#[no_mangle]
pub extern "C" fn contrast_ratio(arg: Value) -> Value {
    let a_str = arg
        .get_attr("a")
        .unwrap_or_else(|| nix_wasm_rust::panic("contrast_ratio: missing 'a' attr"))
        .get_string();
    let b_str = arg
        .get_attr("b")
        .unwrap_or_else(|| nix_wasm_rust::panic("contrast_ratio: missing 'b' attr"))
        .get_string();

    let a = Color::parse(&a_str).to_srgb();
    let b = Color::parse(&b_str).to_srgb();

    Value::make_float(contrast_ratio_impl(&a, &b))
}

fn contrast_ratio_impl(a: &Color, b: &Color) -> f64 {
    let lum = |c: &Color| -> f64 { 0.2126 * c.c1 + 0.7152 * c.c2 + 0.0722 * c.c3 };
    let l1 = lum(a) + 0.05;
    let l2 = lum(b) + 0.05;
    if l1 > l2 {
        l1 / l2
    } else {
        l2 / l1
    }
}

/// hex string -> { r, g, b, alpha } (floats 0‑1)
#[no_mangle]
pub extern "C" fn hex_to_rgb_attr(arg: Value) -> Value {
    let hex = arg.get_string();
    let c = hex_to_srgb(&hex);
    Value::make_attrset(&[
        ("r", Value::make_float(c.c1)),
        ("g", Value::make_float(c.c2)),
        ("b", Value::make_float(c.c3)),
        ("alpha", Value::make_float(c.alpha)),
    ])
}

/// { fixed, color, factor } -> hex string
/// Push `color` away from `fixed` in Okhsv space by `factor` (0‑1).
/// Value is pushed toward opposite brightness, hue toward complement.
#[no_mangle]
pub extern "C" fn adjust_contrast(arg: Value) -> Value {
    let fixed_str = arg
        .get_attr("fixed")
        .unwrap_or_else(|| nix_wasm_rust::panic("adjust_contrast: missing 'fixed' attr"))
        .get_string();
    let color_str = arg
        .get_attr("color")
        .unwrap_or_else(|| nix_wasm_rust::panic("adjust_contrast: missing 'color' attr"))
        .get_string();
    let factor = arg
        .get_attr("factor")
        .unwrap_or_else(|| nix_wasm_rust::panic("adjust_contrast: missing 'factor' attr"))
        .get_float();

    let fixed = Color::parse(&fixed_str).to_okhsv();
    let color = Color::parse(&color_str);
    let color_hsv = color.to_okhsv();

    let fixed_v = fixed.c3;
    let fixed_h = fixed.c1;
    let cur_v = color_hsv.c3;
    let cur_h = color_hsv.c1;

    // Push value away from fixed
    let v_delta = if fixed_v > 0.5 { -cur_v } else { 1.0 - cur_v };
    let new_v = (cur_v + v_delta * factor).clamp(0.0, 1.0);

    // Push hue toward complement
    let target_h = (fixed_h + 0.5).rem_euclid(1.0);
    let raw = target_h - cur_h;
    let h_delta = if raw > 0.5 {
        raw - 1.0
    } else if raw < -0.5 {
        raw + 1.0
    } else {
        raw
    };
    let new_h = (cur_h + h_delta * factor).rem_euclid(1.0);

    let result = Color {
        space: ColorSpace::Okhsv,
        c1: new_h,
        c2: color_hsv.c2,
        c3: new_v,
        alpha: color.alpha,
    };
    Value::make_string(&srgb_to_hex(&result))
}

/// { text, bg, min_ratio } -> hex string
/// Adjust `text` color to ensure at least `min_ratio` contrast against `bg`.
#[no_mangle]
pub extern "C" fn ensure_contrast(arg: Value) -> Value {
    let text_hex = arg
        .get_attr("text")
        .unwrap_or_else(|| nix_wasm_rust::panic("ensure_contrast: missing 'text' attr"))
        .get_string();
    let bg_hex = arg
        .get_attr("bg")
        .unwrap_or_else(|| nix_wasm_rust::panic("ensure_contrast: missing 'bg' attr"))
        .get_string();
    let min_ratio = arg
        .get_attr("min_ratio")
        .unwrap_or_else(|| nix_wasm_rust::panic("ensure_contrast: missing 'min_ratio' attr"))
        .get_float();

    let text_c = hex_to_srgb(&text_hex);
    let bg_c = hex_to_srgb(&bg_hex);

    let current = contrast_ratio_impl(&text_c.to_srgb(), &bg_c.to_srgb());
    let needed = (min_ratio - current) / 3.0;
    let factor = needed.clamp(0.0, 1.0);

    if factor <= 0.0 {
        // Already sufficient contrast
        Value::make_string(&srgb_to_hex(&text_c))
    } else {
        // Reuse adjust_contrast logic inline
        let fixed = bg_c.to_okhsv();
        let color_hsv = text_c.to_okhsv();

        let v_delta = if fixed.c3 > 0.5 {
            -color_hsv.c3
        } else {
            1.0 - color_hsv.c3
        };
        let new_v = (color_hsv.c3 + v_delta * factor).clamp(0.0, 1.0);

        let target_h = (fixed.c1 + 0.5).rem_euclid(1.0);
        let raw = target_h - color_hsv.c1;
        let h_delta = if raw > 0.5 {
            raw - 1.0
        } else if raw < -0.5 {
            raw + 1.0
        } else {
            raw
        };
        let new_h = (color_hsv.c1 + h_delta * factor).rem_euclid(1.0);

        let result = Color {
            space: ColorSpace::Okhsv,
            c1: new_h,
            c2: color_hsv.c2,
            c3: new_v,
            alpha: text_c.alpha,
        };
        Value::make_string(&srgb_to_hex(&result))
    }
}
