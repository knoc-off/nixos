use anyhow::Result;
use mqtt_automations::{Message, Runtime};
use serde_json::json;

/// Routes a wall button's Z2M actions to one or more device `/set` topics
/// using Z2M's native `{"state": "TOGGLE"}` — no light-state tracking needed,
/// each device toggles itself.
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("button-dispatcher").await?;

    let button_topic = rt.env_or("BUTTON_TOPIC", "zigbee2mqtt/button_1/action");
    let single_action = rt.env_or("SINGLE_ACTION", "single");
    let group_actions = rt.env_or("GROUP_ACTIONS", "double,hold");
    let group_actions: Vec<&str> = group_actions.split(',').map(str::trim).collect();

    let single_topics = topics_from_env(&rt, "SINGLE_TOPICS", "zigbee2mqtt/light_1/set");
    let group_topics = topics_from_env(
        &rt,
        "GROUP_TOPICS",
        "zigbee2mqtt/light_1/set,zigbee2mqtt/plug_1/set,zigbee2mqtt/plug_2/set,zigbee2mqtt/plug_3/set",
    );

    let mut msgs = rt.subscribe(&button_topic).await?;

    eprintln!(
        "button-dispatcher started: button={button_topic} single->{single_topics:?} \
         {group_actions:?}->{group_topics:?}"
    );

    loop {
        tokio::select! {
            Some(msg) = msgs.recv() => {
                let action = action_of(&msg);
                if action == single_action {
                    toggle_all(&rt, &single_topics).await;
                } else if group_actions.contains(&action.as_str()) {
                    toggle_all(&rt, &group_topics).await;
                }
            }
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}

fn topics_from_env(rt: &Runtime, key: &str, default: &str) -> Vec<String> {
    parse_csv(&rt.env_or(key, default))
}

fn parse_csv(s: &str) -> Vec<String> {
    s.split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

async fn toggle_all(rt: &Runtime, topics: &[String]) {
    for topic in topics {
        if let Err(e) = rt.publish(topic, json!({ "state": "TOGGLE" })).await {
            eprintln!("toggle {topic} failed: {e}");
        }
    }
}

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn action_of_handles_plain_string_and_object_payloads() {
        let plain = Message {
            topic: "t".into(),
            payload: serde_json::Value::String("double".into()),
        };
        assert_eq!(action_of(&plain), "double");

        let obj = Message {
            topic: "t".into(),
            payload: json!({ "action": "hold" }),
        };
        assert_eq!(action_of(&obj), "hold");

        let empty = Message {
            topic: "t".into(),
            payload: json!({}),
        };
        assert_eq!(action_of(&empty), "");
    }

    #[test]
    fn parse_csv_splits_trims_and_drops_empties() {
        assert_eq!(
            parse_csv(" a/set, b/set ,, c/set"),
            vec!["a/set", "b/set", "c/set"]
        );
    }
}
