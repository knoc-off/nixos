use anyhow::Result;
use chrono::{Local, Timelike};
use chrono_tz::Tz;
use mqtt_automations::{Message, Runtime};
use serde_json::json;
use tokio::sync::mpsc::UnboundedReceiver;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("bedtime-button").await?;

    let button_topic = rt.env_or("BUTTON_TOPIC", "zigbee2mqtt/button_2/action");
    let set_topic = rt.env_or("LIGHT_TOPIC", "zigbee2mqtt/light_3/set");
    // State topic defaults to the set topic minus "/set" (Z2M convention).
    let state_topic = rt.env_or(
        "LIGHT_STATE_TOPIC",
        set_topic.strip_suffix("/set").unwrap_or(&set_topic),
    );
    // Which button action triggers us (Z2M sends "single"/"double"/"hold").
    let action_key = rt.env_or("ACTION_KEY", "single");

    // At/after this local hour, a press starts a bedtime fade instead of a
    // plain toggle.
    let bedtime_hour: u32 = rt.env_parse("BEDTIME_HOUR", 19);
    let fade_minutes: u64 = rt.env_parse("FADE_MINUTES", 10);
    let fade_step_secs: u64 = rt.env_parse("FADE_STEP_SECONDS", 20).max(1);
    // Brightness used when the toggle turns the light on.
    let toggle_brightness: u8 = rt.env_parse("TOGGLE_BRIGHTNESS", 254);

    let tz_name = rt.env_or("TIMEZONE", "Europe/Berlin");
    let tz: Tz = tz_name.parse().unwrap_or_else(|_| {
        tracing::warn!("invalid TIMEZONE '{tz_name}', falling back to UTC");
        chrono_tz::UTC
    });

    let mut button_msgs = rt.subscribe(&button_topic).await?;
    let mut state_msgs = rt.subscribe(&state_topic).await?;

    // Tracked device state, kept fresh from Z2M state echoes.
    let mut light_on = false;
    let mut brightness: u8 = toggle_brightness;

    tracing::info!(
        button = %button_topic, set = %set_topic, state = %state_topic,
        bedtime_hour, fade_minutes, fade_step_secs, %tz_name,
        "bedtime-button started"
    );

    loop {
        tokio::select! {
            Some(msg) = state_msgs.recv() => {
                update_state(&msg, &mut light_on, &mut brightness);
            }
            Some(msg) = button_msgs.recv() => {
                if action_of(&msg) != action_key {
                    continue;
                }

                let hour = Local::now().with_timezone(&tz).hour();
                let bedtime = hour >= bedtime_hour;

                if bedtime && light_on {
                    tracing::info!(hour, from = brightness, "bedtime press — fading down");
                    fade_to_off(
                        &rt,
                        &set_topic,
                        brightness.max(1),
                        fade_minutes * 60,
                        fade_step_secs,
                        &mut button_msgs,
                        &mut state_msgs,
                        &mut light_on,
                        &mut brightness,
                    )
                    .await?;
                } else if light_on {
                    tracing::info!(hour, "toggle → OFF");
                    rt.publish(&set_topic, json!({ "state": "OFF" })).await?;
                } else {
                    tracing::info!(hour, brightness = toggle_brightness, "toggle → ON");
                    rt.publish(
                        &set_topic,
                        json!({ "state": "ON", "brightness": toggle_brightness }),
                    )
                    .await?;
                }
            }
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}

/// Extract the action string from a button message (plain string or
/// `{"action": "..."}`).
fn action_of(msg: &Message) -> String {
    match &msg.payload {
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Object(m) => m
            .get("action")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        _ => String::new(),
    }
}

/// Update tracked on/off and brightness from a Z2M state message.
fn update_state(msg: &Message, light_on: &mut bool, brightness: &mut u8) {
    if let Some(s) = msg.payload.get("state").and_then(|v| v.as_str()) {
        *light_on = s == "ON";
    }
    if let Some(b) = msg.payload.get("brightness").and_then(|v| v.as_u64()) {
        *brightness = b as u8;
    }
}

/// Smoothly ramp brightness from `start` down to off over `total_secs`,
/// publishing a step every `step_secs` with a matching transition so the bulb
/// glides between steps. A button press cancels the fade and turns the light
/// off immediately.
#[allow(clippy::too_many_arguments)]
async fn fade_to_off(
    rt: &Runtime,
    set_topic: &str,
    start: u8,
    total_secs: u64,
    step_secs: u64,
    button_msgs: &mut UnboundedReceiver<Message>,
    state_msgs: &mut UnboundedReceiver<Message>,
    light_on: &mut bool,
    brightness: &mut u8,
) -> Result<()> {
    let steps = (total_secs / step_secs).max(1);

    for i in 1..=steps {
        // Keep tracked state fresh without blocking the fade timing.
        while let Ok(msg) = state_msgs.try_recv() {
            update_state(&msg, light_on, brightness);
        }

        let frac = i as f64 / steps as f64; // 0.0 -> 1.0
        let level = ((start as f64) * (1.0 - frac)).round().max(1.0) as u8;

        rt.publish(
            set_topic,
            json!({ "brightness": level, "transition": step_secs }),
        )
        .await?;
        *brightness = level;

        tokio::select! {
            _ = tokio::time::sleep(std::time::Duration::from_secs(step_secs)) => {}
            Some(_) = button_msgs.recv() => {
                tracing::info!("fade cancelled by button — turning off now");
                rt.publish(set_topic, json!({ "state": "OFF" })).await?;
                *light_on = false;
                return Ok(());
            }
            _ = rt.shutdown_signal() => return Ok(()),
        }
    }

    tracing::info!("fade complete — light off");
    rt.publish(set_topic, json!({ "state": "OFF", "transition": step_secs }))
        .await?;
    *light_on = false;
    Ok(())
}
