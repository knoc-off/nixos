//! Shared light curves: pure functions from time-of-day inputs to light
//! values, behind the Lua `sun` API and the legacy sun-follow/sunrise
//! daemons alike.

use std::f64::consts::PI;

/// Gamma-shape a 0..=1 daylight fraction. `gamma > 1` reaches high values at
/// a lower input fraction (the light brightens "sooner" through the day);
/// `gamma < 1` holds back longer. `gamma == 1` is a no-op.
pub fn apply_gamma(frac: f64, gamma: f64) -> f64 {
    frac.clamp(0.0, 1.0).powf(1.0 / gamma.max(0.01))
}

/// Interpolate `min_pct..=max_pct` (0-100%) by `frac` (0.0-1.0) into a Z2M
/// brightness value (1-254). Tolerates a min/max slider crossed the wrong
/// way. Always returns at least 1 -- callers use [`wants_off`] to decide
/// between "dim" and "off" instead.
pub fn brightness_254(min_pct: u8, max_pct: u8, frac: f64) -> u8 {
    let lo = f64::from(min_pct.min(max_pct));
    let hi = f64::from(min_pct.max(max_pct));
    let pct = lo + (hi - lo) * frac.clamp(0.0, 1.0);
    (pct / 100.0 * 254.0).round().clamp(1.0, 254.0) as u8
}

/// True when the curve calls for the light to be fully off: minimum
/// brightness is 0 and the (gamma-shaped) daylight fraction has bottomed out.
/// With `min_pct > 0` a light never auto-turns-off, only dims to the floor.
pub fn wants_off(min_pct: u8, max_pct: u8, shaped_frac: f64) -> bool {
    min_pct.min(max_pct) == 0 && shaped_frac <= 0.0
}

/// Schmitt-trigger threshold decision: on above `threshold + deadband`, off
/// below `threshold - deadband`, otherwise holds `last`. Prevents flapping
/// right at the boundary.
pub fn decide_switch(frac: f64, threshold_pct: f64, deadband: f64, last: Option<bool>) -> bool {
    let high = ((threshold_pct + deadband) / 100.0).clamp(0.0, 1.0);
    let low = ((threshold_pct - deadband) / 100.0).clamp(0.0, 1.0);
    if frac >= high {
        true
    } else if frac <= low {
        false
    } else {
        last.unwrap_or(false)
    }
}

/// Wake-up ramp: smoothstep (eases in *and* out) shaped by gamma.
///
/// Smoothstep has zero slope at both ends, so the ramp neither slams on at the
/// start nor jumps into the last 10%. `powf` then biases time toward the dim
/// end to compensate for perceptual brightness.
pub fn ramp(t: f64, gamma: f64) -> f64 {
    let t = t.clamp(0.0, 1.0);
    let s = t * t * (3.0 - 2.0 * t);
    s.powf(gamma)
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
    fn decide_switch_on_above_high_off_below_low() {
        assert!(decide_switch(0.6, 50.0, 5.0, None));
        assert!(!decide_switch(0.4, 50.0, 5.0, None));
    }

    #[test]
    fn decide_switch_holds_inside_deadband() {
        assert!(decide_switch(0.52, 50.0, 5.0, Some(true)));
        assert!(!decide_switch(0.52, 50.0, 5.0, Some(false)));
    }

    #[test]
    fn decide_switch_defaults_off_with_no_history() {
        assert!(!decide_switch(0.52, 50.0, 5.0, None));
    }

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
        // gamma > 1 should raise mid-range fractions above the identity line.
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
    fn wants_off_only_when_min_zero_and_frac_zero() {
        assert!(wants_off(0, 100, 0.0));
        assert!(!wants_off(1, 100, 0.0));
        assert!(!wants_off(0, 100, 0.01));
    }

    #[test]
    fn ramp_spans_zero_to_one() {
        assert_eq!(ramp(0.0, 2.2), 0.0);
        assert!((ramp(1.0, 2.2) - 1.0).abs() < 1e-12);
    }

    #[test]
    fn ramp_is_monotonic() {
        let mut prev = -1.0;
        for i in 0..=100 {
            let v = ramp(f64::from(i) / 100.0, 2.2);
            assert!(v >= prev, "not monotonic at t={i}: {prev} -> {v}");
            prev = v;
        }
    }

    #[test]
    fn ramp_is_dim_biased() {
        // Halfway through the ramp should be well below half brightness.
        let mid = ramp(0.5, 2.2);
        assert!(mid < 0.3, "midpoint should be dim, got {mid}");
    }

    #[test]
    fn ramp_eases_out() {
        // Slope near the end approaches zero -- no jump into full brightness.
        let d = ramp(1.0, 2.2) - ramp(0.98, 2.2);
        assert!(d < 0.01, "should ease out, got delta {d}");
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
