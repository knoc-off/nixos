use anyhow::Result;
use chrono::{Local, TimeDelta};
use chrono_tz::Tz;
use mqtt_automations::Runtime;
use serde_json::json;

#[tokio::main]
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

    // Elevation range for the ramp.
    //   -6  = civil twilight (sky starts brightening, good start point)
    //    8  = sun clearly above horizon (full daylight)
    // In Berlin this gives roughly:
    //   Winter: ramp ~07:45 -> ~09:30   (slow sunrise)
    //   Equinox: ramp ~05:30 -> ~07:00
    //   Summer: ramp ~04:15 -> ~05:30   (fast sunrise)
    let elev_start: f64 = rt.env_parse("ELEVATION_START", -6.0);
    let elev_end: f64 = rt.env_parse("ELEVATION_END", 8.0);

    // Gamma > 1 = starts slow, accelerates. 2.0 means at the halfway
    // elevation point you're only at 25% brightness, then it ramps up fast.
    let gamma: f64 = rt.env_parse("GAMMA", 2.0);
    let interval: u64 = rt.env_parse("UPDATE_INTERVAL", 30);
    let ct_start: u16 = rt.env_parse("COLOR_TEMP_START", 454); // warm
    let ct_end: u16 = rt.env_parse("COLOR_TEMP_END", 250); // cool/daylight
    let tz_name = rt.env_or("TIMEZONE", "Europe/Berlin");
    let tz: Tz = tz_name.parse().unwrap_or_else(|_| {
        tracing::warn!("invalid TIMEZONE '{tz_name}', falling back to UTC");
        chrono_tz::UTC
    });

    // Subscribe to light state so we can detect external OFF.
    let mut state_msgs = rt.subscribe(&state_topic).await?;

    tracing::info!(
        set = %set_topic, state = %state_topic,
        %lat, %lon, elev_start, elev_end, gamma,
        %tz_name, "sunrise-lights started"
    );

    // -- main loop: one cycle per day ----------------------------------------

    loop {
        let now = Local::now().with_timezone(&tz);
        let elev = mqtt_automations::sun::elevation(lat, lon, now);

        // If we're currently in the ramp window (mid-sunrise), jump straight
        // into the ramp. Otherwise, sleep until the next pre-dawn.
        if elev < elev_start || elev >= elev_end {
            let today = now.date_naive();
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
        }

        // Drain stale state messages before starting.
        while state_msgs.try_recv().is_ok() {}

        // -- ramp phase: driven by real solar elevation -----------------------

        let mut light_on = false;
        tracing::info!("entering ramp phase");

        'ramp: loop {
            // Check for external OFF while ramping.
            while let Ok(msg) = state_msgs.try_recv() {
                if light_on {
                    let state = msg
                        .payload
                        .get("state")
                        .and_then(|v| v.as_str())
                        .unwrap_or("");
                    if state == "OFF" {
                        tracing::info!("light turned off externally, aborting ramp");
                        break 'ramp;
                    }
                }
            }

            let now = Local::now().with_timezone(&tz);
            let elev = mqtt_automations::sun::elevation(lat, lon, now);

            // Not yet at the start elevation — keep waiting.
            if elev < elev_start {
                tokio::select! {
                    _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => continue,
                    _ = rt.shutdown_signal() => return Ok(()),
                }
            }

            // Map elevation [start, end] -> [0, 1], then apply gamma.
            let raw = ((elev - elev_start) / (elev_end - elev_start)).clamp(0.0, 1.0);
            let progress = raw.powf(gamma);

            let brightness = (progress * 254.0).max(1.0) as u8;
            let ct = ct_start as f64 + progress * (ct_end as f64 - ct_start as f64);

            if !light_on {
                rt.publish(
                    &set_topic,
                    json!({
                        "state": "ON",
                        "brightness": brightness,
                        "color_temp": ct as u16,
                    }),
                )
                .await?;
                light_on = true;
                tracing::info!(elev = format!("{elev:.1}"), "ramp started");
            } else {
                rt.publish(
                    &set_topic,
                    json!({
                        "brightness": brightness,
                        "color_temp": ct as u16,
                    }),
                )
                .await?;
            }

            tracing::debug!(
                elev = format!("{elev:.1}"),
                %brightness,
                progress = format!("{:.0}%", progress * 100.0),
                "tick"
            );

            if raw >= 1.0 {
                tracing::info!("ramp complete, full brightness");
                break;
            }

            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => {}
                _ = rt.shutdown_signal() => return Ok(()),
            }
        }

        // Done for today. Small pause, then loop back — the outer check
        // will see we're past elev_end and sleep until next pre-dawn.
        tokio::select! {
            _ = tokio::time::sleep(std::time::Duration::from_secs(60)) => {}
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}
