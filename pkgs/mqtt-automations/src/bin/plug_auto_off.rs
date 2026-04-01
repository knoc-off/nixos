use anyhow::Result;
use mqtt_automations::Runtime;
use serde_json::json;

#[tokio::main]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("plug-auto-off").await?;
    let plug = rt.env_or("PLUG_TOPIC", "zigbee2mqtt/plug_1");
    let countdown: u64 = rt.env_parse("COUNTDOWN_SECONDS", 3600);

    let mut msgs = rt.subscribe(&plug).await?;
    let mut last_on = false;

    tracing::info!(topic = %plug, countdown, "watching plug");

    loop {
        tokio::select! {
            Some(msg) = msgs.recv() => {
                let on = msg.payload.get("state").and_then(|v| v.as_str()) == Some("ON");
                if on && !last_on {
                    tracing::info!("plug turned on, setting {countdown}s countdown");
                    rt.publish(&format!("{plug}/set"), json!({ "countdown": countdown })).await?;
                }
                last_on = on;
            }
            _ = rt.shutdown_signal() => break,
        }
    }
    Ok(())
}
