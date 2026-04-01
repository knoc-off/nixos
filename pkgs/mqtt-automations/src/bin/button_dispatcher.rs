use std::collections::HashMap;

use anyhow::{Context, Result};
use mqtt_automations::Runtime;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Config {
    buttons: HashMap<String, HashMap<String, Action>>,
}

#[derive(Debug, Deserialize)]
struct Action {
    topic: String,
    payload: serde_json::Value,
}

#[tokio::main]
async fn main() -> Result<()> {
    let config_path = std::env::args()
        .nth(1)
        .context("usage: button-dispatcher <config.json>")?;

    let config: Config = serde_json::from_str(
        &std::fs::read_to_string(&config_path)
            .with_context(|| format!("reading {config_path}"))?,
    )
    .context("parsing config")?;

    let rt = Runtime::from_env("button-dispatcher").await?;

    // Subscribe to all button topics and build a lookup table.
    let mut receivers = Vec::new();
    for (topic, actions) in &config.buttons {
        let rx = rt.subscribe(topic).await?;
        tracing::info!(topic, actions = actions.len(), "registered button");
        receivers.push((topic.clone(), rx));
    }

    loop {
        // Wait for any button message across all subscriptions.
        let msg = tokio::select! {
            msg = async {
                loop {
                    for (_topic, rx) in receivers.iter_mut() {
                        if let Ok(msg) = rx.try_recv() {
                            return msg;
                        }
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(10)).await;
                }
            } => msg,
            _ = rt.shutdown_signal() => break,
        };

        // Look up the action for this payload value.
        let action_key = match &msg.payload {
            serde_json::Value::String(s) => s.clone(),
            serde_json::Value::Object(m) => {
                // Z2M sometimes sends {"action":"single"} on the main topic
                m.get("action")
                    .and_then(|v| v.as_str())
                    .unwrap_or_default()
                    .to_string()
            }
            _ => continue,
        };

        if let Some(actions) = config.buttons.get(&msg.topic) {
            if let Some(action) = actions.get(&action_key) {
                tracing::info!(
                    button = %msg.topic,
                    action = %action_key,
                    target = %action.topic,
                    "dispatching"
                );
                rt.publish(&action.topic, &action.payload).await?;
            }
        }
    }
    Ok(())
}
