use std::time::Instant;

use anyhow::Result;
use mqtt_automations::Runtime;

#[tokio::main]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("cat-doorbell").await?;

    let sensor = rt.env_or("SENSOR_TOPIC", "zigbee2mqtt/motion_sensor");
    let ntfy_url = rt.env_or("NTFY_URL", "https://ntfy.niko.ink");
    let ntfy_topic = rt.env_or("NTFY_TOPIC", "cat-doorbell");
    let cooldown: u64 = rt.env_parse("COOLDOWN_SECONDS", 300);
    let title = rt.env_or("NOTIFICATION_TITLE", "Cat Doorbell");

    let token = read_token(&rt)?;
    if token.is_empty() {
        tracing::error!("no ntfy token configured — set NTFY_TOKEN_FILE or NTFY_TOKEN");
    }

    let mut msgs = rt.subscribe(&sensor).await?;
    let mut last_notification: Option<Instant> = None;
    let mut notified_this_session = false;

    tracing::info!(topic = %sensor, cooldown, "watching sensor");

    loop {
        tokio::select! {
            Some(msg) = msgs.recv() => {
                let presence = msg.payload.get("presence").and_then(|v| v.as_bool()).unwrap_or(false);
                let motion = msg.payload.get("motion_state")
                    .and_then(|v| v.as_str())
                    .unwrap_or("none");

                if !presence {
                    if notified_this_session {
                        tracing::info!("presence ended, resetting");
                    }
                    notified_this_session = false;
                    continue;
                }

                if !notified_this_session && matches!(motion, "large" | "small") {
                    if let Some(last) = last_notification {
                        if last.elapsed().as_secs() < cooldown {
                            tracing::info!("cooldown active, skipping");
                            continue;
                        }
                    }

                    let message = format!("Movement detected ({motion})");
                    match send_notification(&ntfy_url, &ntfy_topic, &token, &title, &message) {
                        Ok(()) => {
                            last_notification = Some(Instant::now());
                            notified_this_session = true;
                            tracing::info!(%message, "notification sent");
                        }
                        Err(e) => tracing::error!("notification failed: {e}"),
                    }
                }
            }
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}

fn read_token(rt: &Runtime) -> Result<String> {
    let token_file = rt.env_or("NTFY_TOKEN_FILE", "");
    if !token_file.is_empty() {
        let token = std::fs::read_to_string(&token_file)
            .map(|s| s.trim().to_string())
            .unwrap_or_else(|e| {
                tracing::warn!("could not read token file {token_file}: {e}");
                String::new()
            });
        if !token.is_empty() {
            tracing::info!("loaded ntfy token from {token_file}");
            return Ok(token);
        }
    }
    Ok(rt.env_or("NTFY_TOKEN", ""))
}

fn send_notification(
    url: &str,
    topic: &str,
    token: &str,
    title: &str,
    message: &str,
) -> Result<()> {
    let resp = ureq::post(&format!("{url}/{topic}"))
        .set("Authorization", &format!("Bearer {token}"))
        .set("Title", title)
        .set("Priority", "high")
        .set("Tags", "cat")
        .send_string(message)?;

    if resp.status() >= 400 {
        anyhow::bail!("ntfy returned {}", resp.status());
    }
    Ok(())
}
