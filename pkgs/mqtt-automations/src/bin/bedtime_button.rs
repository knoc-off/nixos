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

    // Which Z2M actions we react to.
    let single_action = rt.env_or("SINGLE_ACTION", "single");
    let hold_action = rt.env_or("HOLD_ACTION", "hold");

    // Brightness levels (Z2M scale 0-254).
    let low_brightness: u8 = rt.env_parse("LOW_BRIGHTNESS", 25);
    let day_brightness: u8 = rt.env_parse("DAY_BRIGHTNESS", 254);

    // Evening window [EVENING_START_HOUR, DAY_START_HOUR): during it, a press
    // never goes to full brightness — on/dim presses land on low light.
    let evening_start_hour: u32 = rt.env_parse("EVENING_START_HOUR", 21);
    let day_start_hour: u32 = rt.env_parse("DAY_START_HOUR", 6);

    // Press-and-hold: go to low light, then turn off by itself after this delay.
    let hold_off_minutes: u64 = rt.env_parse("HOLD_OFF_MINUTES", 5);

    let tz_name = rt.env_or("TIMEZONE", "Europe/Berlin");
    let tz: Tz = tz_name.parse().unwrap_or_else(|_| {
        tracing::warn!("invalid TIMEZONE '{tz_name}', falling back to UTC");
        chrono_tz::UTC
    });

    let mut button_msgs = rt.subscribe(&button_topic).await?;
    let mut state_msgs = rt.subscribe(&state_topic).await?;

    // Tracked device state, kept fresh from Z2M state echoes.
    let mut light_on = false;
    let mut brightness: u8 = day_brightness;

    tracing::info!(
        button = %button_topic, set = %set_topic, state = %state_topic,
        low_brightness, day_brightness, evening_start_hour, day_start_hour,
        hold_off_minutes, %tz_name,
        "bedtime-button started"
    );

    loop {
        tokio::select! {
            Some(msg) = state_msgs.recv() => {
                update_state(&msg, &mut light_on, &mut brightness);
            }
            Some(msg) = button_msgs.recv() => {
                let action = action_of(&msg);
                let hour = Local::now().with_timezone(&tz).hour();
                let evening = is_evening(hour, evening_start_hour, day_start_hour);
                // "Low" with a small margin so bulb rounding still counts.
                let is_low = brightness <= low_brightness.saturating_add(LOW_MARGIN);

                if action == hold_action {
                    tracing::info!(hour, "hold — low light, auto-off in {hold_off_minutes}m");
                    hold_to_off(
                        &rt,
                        &set_topic,
                        low_brightness,
                        hold_off_minutes * 60,
                        &mut button_msgs,
                        &mut state_msgs,
                        &mut light_on,
                        &mut brightness,
                    )
                    .await?;
                } else if action == single_action {
                    if light_on && is_low {
                        // Already dim → turn off.
                        tracing::info!(hour, "single — on & low → OFF");
                        rt.publish(&set_topic, json!({ "state": "OFF" })).await?;
                    } else if light_on && evening {
                        // On & bright, evening → drop to low light.
                        tracing::info!(hour, "single — on & bright, evening → low");
                        set_low(&rt, &set_topic, low_brightness).await?;
                    } else if light_on {
                        // On & bright, daytime → plain toggle off.
                        tracing::info!(hour, "single — on & bright, day → OFF");
                        rt.publish(&set_topic, json!({ "state": "OFF" })).await?;
                    } else if evening {
                        // Off, evening → low light (never full brightness).
                        tracing::info!(hour, "single — off, evening → low");
                        set_low(&rt, &set_topic, low_brightness).await?;
                    } else {
                        // Off, daytime → full brightness.
                        tracing::info!(hour, "single — off, day → full");
                        rt.publish(
                            &set_topic,
                            json!({ "state": "ON", "brightness": day_brightness }),
                        )
                        .await?;
                    }
                }
            }
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}

/// Margin (Z2M units) added to `low_brightness` when deciding "is the light
/// already dim?", to tolerate bulb rounding of the reported level.
const LOW_MARGIN: u8 = 10;

/// True when the local `hour` falls in the evening window `[start, day_start)`,
/// wrapping across midnight (e.g. 21:00–06:00).
fn is_evening(hour: u32, start: u32, day_start: u32) -> bool {
    if start <= day_start {
        hour >= start && hour < day_start
    } else {
        hour >= start || hour < day_start
    }
}

/// Turn the light on at the low level with a gentle transition.
async fn set_low(rt: &Runtime, set_topic: &str, low: u8) -> Result<()> {
    rt.publish(
        set_topic,
        json!({ "state": "ON", "brightness": low, "transition": 1 }),
    )
    .await
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

/// Drop to low light, then turn off after `delay_secs`. Any button press during
/// the wait cancels the countdown and turns the light off immediately.
#[allow(clippy::too_many_arguments)]
async fn hold_to_off(
    rt: &Runtime,
    set_topic: &str,
    low: u8,
    delay_secs: u64,
    button_msgs: &mut UnboundedReceiver<Message>,
    state_msgs: &mut UnboundedReceiver<Message>,
    light_on: &mut bool,
    brightness: &mut u8,
) -> Result<()> {
    set_low(rt, set_topic, low).await?;
    *light_on = true;
    *brightness = low;

    tokio::select! {
        _ = tokio::time::sleep(std::time::Duration::from_secs(delay_secs)) => {
            tracing::info!("hold timer elapsed — light off");
            rt.publish(set_topic, json!({ "state": "OFF", "transition": 2 })).await?;
            *light_on = false;
        }
        Some(_) = button_msgs.recv() => {
            tracing::info!("hold countdown cancelled by button — turning off now");
            rt.publish(set_topic, json!({ "state": "OFF" })).await?;
            *light_on = false;
        }
        _ = drain_state(state_msgs, light_on, brightness) => {}
        _ = rt.shutdown_signal() => {}
    }
    Ok(())
}

/// Keep tracked state fresh from Z2M echoes; never resolves so it only runs as
/// a `select!` background branch.
async fn drain_state(
    state_msgs: &mut UnboundedReceiver<Message>,
    light_on: &mut bool,
    brightness: &mut u8,
) {
    while let Some(msg) = state_msgs.recv().await {
        update_state(&msg, light_on, brightness);
    }
}
