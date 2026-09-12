//! Wake-up light: a smooth brightness ramp on a fixed clock schedule.
//!
//! Deliberately *not* sun-tracking. Tracking the real sun means a 9-hour ramp
//! starting at 03:52 in June and a 4.5-hour one starting at 07:32 in December
//! — the opposite of a wake-up light. A fixed start time emulates a summer
//! sunrise year-round, which is the point.

use anyhow::Result;
use chrono::{DateTime, Local, NaiveTime, TimeDelta};
use mqtt_automations::Runtime;
use serde_json::json;

/// Next occurrence of wall-clock time `t` — today if still ahead, else tomorrow.
///
/// `earliest()` rather than `unwrap()`: `and_local_timezone` yields nothing in
/// the DST spring-forward gap and two candidates in the autumn overlap.
fn next_occurrence(now: DateTime<Local>, t: NaiveTime) -> DateTime<Local> {
    for day in 0..=2 {
        let cand = (now.date_naive() + TimeDelta::days(day))
            .and_time(t)
            .and_local_timezone(Local)
            .earliest();
        if let Some(dt) = cand {
            if dt > now {
                return dt;
            }
        }
    }
    // Every candidate fell in a DST gap (not reachable in practice).
    now + TimeDelta::days(1)
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("sunrise-lights").await?;

    let set_topic = rt.env_or("LIGHT_TOPIC", "zigbee2mqtt/light_1/set");
    // State topic defaults to the set topic minus "/set" (Z2M convention).
    let state_topic = rt.env_or(
        "LIGHT_STATE_TOPIC",
        set_topic.strip_suffix("/set").unwrap_or(&set_topic),
    );

    // When the ramp begins (local wall clock), and how long it runs.
    // Both controllable at runtime from HA.
    let start_init: NaiveTime = rt
        .env_or("START_TIME", "06:30:00")
        .parse()
        .unwrap_or_else(|_| NaiveTime::from_hms_opt(6, 30, 0).expect("valid time"));
    let mut start = rt.setting::<NaiveTime>("START_TIME_TOPIC", start_init).await?;

    let duration_init: u64 = rt.env_parse("DURATION", 45);
    let mut duration_min = rt.setting::<u64>("DURATION_TOPIC", duration_init).await?;

    // Perceptual correction: zigbee brightness is ~linear in luminance while
    // the eye is ~cube-root, so the raw curve looks like it jumps at the dim
    // end. Higher = more time spent dim.
    let gamma_init: f64 = rt.env_parse("GAMMA", 2.2);
    let mut gamma = rt.setting::<f64>("GAMMA_TOPIC", gamma_init).await?;

    let interval: u64 = rt.env_parse("UPDATE_INTERVAL", 30);

    // Cap the ramp at this brightness percentage (0-100%).
    let max_bri_pct: u8 = rt.env_parse("MAX_BRIGHTNESS", 100);
    let mut max_bri = rt.setting::<u8>("MAX_BRIGHTNESS_TOPIC", max_bri_pct).await?;

    // How much the reported brightness may differ from what we set before
    // we consider it a manual change (zigbee rounding, transitions, etc.).
    let brightness_tolerance: u8 = rt.env_parse("BRIGHTNESS_TOLERANCE", 5);

    // Subscribe to light state so we can detect external changes.
    let mut state_msgs = rt.subscribe(&state_topic).await?;

    eprintln!(
        "sunrise-lights started: set={set_topic} state={state_topic} \
         start={start_init} duration={duration_init}m gamma={gamma_init} \
         max_brightness_pct={max_bri_pct}"
    );

    // -- main loop: one ramp per day -----------------------------------------

    loop {
        // Sleep until the next start time. Settings are re-read each pass, so
        // moving the slider takes effect from the following day.
        let now = Local::now();
        let ramp_start = next_occurrence(now, start.get());
        let wait_ms = (ramp_start - now).num_milliseconds().max(0) as u64;

        eprintln!("sleeping until {}", ramp_start.format("%a %H:%M"));

        tokio::select! {
            _ = tokio::time::sleep(std::time::Duration::from_millis(wait_ms)) => {}
            _ = rt.shutdown_signal() => break,
        }

        // Drain stale state messages before starting.
        while state_msgs.try_recv().is_ok() {}

        let ramp_duration = (duration_min.get().max(1) * 60) as f64;
        let ramp_start = Local::now();

        let mut light_on = false;
        let mut last_set_brightness: Option<u8> = None;
        eprintln!("entering ramp phase ({:.0}m)", ramp_duration / 60.0);

        'ramp: loop {
            // Check for external changes. Any manual touch of brightness or
            // on/off state means something else is driving the light, so we
            // bow out for the rest of the day instead of competing.
            while let Ok(msg) = state_msgs.try_recv() {
                let state = msg
                    .payload
                    .get("state")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                if light_on {
                    if state == "OFF" {
                        eprintln!("light turned off externally, bowing out for today");
                        break 'ramp;
                    }
                    // Check if brightness was changed manually.
                    if let Some(expected) = last_set_brightness {
                        if let Some(reported) = msg
                            .payload
                            .get("brightness")
                            .and_then(|v| v.as_u64())
                        {
                            let reported = reported as u8;
                            let diff = (reported as i16 - expected as i16).unsigned_abs() as u8;
                            if diff > brightness_tolerance {
                                eprintln!(
                                    "brightness changed externally ({expected} -> {reported}), \
                                     bowing out for today"
                                );
                                break 'ramp;
                            }
                        }
                    }
                } else if state == "ON" {
                    // We haven't started the ramp yet, so any external "ON"
                    // means someone else (button, HA, etc.) took the light.
                    eprintln!("light turned on externally before ramp, bowing out for today");
                    break 'ramp;
                }
            }

            let elapsed = (Local::now() - ramp_start).num_seconds() as f64;
            let t = (elapsed / ramp_duration).clamp(0.0, 1.0);
            let progress = ramp_curve(t, gamma.get());

            let cap = (max_bri.get() as f64 / 100.0 * 254.0).max(1.0) as u8;
            let brightness = (progress * cap as f64).max(1.0) as u8;

            if !light_on {
                rt.publish(
                    &set_topic,
                    json!({
                        "state": "ON",
                        "brightness": brightness,
                    }),
                )
                .await?;
                light_on = true;
                last_set_brightness = Some(brightness);
            } else {
                rt.publish(
                    &set_topic,
                    json!({
                        "brightness": brightness,
                    }),
                )
                .await?;
                last_set_brightness = Some(brightness);
            }

            if t >= 1.0 {
                eprintln!("ramp complete");
                break;
            }

            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => {}
                _ = rt.shutdown_signal() => return Ok(()),
            }
        }

        // Loop back; next_occurrence is now strictly tomorrow, so we can't
        // re-trigger today.
    }
    Ok(())
}

