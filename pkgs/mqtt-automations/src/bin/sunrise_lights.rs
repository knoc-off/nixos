use anyhow::Result;
use chrono::{Local, NaiveDate, TimeDelta};
use chrono_tz::Tz;
use mqtt_automations::Runtime;
use serde_json::json;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("sunrise-lights").await?;

    let set_topic = rt.env_or("LIGHT_TOPIC", "zigbee2mqtt/light_1/set");
    // State topic defaults to the set topic minus "/set" (Z2M convention).
    let state_topic = rt.env_or(
        "LIGHT_STATE_TOPIC",
        set_topic.strip_suffix("/set").unwrap_or(&set_topic),
    );
    let lat: f64 = rt.env_parse("LATITUDE", 52.52);
    let lon: f64 = rt.env_parse("LONGITUDE", 13.405);

    // Elevation at which the ramp starts (light turns on).
    //   -6 = civil twilight (sky starts brightening)
    let elev_start: f64 = rt.env_parse("ELEVATION_START", -6.0);

    // The ramp ends at solar noon + this offset (minutes). Default 0 = solar noon.
    let noon_offset_min: i64 = rt.env_parse("NOON_OFFSET_MIN", 0);

    // Gamma > 1 = starts slow, accelerates. 2.0 means at the halfway
    // time point you're only at 25% brightness, then it ramps up fast.
    // Controllable at runtime via an HA slider (GAMMA_TOPIC).
    let gamma_init: f64 = rt.env_parse("GAMMA", 2.0);
    let mut gamma = rt.setting::<f64>("GAMMA_TOPIC", gamma_init).await?;
    let interval: u64 = rt.env_parse("UPDATE_INTERVAL", 30);
    let tz_name = rt.env_or("TIMEZONE", "Europe/Berlin");
    let tz: Tz = tz_name.parse().unwrap_or_else(|_| {
        tracing::warn!("invalid TIMEZONE '{tz_name}', falling back to UTC");
        chrono_tz::UTC
    });

    // Cap the ramp at this brightness percentage (0-100%).
    // Can be overridden at runtime via an HA slider (MAX_BRIGHTNESS_TOPIC).
    let max_bri_pct: u8 = rt.env_parse("MAX_BRIGHTNESS", 100);
    let mut max_bri = rt.setting::<u8>("MAX_BRIGHTNESS_TOPIC", max_bri_pct).await?;

    // How much the reported brightness may differ from what we set before
    // we consider it a manual change (zigbee rounding, transitions, etc.).
    let brightness_tolerance: u8 = rt.env_parse("BRIGHTNESS_TOLERANCE", 5);

    // Persistent delay (minutes) controlled from an HA slider.
    let mut delay = rt.setting::<u64>("DELAY_TOPIC", 0).await?;

    // Subscribe to light state so we can detect external changes.
    let mut state_msgs = rt.subscribe(&state_topic).await?;

    tracing::info!(
        set = %set_topic, state = %state_topic,
        %lat, %lon, elev_start, noon_offset_min, gamma = gamma_init,
        max_brightness_pct = max_bri_pct,
        %tz_name, "sunrise-lights started"
    );

    // -- main loop: one cycle per day ----------------------------------------

    // Once the ramp ends for the day (completed OR pre-empted by an external
    // change) we record the date and refuse to ramp again until tomorrow, so
    // we never fight a manual override.
    let mut bowed_out: Option<NaiveDate> = None;

    loop {
        let now = Local::now().with_timezone(&tz);
        let today = now.date_naive();
        let elev = mqtt_automations::sun::elevation(lat, lon, now);
        let noon = mqtt_automations::sun::solar_noon(lon, today, &tz)
            + TimeDelta::minutes(noon_offset_min);

        // If we've already bowed out today, or we're past noon or before the
        // start elevation, sleep until next pre-dawn.
        if bowed_out == Some(today) || now >= noon || elev < elev_start {
            let rise = mqtt_automations::sun::sunrise(lat, lon, today, &tz);
            let next_rise = if now > rise {
                let tomorrow = today + TimeDelta::days(1);
                mqtt_automations::sun::sunrise(lat, lon, tomorrow, &tz)
            } else {
                rise
            };

            // Wake 60 min before sunrise — well before civil twilight.
            let wake_at = next_rise - TimeDelta::minutes(60);
            let wait_ms = (wake_at - now).num_milliseconds().max(0) as u64;

            tracing::info!(
                next_sunrise = %next_rise.format("%H:%M"),
                wake_at = %wake_at.format("%H:%M"),
                "sleeping until pre-dawn"
            );

            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_millis(wait_ms)) => {}
                _ = rt.shutdown_signal() => break,
            }

            // Apply persistent delay from HA slider.
            let delay_min = delay.get();
            if delay_min > 0 {
                tracing::info!(delay_min, "sunrise delay active, sleeping extra");
                tokio::select! {
                    _ = tokio::time::sleep(std::time::Duration::from_secs(delay_min * 60)) => {}
                    _ = rt.shutdown_signal() => break,
                }
            }

            continue;
        }

        // Drain stale state messages before starting.
        while state_msgs.try_recv().is_ok() {}

        // -- ramp phase: time-based from now until solar noon -----------------

        let ramp_start = now;
        let ramp_end = noon;
        let ramp_duration = (ramp_end - ramp_start).num_seconds() as f64;

        let mut light_on = false;
        let mut last_set_brightness: Option<u8> = None;
        tracing::info!(
            ramp_end = %ramp_end.format("%H:%M"),
            duration_min = ramp_duration / 60.0,
            "entering ramp phase (target: solar noon)"
        );

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
                        tracing::info!("light turned off externally, bowing out for today");
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
                                tracing::info!(
                                    expected, reported, diff,
                                    "brightness changed externally, bowing out for today"
                                );
                                break 'ramp;
                            }
                        }
                    }
                } else if state == "ON" {
                    // We haven't started the ramp yet, so any external "ON"
                    // means someone else (button, HA, etc.) took the light.
                    tracing::info!("light turned on externally before ramp, bowing out for today");
                    break 'ramp;
                }
            }

            let now = Local::now().with_timezone(&tz);

            // Not yet at the start elevation — keep waiting.
            let elev = mqtt_automations::sun::elevation(lat, lon, now);
            if elev < elev_start {
                tokio::select! {
                    _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => continue,
                    _ = rt.shutdown_signal() => return Ok(()),
                }
            }

            // Time-based progress toward solar noon, then apply gamma.
            let elapsed = (now - ramp_start).num_seconds() as f64;
            let raw = (elapsed / ramp_duration).clamp(0.0, 1.0);
            let progress = raw.powf(gamma.get());

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
                tracing::info!(elev = format!("{elev:.1}"), "ramp started");
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

            tracing::debug!(
                elev = format!("{elev:.1}"),
                %brightness,
                progress = format!("{:.0}%", progress * 100.0),
                "tick"
            );

            if raw >= 1.0 {
                tracing::info!("ramp complete, full brightness at noon");
                break;
            }

            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => {}
                _ = rt.shutdown_signal() => return Ok(()),
            }
        }

        // Ramp ended (completed or pre-empted) — don't ramp again until
        // tomorrow. Small pause, then loop back; the outer check will sleep
        // until next pre-dawn.
        bowed_out = Some(today);
        tokio::select! {
            _ = tokio::time::sleep(std::time::Duration::from_secs(60)) => {}
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}
