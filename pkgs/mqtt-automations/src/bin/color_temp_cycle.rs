use anyhow::Result;
use chrono::{Local, TimeDelta};
use chrono_tz::Tz;
use mqtt_automations::Runtime;
use serde_json::json;
use std::f64::consts::PI;

#[tokio::main]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("color-temp-cycle").await?;

    let set_topic = rt.env_or("LIGHT_TOPIC", "zigbee2mqtt/light_1/set");
    let state_topic = rt.env_or(
        "LIGHT_STATE_TOPIC",
        set_topic.strip_suffix("/set").unwrap_or(&set_topic),
    );
    let lat: f64 = rt.env_parse("LATITUDE", 52.52);
    let lon: f64 = rt.env_parse("LONGITUDE", 13.405);

    // Color temperature range (mireds). Higher = warmer.
    let ct_warm: u16 = rt.env_parse("CT_WARM", 454); // ~2200K candlelight
    let ct_cool: u16 = rt.env_parse("CT_COOL", 250); // ~4000K daylight

    let interval: u64 = rt.env_parse("UPDATE_INTERVAL", 60);
    let tz_name = rt.env_or("TIMEZONE", "Europe/Berlin");
    let tz: Tz = tz_name.parse().unwrap_or_else(|_| {
        tracing::warn!("invalid TIMEZONE '{tz_name}', falling back to UTC");
        chrono_tz::UTC
    });

    // Tolerance for manual color_temp changes (mireds).
    let ct_tolerance: u16 = rt.env_parse("CT_TOLERANCE", 15);

    // Global enable/disable gate — controlled by HA toggle.
    let mut enabled = rt.setting::<bool>("ENABLED_TOPIC", true).await?;

    let mut state_msgs = rt.subscribe(&state_topic).await?;

    tracing::info!(
        set = %set_topic, state = %state_topic,
        %lat, %lon, ct_warm, ct_cool,
        %tz_name, "color-temp-cycle started"
    );

    // -- main loop: one cycle per day ----------------------------------------

    loop {
        let now = Local::now().with_timezone(&tz);
        let today = now.date_naive();

        let sunrise = mqtt_automations::sun::sunrise(lat, lon, today, &tz);
        let sunset = mqtt_automations::sun::sunset(lat, lon, today, &tz);
        let noon = mqtt_automations::sun::solar_noon(lon, today, &tz);

        // Outside daylight hours — sleep until next sunrise.
        if now < sunrise || now >= sunset {
            let next_sunrise = if now >= sunset {
                let tomorrow = today + TimeDelta::days(1);
                mqtt_automations::sun::sunrise(lat, lon, tomorrow, &tz)
            } else {
                sunrise
            };

            let wait_ms = (next_sunrise - now).num_milliseconds().max(0) as u64;
            tracing::info!(
                next_sunrise = %next_sunrise.format("%H:%M"),
                "outside daylight, sleeping until sunrise"
            );

            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_millis(wait_ms)) => {}
                _ = rt.shutdown_signal() => break,
            }
            continue;
        }

        // Drain stale state messages.
        while state_msgs.try_recv().is_ok() {}

        // -- active phase: sunrise to sunset ----------------------------------

        let mut last_set_ct: Option<u16> = None;
        tracing::info!(
            sunrise = %sunrise.format("%H:%M"),
            noon = %noon.format("%H:%M"),
            sunset = %sunset.format("%H:%M"),
            "entering daylight color cycle"
        );

        'cycle: loop {
            // Check for external changes (only abort on manual override when enabled).
            while let Ok(msg) = state_msgs.try_recv() {
                if !enabled.get() {
                    continue;
                }

                // Detect manual color_temp change. The bulb stays on the Zigbee
                // network when "off", so color_temp is still set regardless of
                // on/off state — no need to pause when the light is off.
                if let Some(expected) = last_set_ct {
                    if let Some(reported) = msg
                        .payload
                        .get("color_temp")
                        .and_then(|v| v.as_u64())
                    {
                        let reported = reported as u16;
                        let diff = (reported as i32 - expected as i32).unsigned_abs() as u16;
                        if diff > ct_tolerance {
                            tracing::info!(
                                expected, reported, diff,
                                "color_temp changed externally, stopping cycle for today"
                            );
                            break 'cycle;
                        }
                    }
                }
            }

            let now = Local::now().with_timezone(&tz);
            if now >= sunset {
                tracing::info!("sunset reached, cycle done");
                break;
            }

            // Sine curve: warm at sunrise/sunset, cool at noon.
            //   progress ∈ [0, 1] maps sunrise→sunset
            //   sin(π * progress) peaks at 1.0 at noon (progress=0.5)
            let day_duration = (sunset - sunrise).num_seconds() as f64;
            let elapsed = (now - sunrise).num_seconds() as f64;
            let progress = (elapsed / day_duration).clamp(0.0, 1.0);
            let factor = (PI * progress).sin();

            // Interpolate: at factor=0 (sunrise/sunset) → ct_warm,
            //              at factor=1 (noon) → ct_cool
            let ct = ct_warm as f64 - factor * (ct_warm as f64 - ct_cool as f64);
            let ct = ct.round() as u16;

            // Only publish if the value actually changed and cycle is enabled.
            if enabled.get() && last_set_ct != Some(ct) {
                rt.publish(&set_topic, json!({ "color_temp": ct })).await?;
                last_set_ct = Some(ct);

                tracing::debug!(
                    %ct,
                    progress = format!("{:.0}%", progress * 100.0),
                    "tick"
                );
            }

            tokio::select! {
                _ = tokio::time::sleep(std::time::Duration::from_secs(interval)) => {}
                _ = rt.shutdown_signal() => return Ok(()),
            }
        }

        // Done for today, wait a bit then loop back to sleep check.
        tokio::select! {
            _ = tokio::time::sleep(std::time::Duration::from_secs(60)) => {}
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}