/// Brightness curve: smoothstep (eases in *and* out) shaped by gamma.
///
/// Smoothstep has zero slope at both ends, so the ramp neither slams on at the
/// start nor jumps into the last 10%. `powf` then biases time toward the dim
/// end to compensate for perceptual brightness.
fn ramp_curve(t: f64, gamma: f64) -> f64 {
    let s = t * t * (3.0 - 2.0 * t);
    s.powf(gamma)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn curve_spans_zero_to_one() {
        assert_eq!(ramp_curve(0.0, 2.2), 0.0);
        assert!((ramp_curve(1.0, 2.2) - 1.0).abs() < 1e-12);
    }

    #[test]
    fn curve_is_monotonic() {
        let mut prev = -1.0;
        for i in 0..=100 {
            let v = ramp_curve(i as f64 / 100.0, 2.2);
            assert!(v >= prev, "not monotonic at t={i}: {prev} -> {v}");
            prev = v;
        }
    }

    #[test]
    fn curve_is_dim_biased() {
        // Halfway through the ramp should be well below half brightness.
        let mid = ramp_curve(0.5, 2.2);
        assert!(mid < 0.3, "midpoint should be dim, got {mid}");
    }

    #[test]
    fn curve_eases_out() {
        // Slope near the end approaches zero — no jump into full brightness.
        let d = ramp_curve(1.0, 2.2) - ramp_curve(0.98, 2.2);
        assert!(d < 0.01, "should ease out, got delta {d}");
    }

    #[test]
    fn next_occurrence_picks_today_then_tomorrow() {
        let now = Local::now()
            .date_naive()
            .and_hms_opt(12, 0, 0)
            .unwrap()
            .and_local_timezone(Local)
            .unwrap();

        let later = next_occurrence(now, NaiveTime::from_hms_opt(18, 0, 0).unwrap());
        assert_eq!(later.date_naive(), now.date_naive());

        let earlier = next_occurrence(now, NaiveTime::from_hms_opt(6, 30, 0).unwrap());
        assert_eq!(earlier.date_naive(), now.date_naive() + TimeDelta::days(1));
    }
}
