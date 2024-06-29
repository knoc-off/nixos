use palette::{FromColor,  Lch, Srgb, IntoColor};
use palette::Darken;

pub fn get_complementary_color(color: &str) -> String {
    // Convert hex to Srgb
    let rgb = hex_to_rgb(color).unwrap_or(Srgb::new(0.0, 0.0, 0.0));

    // Convert Srgb to Lch
    let mut lch = Lch::from_color(rgb);

    // Shift the hue by 180 degrees
    lch.hue += 180.0;

    // Convert back to Srgb
    let comp_rgb: Srgb = lch.into_color();

    // Convert Srgb to hex
    rgb_to_hex(&comp_rgb)
}

// Helper function to convert hex to Srgb
fn hex_to_rgb(hex: &str) -> Result<Srgb, ()> {
    // Remove '#' if present
    let hex = hex.trim_start_matches('#');

    if hex.len() != 6 {
        return Err(());
    }

    let r = u8::from_str_radix(&hex[0..2], 16).map_err(|_| ())?;
    let g = u8::from_str_radix(&hex[2..4], 16).map_err(|_| ())?;
    let b = u8::from_str_radix(&hex[4..6], 16).map_err(|_| ())?;

    Ok(Srgb::new(r as f32 / 255.0, g as f32 / 255.0, b as f32 / 255.0))
}

// Helper function to convert Srgb to hex
fn rgb_to_hex(rgb: &Srgb) -> String {
    format!(
        "#{:02X}{:02X}{:02X}",
        (rgb.red * 255.0) as u8,
        (rgb.green * 255.0) as u8,
        (rgb.blue * 255.0) as u8
    )
}




pub fn darken_color(color: &str, factor: f32) -> String {
    let rgb = hex_to_rgb(color).unwrap_or(Srgb::new(0.0, 0.0, 0.0));
    let darkened = rgb.darken(factor);
    rgb_to_hex(&darkened)
}


