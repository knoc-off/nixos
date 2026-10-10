//! Light curves behind the Lua `sun` API: pure functions from time-of-day
//! inputs to light values.

use std::f64::consts::PI;

/// Gamma-shape a 0..=1 daylight fraction. `gamma > 1` reaches high values at
/// a lower input fraction (the light brightens "sooner" through the day);
/// `gamma < 1` holds back longer. `gamma == 1` is a no-op.
pub fn apply_gamma(frac: f64, gamma: f64) -> f64 {
    frac.clamp(0.0, 1.0).powf(1.0 / gamma.max(0.01))
}

/// Interpolate `min_pct..=max_pct` (0-100%) by `frac` (0.0-1.0) into a Z2M
/// brightness value (1-254). Tolerates a min/max slider crossed the wrong
/// way. Always at least 1: a curve dims, it never switches off.
pub fn brightness_254(min_pct: u8, max_pct: u8, frac: f64) -> u8 {
    let lo = f64::from(min_pct.min(max_pct));
    let hi = f64::from(min_pct.max(max_pct));
    let pct = lo + (hi - lo) * frac.clamp(0.0, 1.0);
    (pct / 100.0 * 254.0).round().clamp(1.0, 254.0) as u8
}

/// Colour temperature in mireds across the day: `warm` at sunrise, sunset
/// and all night (`day_progress` is `None`), easing (sine) to `cool` at the
/// middle of the day. See [`crate::sun::day_progress`].
pub fn color_temp(day_progress: Option<f64>, warm: u16, cool: u16) -> u16 {
    let Some(p) = day_progress else {
        return warm;
    };
    let factor = (PI * p.clamp(0.0, 1.0)).sin();
    let (warm, cool) = (f64::from(warm), f64::from(cool));
    (warm - factor * (warm - cool)).round() as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brightness_254_spans_min_to_max() {
        assert_eq!(brightness_254(10, 100, 0.0), 25);
        assert_eq!(brightness_254(10, 100, 1.0), 254);
    }

    #[test]
    fn brightness_254_never_zero() {
        assert_eq!(brightness_254(0, 100, 0.0), 1);
    }

    #[test]
    fn brightness_254_tolerates_reversed_slider() {
        assert_eq!(brightness_254(100, 10, 1.0), brightness_254(10, 100, 1.0));
        assert_eq!(brightness_254(100, 10, 0.0), brightness_254(10, 100, 0.0));
    }

    #[test]
    fn apply_gamma_identity_at_one() {
        for f in [0.0, 0.25, 0.5, 0.75, 1.0] {
            assert!((apply_gamma(f, 1.0) - f).abs() < 1e-9, "f={f}");
        }
    }

    #[test]
    fn apply_gamma_above_one_brightens_sooner() {
        assert!(apply_gamma(0.25, 2.0) > 0.25);
        assert!(apply_gamma(0.5, 2.0) > 0.5);
    }

    #[test]
    fn apply_gamma_below_one_holds_back() {
        assert!(apply_gamma(0.5, 0.5) < 0.5);
    }

    #[test]
    fn apply_gamma_preserves_endpoints() {
        for gamma in [0.3, 1.0, 3.0] {
            assert_eq!(apply_gamma(0.0, gamma), 0.0);
            assert!((apply_gamma(1.0, gamma) - 1.0).abs() < 1e-9);
        }
    }

    #[test]
    fn color_temp_is_warm_at_night_and_cool_at_midday() {
        assert_eq!(color_temp(None, 454, 250), 454);
        assert_eq!(color_temp(Some(0.0), 454, 250), 454);
        assert_eq!(color_temp(Some(0.5), 454, 250), 250);
        let morning = color_temp(Some(0.2), 454, 250);
        assert!(morning > 250 && morning < 454);
    }
}
