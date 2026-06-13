use std::collections::HashMap;

use anyhow::{Context, Result};
use mqtt_automations::Runtime;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct Config {
    buttons: HashMap<String, HashMap<String, ActionSpec>>,
    #[serde(default)]
    groups: HashMap<String, Group>,
}

/// What a button action does. Untagged so the JSON stays terse:
///   {"topic": "...", "payload": {...}}   -> Direct
///   {"group": "living_room"}             -> Group
#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum ActionSpec {
    Group {
        group: String,
    },
    Direct {
        topic: String,
        payload: serde_json::Value,
    },
}

/// A group of devices toggled together via a shared internal on/off state.
#[derive(Debug, Deserialize)]
struct Group {
    members: Vec<GroupMember>,
}

#[derive(Debug, Deserialize)]
struct GroupMember {
    topic: String,
    on: serde_json::Value,
    off: serde_json::Value,
}

#[tokio::main(flavor = "current_thread")]
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

    // Internal on/off state per group. Starts off; resets on restart.
    let mut group_states: HashMap<String, bool> = HashMap::new();

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
                match action {
                    ActionSpec::Direct { topic, payload } => {
                        tracing::info!(
                            button = %msg.topic,
                            action = %action_key,
                            target = %topic,
                            "dispatching"
                        );
                        rt.publish(topic, payload).await?;
                    }
                    ActionSpec::Group { group } => {
                        let Some(grp) = config.groups.get(group) else {
                            tracing::warn!(group, "unknown group referenced");
                            continue;
                        };
                        // Flip the group's internal state and broadcast an
                        // explicit on/off to every member so they stay in sync.
                        let on = !group_states.get(group).copied().unwrap_or(false);
                        group_states.insert(group.clone(), on);
                        tracing::info!(
                            button = %msg.topic,
                            action = %action_key,
                            %group,
                            state = if on { "ON" } else { "OFF" },
                            members = grp.members.len(),
                            "dispatching group"
                        );
                        for member in &grp.members {
                            let payload = if on { &member.on } else { &member.off };
                            rt.publish(&member.topic, payload).await?;
                        }
                    }
                }
            }
        }
    }
    Ok(())
}
