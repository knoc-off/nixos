//! Generic sun-following automation: drives a dimmable light's brightness or
//! an on/off plug's state from the real solar elevation at a fixed location.
//!
//! One process per device (`MQTT_CLIENT_ID` must be unique per instance, same
//! convention as `color-temp-cycle`). `MODE` selects the behavior:
//!   - `brightness`: brightness tracks [`mqtt_automations::sun::daylight_fraction`]
//!     (optionally gamma-shaped via `GAMMA`) continuously between MIN/MAX.
//!   - `switch`: state flips once per threshold crossing, with hysteresis so
//!     it can't flap near the boundary.
//!
//! Sunrise (morning half of the day) and sunset (evening half) are opted into
//! independently and at runtime from HA.
//!
//! Ownership model ("seamless adoption"): the automation never yanks a device
//! to a new value. It only takes control once the device's current value
//! already agrees (within tolerance) with what the sun curve wants -- so a
//! light left somewhere the curve hasn't reached yet gets picked up the
//! moment the curve sweeps past it, with no visible jump.
//!
//! A manual OFF is remembered as *yours* and never auto-woken; an OFF the
//! automation itself issued (sun down, MIN=0) may be woken again once the
//! curve calls for light again -- that's the light still following the sun,
//! not an override. See [`LightState`] and [`SwitchState`].
//!
//! An HA "reset" button drops all ownership state back to `Unknown` and
//! re-queries the device, for when you want to hand control back immediately
//! instead of waiting for the curve to catch up.

use std::time::{Duration, Instant};

use anyhow::Result;
use chrono::Local;
use mqtt_automations::{sun, Message, Runtime};
use serde_json::json;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Phase {
    Morning,
    Evening,
}

/// Brightness-mode ownership state. See module docs for the adoption model.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum LightState {
    /// No report received yet (just started).
    Unknown,
    /// On, but not close enough to the curve's target to take over.
    Free,
    /// We're actively driving brightness.
    Driving,
    /// User turned it off -- never auto-wake.
    UserOff,
    /// We turned it off (curve hit zero) -- may auto-wake when it rises again.
    AutoOff,
    /// Reset button was pressed: take over unconditionally on the next tick,
    /// regardless of tolerance or current on/off state.
    Claim,
}

/// Switch-mode ownership state.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum SwitchState {
    Unknown,
    Driving,
    NotDriving,
    /// Reset button was pressed: take over unconditionally on the next tick,
    /// regardless of tolerance or where the switch currently sits.
    Claim,
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("sun-follow").await?;

    let set_topic = rt.env_or("DEVICE_TOPIC", "zigbee2mqtt/light_1/set");
    let state_topic = rt.env_or(
        "DEVICE_STATE_TOPIC",
        set_topic.strip_suffix("/set").unwrap_or(&set_topic),
    );
    let get_topic = format!("{state_topic}/get");
    let mode = rt.env_or("MODE", "brightness");
    let is_switch = mode == "switch";

    let lat: f64 = rt.env_parse("LATITUDE", 52.52);
    let lon: f64 = rt.env_parse("LONGITUDE", 13.405);
    let interval: u64 = rt.env_parse("UPDATE_INTERVAL", 30);
    let transition: u64 = rt.env_parse("TRANSITION", 2);

    // Runtime settings, all HA-controlled. Each has an env var for its
    // initial value (so Nix can set device-specific defaults) and a topic
    // for live overrides from HA, same convention as sunrise-lights.
    let mut enabled = rt
        .setting::<bool>("ENABLED_TOPIC", rt.env_parse("ENABLED", true))
        .await?;
    let mut follow_sunrise = rt
        .setting::<bool>("FOLLOW_SUNRISE_TOPIC", rt.env_parse("FOLLOW_SUNRISE", true))
        .await?;
    let mut follow_sunset = rt
        .setting::<bool>("FOLLOW_SUNSET_TOPIC", rt.env_parse("FOLLOW_SUNSET", true))
        .await?;
    let mut invert = rt
        .setting::<bool>("INVERT_TOPIC", rt.env_parse("INVERT", false))
        .await?;
    let mut allow_wake = rt
        .setting::<bool>("ALLOW_WAKE_TOPIC", rt.env_parse("ALLOW_WAKE", true))
        .await?;
    let mut min_pct = rt
        .setting::<u8>("MIN_BRIGHTNESS_TOPIC", rt.env_parse("MIN_BRIGHTNESS", 1))
        .await?;
    let mut max_pct = rt
        .setting::<u8>("MAX_BRIGHTNESS_TOPIC", rt.env_parse("MAX_BRIGHTNESS", 100))
        .await?;
    let mut gamma = rt
        .setting::<f64>("GAMMA_TOPIC", rt.env_parse("GAMMA", 1.0))
        .await?;
    let mut threshold_pct = rt
        .setting::<u8>("THRESHOLD_TOPIC", rt.env_parse("THRESHOLD", 15))
        .await?;

    // Hysteresis half-width (switch mode), override tolerance, and adoption
    // tolerance (brightness mode) -- static tuning knobs, not user settings.
    let deadband: f64 = rt.env_parse("DEADBAND", 5.0);
    let brightness_tolerance: u8 = rt.env_parse("BRIGHTNESS_TOLERANCE", 5);
    let adopt_tolerance: u8 = rt.env_parse("ADOPT_TOLERANCE", 25);

    // Optional: publish the raw (uninverted) daylight fraction as a shared HA
    // sensor. Only set this on one instance -- every sun-follow process
    // computes the same value for the same lat/lon, so publishing it from
    // all of them would be redundant.
    let daylight_sensor_topic = rt.env_or("DAYLIGHT_SENSOR_TOPIC", "");

    // "Reset" button (HA mqtt.button): drop back to Unknown and re-query the
    // device, discarding whatever ownership state we've built up.
    let reset_topic = rt.env_or("RESET_TOPIC", "");

    let mut state_msgs = rt.subscribe(&state_topic).await?;
    let mut reset_msgs = if !reset_topic.is_empty() {
        Some(rt.subscribe(&reset_topic).await?)
    } else {
        None
    };

    rt.publish(&get_topic, json!({ "state": "" })).await?;

    eprintln!(
        "sun-follow started: mode={mode} set={set_topic} state={state_topic} lat={lat} lon={lon}"
    );

    // Tracked device state, kept fresh from Z2M state echoes.
    let mut reported_on: Option<bool> = None;
    let mut reported_bri: Option<u8> = None;
    let mut last_set_brightness: Option<u8> = None;
    let mut last_set_switch: Option<bool> = None;
    let mut last_desired_switch: Option<bool> = None;
    // Ignore state echoes for a moment after we publish, so the tail of our
    // own transition doesn't get mistaken for a manual change.
    let mut settle_until: Option<Instant> = None;

    let mut light_state = LightState::Unknown;
    let mut switch_state = SwitchState::Unknown;

    loop {
        tokio::select! {
            Some(msg) = state_msgs.recv() => {
                let (new_on, new_bri) = parse_state(&msg);
                let in_settle = settle_until.map(|t| Instant::now() < t).unwrap_or(false);
                if let Some(on) = new_on {
                    reported_on = Some(on);
                }
                if let Some(b) = new_bri {
                    reported_bri = Some(b);
                }

                if is_switch {
                    switch_state = switch_on_message(switch_state, new_on, last_set_switch, in_settle);
                } else {
                    light_state = light_on_message(
                        light_state,
                        new_on,
                        new_bri,
                        last_set_brightness,
                        brightness_tolerance,
                        in_settle,
                    );
                }
            }
            _ = async {
                match reset_msgs.as_mut() {
                    Some(rx) => { rx.recv().await; }
                    None => std::future::pending::<()>().await,
                }
            } => {
                eprintln!("reset requested, claiming device on next tick");
                light_state = LightState::Claim;
                switch_state = SwitchState::Claim;
            }
            _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => {
                let now = Local::now();
                let today = now.date_naive();
                let noon = sun::solar_noon(lon, today, Local);
                let phase = if now < noon { Phase::Morning } else { Phase::Evening };

                let raw = sun::daylight_fraction(lat, lon, now);
                if !daylight_sensor_topic.is_empty() {
                    rt.publish(&daylight_sensor_topic, json!({ "daylight_pct": (raw * 100.0).round() })).await?;
                }

                if !enabled.get() {
                    continue;
                }
                let phase_enabled = match phase {
                    Phase::Morning => follow_sunrise.get(),
                    Phase::Evening => follow_sunset.get(),
                };
                if !phase_enabled {
                    continue;
                }

                let frac = if invert.get() { 1.0 - raw } else { raw };

                if is_switch {
                    let desired = decide_switch(frac, threshold_pct.get() as f64, deadband, last_desired_switch);
                    let (next_state, publish) = switch_on_tick(switch_state, desired, reported_on, last_desired_switch, last_set_switch);
                    switch_state = next_state;
                    last_desired_switch = Some(desired);
                    if switch_state == SwitchState::Driving {
                        last_set_switch = Some(desired);
                    }
                    if let Some(state_on) = publish {
                        rt.publish(&set_topic, json!({ "state": if state_on { "ON" } else { "OFF" } })).await?;
                        settle_until = Some(Instant::now() + Duration::from_secs(1));
                    }
                } else {
                    let shaped = apply_gamma(frac, gamma.get());
                    let should_be_off = wants_off(min_pct.get(), max_pct.get(), shaped);
                    let target = brightness_254(min_pct.get(), max_pct.get(), shaped);
                    let (next_state, action) = light_on_tick(
                        light_state,
                        reported_bri,
                        last_set_brightness,
                        target,
                        should_be_off,
                        adopt_tolerance,
                        allow_wake.get(),
                    );
                    light_state = next_state;
                    if let Some(action) = action {
                        let mut payload = json!({ "brightness": action.brightness, "transition": transition });
                        if let Some(on) = action.set_on {
                            payload["state"] = json!(if on { "ON" } else { "OFF" });
                        }
                        rt.publish(&set_topic, payload).await?;
                        last_set_brightness = Some(action.brightness);
                        settle_until = Some(Instant::now() + Duration::from_secs(transition + 1));
                    }
                }
            }
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}

/// Extract `(state as bool, brightness)` from a Z2M state message.
fn parse_state(msg: &Message) -> (Option<bool>, Option<u8>) {
    let on = msg
        .payload
        .get("state")
        .and_then(|v| v.as_str())
        .map(|s| s == "ON");
    let bri = msg
        .payload
        .get("brightness")
        .and_then(|v| v.as_u64())
        .map(|b| b as u8);
    (on, bri)
}

/// Gamma-shape a 0..=1 daylight fraction. `gamma > 1` reaches high values at
/// a lower input fraction (the light brightens "sooner" through the day);
/// `gamma < 1` holds back longer. `gamma == 1` is a no-op.
fn apply_gamma(frac: f64, gamma: f64) -> f64 {
    frac.clamp(0.0, 1.0).powf(1.0 / gamma.max(0.01))
}

/// Interpolate `min_pct..=max_pct` (0-100%) by `frac` (0.0-1.0) into a Z2M
/// brightness value (1-254). Tolerates a min/max slider crossed the wrong
/// way. Always returns at least 1 -- callers use [`wants_off`] to decide
/// between "dim" and "off" instead.
fn brightness_254(min_pct: u8, max_pct: u8, frac: f64) -> u8 {
    let lo = min_pct.min(max_pct) as f64;
    let hi = min_pct.max(max_pct) as f64;
    let pct = lo + (hi - lo) * frac.clamp(0.0, 1.0);
    (pct / 100.0 * 254.0).round().clamp(1.0, 254.0) as u8
}

/// True when the curve calls for the light to be fully off: minimum
/// brightness is 0 and the (gamma-shaped) daylight fraction has bottomed out.
/// With `min_pct > 0` a light never auto-turns-off, only dims to the floor.
fn wants_off(min_pct: u8, max_pct: u8, shaped_frac: f64) -> bool {
    min_pct.min(max_pct) == 0 && shaped_frac <= 0.0
}

/// Schmitt-trigger threshold decision: on above `threshold + deadband`, off
/// below `threshold - deadband`, otherwise holds `last`. Prevents flapping
/// right at the boundary.
fn decide_switch(frac: f64, threshold_pct: f64, deadband: f64, last: Option<bool>) -> bool {
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

/// React to a Z2M state echo for a light. `last_set_bri` is what we last
/// commanded (used to detect a manual brightness change); `in_settle`
/// suppresses transitions during the settle window right after we publish.
fn light_on_message(
    state: LightState,
    reported_on: Option<bool>,
    reported_bri: Option<u8>,
    last_set_bri: Option<u8>,
    bri_tolerance: u8,
    in_settle: bool,
) -> LightState {
    if in_settle {
        return state;
    }
    match state {
        LightState::Unknown => match reported_on {
            Some(true) => LightState::Free,
            Some(false) => LightState::UserOff,
            None => state,
        },
        LightState::Free => match reported_on {
            Some(false) => LightState::UserOff,
            _ => state,
        },
        LightState::Driving => {
            if reported_on == Some(false) {
                LightState::UserOff
            } else if let (Some(bri), Some(expected)) = (reported_bri, last_set_bri) {
                let diff = (bri as i16 - expected as i16).unsigned_abs() as u8;
                if diff > bri_tolerance {
                    LightState::Free
                } else {
                    state
                }
            } else {
                state
            }
        }
        LightState::UserOff | LightState::AutoOff => match reported_on {
            Some(true) => LightState::Free,
            _ => state,
        },
        // Waiting for the next tick to apply the claim -- ignore reports
        // in the meantime so a stray echo can't cancel it.
        LightState::Claim => state,
    }
}

struct LightAction {
    /// `Some` when the state (on/off) must change alongside brightness.
    set_on: Option<bool>,
    brightness: u8,
}

/// Decide what to do on a tick, given the current ownership state.
/// "Adoption" (`Free` -> `Driving`) only happens when the reported brightness
/// is already within `adopt_tolerance` of `target` -- taking over is then
/// invisible. A manual `UserOff` is never auto-woken; an `AutoOff` (the
/// automation's own doing) may be, subject to `allow_wake`.
fn light_on_tick(
    state: LightState,
    reported_bri: Option<u8>,
    last_set_bri: Option<u8>,
    target: u8,
    should_be_off: bool,
    adopt_tolerance: u8,
    allow_wake: bool,
) -> (LightState, Option<LightAction>) {
    match state {
        LightState::Unknown | LightState::UserOff => (state, None),
        LightState::Free => match reported_bri {
            Some(bri) if (bri as i16 - target as i16).unsigned_abs() as u8 <= adopt_tolerance => (
                LightState::Driving,
                Some(LightAction {
                    set_on: None,
                    brightness: target,
                }),
            ),
            _ => (state, None),
        },
        LightState::Driving => {
            if should_be_off {
                (
                    LightState::AutoOff,
                    Some(LightAction {
                        set_on: Some(false),
                        brightness: target,
                    }),
                )
            } else if last_set_bri != Some(target) {
                (
                    state,
                    Some(LightAction {
                        set_on: None,
                        brightness: target,
                    }),
                )
            } else {
                (state, None)
            }
        }
        LightState::AutoOff => {
            if !should_be_off && allow_wake {
                (
                    LightState::Driving,
                    Some(LightAction {
                        set_on: Some(true),
                        brightness: target,
                    }),
                )
            } else {
                (state, None)
            }
        }
        // Reset button: take over unconditionally, no tolerance check, no
        // matter what the light is currently doing.
        LightState::Claim => {
            if should_be_off {
                (
                    LightState::AutoOff,
                    Some(LightAction {
                        set_on: Some(false),
                        brightness: target,
                    }),
                )
            } else {
                (
                    LightState::Driving,
                    Some(LightAction {
                        set_on: Some(true),
                        brightness: target,
                    }),
                )
            }
        }
    }
}

/// React to a Z2M state echo for a switch. Only `Driving` can be knocked out
/// by an external change -- `Unknown`/`NotDriving` resolve on the next tick.
fn switch_on_message(
    state: SwitchState,
    reported_on: Option<bool>,
    last_set: Option<bool>,
    in_settle: bool,
) -> SwitchState {
    if in_settle {
        return state;
    }
    match state {
        SwitchState::Driving => match (reported_on, last_set) {
            (Some(on), Some(expected)) if on != expected => SwitchState::NotDriving,
            _ => state,
        },
        _ => state,
    }
}

/// Decide what to do on a tick. `Unknown` adopts immediately if the reported
/// state already agrees with `desired` (invisible takeover), otherwise backs
/// off to `NotDriving`. Once `NotDriving`, control returns only when the
/// sun's desired side actually flips ("crossed") -- disagreeing isn't enough,
/// the world has to change for the automation to reassert itself.
fn switch_on_tick(
    state: SwitchState,
    desired: bool,
    reported_on: Option<bool>,
    last_desired: Option<bool>,
    last_set: Option<bool>,
) -> (SwitchState, Option<bool>) {
    let crossed = last_desired.is_some() && last_desired != Some(desired);
    match state {
        SwitchState::Unknown => match reported_on {
            Some(on) if on == desired => (SwitchState::Driving, None),
            Some(_) => (SwitchState::NotDriving, None),
            None => (state, None),
        },
        SwitchState::Driving => {
            if last_set != Some(desired) {
                (state, Some(desired))
            } else {
                (state, None)
            }
        }
        SwitchState::NotDriving => {
            if crossed {
                (SwitchState::Driving, Some(desired))
            } else {
                (state, None)
            }
        }
        // Reset button: take over unconditionally, no crossing required.
        SwitchState::Claim => (SwitchState::Driving, Some(desired)),
    }
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
    fn light_unknown_resolves_from_report() {
        assert_eq!(
            light_on_message(LightState::Unknown, Some(true), None, None, 5, false),
            LightState::Free
        );
        assert_eq!(
            light_on_message(LightState::Unknown, Some(false), None, None, 5, false),
            LightState::UserOff
        );
        assert_eq!(
            light_on_message(LightState::Unknown, None, None, None, 5, false),
            LightState::Unknown
        );
    }

    #[test]
    fn light_manual_off_from_any_on_state_goes_to_user_off() {
        assert_eq!(
            light_on_message(LightState::Free, Some(false), None, None, 5, false),
            LightState::UserOff
        );
        assert_eq!(
            light_on_message(LightState::Driving, Some(false), None, Some(100), 5, false),
            LightState::UserOff
        );
    }

    #[test]
    fn light_driving_tolerates_small_brightness_delta() {
        assert_eq!(
            light_on_message(LightState::Driving, None, Some(103), Some(100), 5, false),
            LightState::Driving
        );
    }

    #[test]
    fn light_driving_releases_on_large_brightness_delta() {
        assert_eq!(
            light_on_message(LightState::Driving, None, Some(200), Some(100), 5, false),
            LightState::Free
        );
    }

    #[test]
    fn light_user_off_and_auto_off_both_free_on_manual_on() {
        assert_eq!(
            light_on_message(LightState::UserOff, Some(true), None, None, 5, false),
            LightState::Free
        );
        assert_eq!(
            light_on_message(LightState::AutoOff, Some(true), None, None, 5, false),
            LightState::Free
        );
    }

    #[test]
    fn light_settle_window_suppresses_all_transitions() {
        // Even a manual-looking OFF or a huge brightness jump is ignored
        // while we're still settling our own transition.
        assert_eq!(
            light_on_message(LightState::Driving, Some(false), Some(0), Some(100), 5, true),
            LightState::Driving
        );
        assert_eq!(
            light_on_message(LightState::Driving, None, Some(250), Some(100), 5, true),
            LightState::Driving
        );
    }

    #[test]
    fn light_tick_unknown_and_user_off_never_act() {
        assert_eq!(
            light_on_tick(LightState::Unknown, Some(50), None, 100, false, 25, true).1.is_some(),
            false
        );
        assert_eq!(
            light_on_tick(LightState::UserOff, Some(50), None, 100, false, 25, true).1.is_some(),
            false
        );
    }

    #[test]
    fn light_tick_free_adopts_within_tolerance() {
        let (state, action) = light_on_tick(LightState::Free, Some(105), None, 100, false, 25, true);
        assert_eq!(state, LightState::Driving);
        let action = action.expect("should adopt");
        assert_eq!(action.brightness, 100);
        assert_eq!(action.set_on, None);
    }

    #[test]
    fn light_tick_free_does_not_adopt_outside_tolerance() {
        let (state, action) = light_on_tick(LightState::Free, Some(200), None, 100, false, 25, true);
        assert_eq!(state, LightState::Free);
        assert!(action.is_none());
    }

    #[test]
    fn light_tick_free_does_not_adopt_without_data() {
        let (state, action) = light_on_tick(LightState::Free, None, None, 100, false, 25, true);
        assert_eq!(state, LightState::Free);
        assert!(action.is_none());
    }

    #[test]
    fn light_tick_driving_turns_off_when_curve_bottoms_out() {
        let (state, action) = light_on_tick(LightState::Driving, Some(50), Some(50), 1, true, 25, true);
        assert_eq!(state, LightState::AutoOff);
        assert_eq!(action.unwrap().set_on, Some(false));
    }

    #[test]
    fn light_tick_driving_updates_brightness_when_changed() {
        let (state, action) = light_on_tick(LightState::Driving, Some(100), Some(100), 150, false, 25, true);
        assert_eq!(state, LightState::Driving);
        assert_eq!(action.unwrap().brightness, 150);
    }

    #[test]
    fn light_tick_driving_dedupes_unchanged_brightness() {
        let (state, action) = light_on_tick(LightState::Driving, Some(100), Some(100), 100, false, 25, true);
        assert_eq!(state, LightState::Driving);
        assert!(action.is_none());
    }

    #[test]
    fn light_tick_auto_off_wakes_when_allowed() {
        let (state, action) = light_on_tick(LightState::AutoOff, None, None, 50, false, 25, true);
        assert_eq!(state, LightState::Driving);
        assert_eq!(action.unwrap().set_on, Some(true));
    }

    #[test]
    fn light_tick_auto_off_stays_off_when_wake_disallowed() {
        let (state, action) = light_on_tick(LightState::AutoOff, None, None, 50, false, 25, false);
        assert_eq!(state, LightState::AutoOff);
        assert!(action.is_none());
    }

    #[test]
    fn light_tick_auto_off_stays_off_while_curve_still_wants_off() {
        let (state, action) = light_on_tick(LightState::AutoOff, None, None, 1, true, 25, true);
        assert_eq!(state, LightState::AutoOff);
        assert!(action.is_none());
    }

    #[test]
    fn light_tick_claim_turns_on_regardless_of_distance() {
        // Light reported far outside adopt_tolerance (or not reported at
        // all) -- claim takes over anyway, unconditionally.
        let (state, action) = light_on_tick(LightState::Claim, Some(10), None, 240, false, 25, true);
        assert_eq!(state, LightState::Driving);
        let action = action.expect("claim must always act");
        assert_eq!(action.set_on, Some(true));
        assert_eq!(action.brightness, 240);
    }

    #[test]
    fn light_tick_claim_turns_off_when_curve_wants_off() {
        let (state, action) = light_on_tick(LightState::Claim, Some(200), None, 1, true, 25, true);
        assert_eq!(state, LightState::AutoOff);
        assert_eq!(action.unwrap().set_on, Some(false));
    }

    #[test]
    fn light_claim_ignores_reports_until_tick_applies_it() {
        // A stray echo while a claim is pending must not cancel it.
        assert_eq!(
            light_on_message(LightState::Claim, Some(false), Some(5), None, 5, false),
            LightState::Claim
        );
    }

    #[test]
    fn switch_driving_releases_on_unexpected_change() {
        assert_eq!(
            switch_on_message(SwitchState::Driving, Some(false), Some(true), false),
            SwitchState::NotDriving
        );
    }

    #[test]
    fn switch_driving_ignores_own_echo() {
        assert_eq!(
            switch_on_message(SwitchState::Driving, Some(true), Some(true), false),
            SwitchState::Driving
        );
    }

    #[test]
    fn switch_settle_window_suppresses_release() {
        assert_eq!(
            switch_on_message(SwitchState::Driving, Some(false), Some(true), true),
            SwitchState::Driving
        );
    }

    #[test]
    fn switch_unknown_adopts_when_already_agreeing() {
        let (state, publish) = switch_on_tick(SwitchState::Unknown, true, Some(true), None, None);
        assert_eq!(state, SwitchState::Driving);
        assert!(publish.is_none());
    }

    #[test]
    fn switch_unknown_backs_off_when_disagreeing() {
        let (state, publish) = switch_on_tick(SwitchState::Unknown, true, Some(false), None, None);
        assert_eq!(state, SwitchState::NotDriving);
        assert!(publish.is_none());
    }

    #[test]
    fn switch_unknown_waits_without_data() {
        let (state, publish) = switch_on_tick(SwitchState::Unknown, true, None, None, None);
        assert_eq!(state, SwitchState::Unknown);
        assert!(publish.is_none());
    }

    #[test]
    fn switch_driving_publishes_on_change() {
        let (state, publish) = switch_on_tick(SwitchState::Driving, false, Some(true), Some(true), Some(true));
        assert_eq!(state, SwitchState::Driving);
        assert_eq!(publish, Some(false));
    }

    #[test]
    fn switch_not_driving_ignores_disagreement_without_crossing() {
        // last_desired == desired: no crossing, even though it currently disagrees.
        let (state, publish) = switch_on_tick(SwitchState::NotDriving, true, Some(false), Some(true), None);
        assert_eq!(state, SwitchState::NotDriving);
        assert!(publish.is_none());
    }

    #[test]
    fn switch_not_driving_reclaims_on_crossing() {
        let (state, publish) = switch_on_tick(SwitchState::NotDriving, false, Some(true), Some(true), None);
        assert_eq!(state, SwitchState::Driving);
        assert_eq!(publish, Some(false));
    }

    #[test]
    fn switch_tick_claim_publishes_regardless() {
        let (state, publish) = switch_on_tick(SwitchState::Claim, true, Some(false), None, None);
        assert_eq!(state, SwitchState::Driving);
        assert_eq!(publish, Some(true));
    }

    #[test]
    fn switch_claim_ignores_reports_until_tick_applies_it() {
        assert_eq!(
            switch_on_message(SwitchState::Claim, Some(false), None, false),
            SwitchState::Claim
        );
    }
}
