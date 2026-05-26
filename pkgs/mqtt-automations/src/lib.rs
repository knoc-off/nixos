pub mod sun;

use std::collections::HashMap;
use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result};
use rumqttc::{AsyncClient, Event, Incoming, MqttOptions, QoS};
use serde::Serialize;
use tokio::sync::{mpsc, watch, Mutex};

/// A decoded MQTT message.
#[derive(Debug, Clone)]
pub struct Message {
    pub topic: String,
    pub payload: serde_json::Value,
}

// -- Setting: bidirectional HA ↔ MQTT value -----------------------------------

/// Types that can be parsed from MQTT JSON payloads and serialized back.
pub trait FromMqttPayload: Copy + Serialize {
    fn from_payload(value: &serde_json::Value) -> Option<Self>;
}

macro_rules! impl_from_mqtt_uint {
    ($($t:ty),+) => { $(
        impl FromMqttPayload for $t {
            fn from_payload(v: &serde_json::Value) -> Option<Self> {
                v.as_u64().and_then(|n| n.try_into().ok())
                    .or_else(|| v.as_f64().and_then(|n| {
                        let r = n.round();
                        if r >= 0.0 && r <= Self::MAX as f64 { Some(r as Self) } else { None }
                    }))
                    .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
            }
        }
    )+ };
}

impl_from_mqtt_uint!(u8, u16, u64);

impl FromMqttPayload for f64 {
    fn from_payload(v: &serde_json::Value) -> Option<Self> {
        v.as_f64()
            .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
    }
}

impl FromMqttPayload for bool {
    fn from_payload(v: &serde_json::Value) -> Option<Self> {
        v.as_bool().or_else(|| match v.as_str()? {
            "on" | "true" | "1" => Some(true),
            "off" | "false" | "0" => Some(false),
            _ => None,
        })
    }
}

/// A runtime-configurable value backed by an optional MQTT retained topic.
///
/// Created via [`Runtime::setting`]. If no topic is configured (env var
/// empty/unset), the setting always returns its initial value.
///
/// Bidirectional: call [`.get()`](Self::get) to read the latest value from HA,
/// or [`.set()`](Self::set) to push a new value back.
pub struct Setting<T> {
    rx: Option<mpsc::UnboundedReceiver<Message>>,
    current: T,
    topic: Option<String>,
    client: Option<AsyncClient>,
}

impl<T: FromMqttPayload> Setting<T> {
    /// Drain pending MQTT messages and return the latest value.
    pub fn get(&mut self) -> T {
        if let Some(ref mut rx) = self.rx {
            while let Ok(msg) = rx.try_recv() {
                if let Some(v) = T::from_payload(&msg.payload) {
                    self.current = v;
                }
            }
        }
        self.current
    }

    /// Publish a new value to the MQTT topic (retained) so HA picks it up.
    pub async fn set(&mut self, value: T) -> Result<()> {
        if let (Some(ref client), Some(ref topic)) = (&self.client, &self.topic) {
            let payload = serde_json::to_vec(&value)?;
            client
                .publish(topic, QoS::AtMostOnce, true, payload)
                .await
                .context("setting publish")?;
            self.current = value;
        }
        Ok(())
    }
}

type Subs = Arc<Mutex<HashMap<String, Vec<mpsc::UnboundedSender<Message>>>>>;

/// Core runtime — owns the MQTT connection, env helpers, and shutdown coordination.
pub struct Runtime {
    client: AsyncClient,
    subs: Subs,
    shutdown_tx: watch::Sender<bool>,
    shutdown_rx: watch::Receiver<bool>,
}

impl Runtime {
    /// Connect to MQTT and start the background event loop.
    ///
    /// Reads `MQTT_HOST` (default `127.0.0.1`) and `MQTT_PORT` (default `1883`)
    /// from the environment. Sets up tracing to stdout.
    pub async fn from_env(name: &str) -> Result<Self> {
        // Logging
        tracing_subscriber::fmt()
            .with_writer(std::io::stderr)
            .with_env_filter(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
            )
            .compact()
            .init();

        let host = Self::env_var("MQTT_HOST").unwrap_or_else(|| "127.0.0.1".into());
        let port: u16 = Self::env_var("MQTT_PORT")
            .and_then(|v| v.parse().ok())
            .unwrap_or(1883);

        let mut opts = MqttOptions::new(
            Self::env_var("MQTT_CLIENT_ID").unwrap_or_else(|| name.into()),
            &host,
            port,
        );
        opts.set_keep_alive(Duration::from_secs(30));

        let (client, eventloop) = AsyncClient::new(opts, 32);
        let subs: Subs = Arc::new(Mutex::new(HashMap::new()));
        let (shutdown_tx, shutdown_rx) = watch::channel(false);

        // Spawn the MQTT event-loop poller + message dispatcher.
        let disp_subs = subs.clone();
        let disp_shutdown = shutdown_rx.clone();
        tokio::spawn(Self::event_loop(eventloop, disp_subs, disp_shutdown));

        // Spawn signal handler.
        let sig_tx = shutdown_tx.clone();
        tokio::spawn(async move {
            Self::wait_for_signal().await;
            let _ = sig_tx.send(true);
        });

        tracing::info!(name, %host, port, "mqtt connected");
        Ok(Self {
            client,
            subs,
            shutdown_tx,
            shutdown_rx,
        })
    }

    // -- env helpers ----------------------------------------------------------

    fn env_var(key: &str) -> Option<String> {
        std::env::var(key).ok()
    }

    pub fn env_or(&self, key: &str, default: &str) -> String {
        std::env::var(key).unwrap_or_else(|_| default.into())
    }

    pub fn env_parse<T: FromStr>(&self, key: &str, default: T) -> T {
        std::env::var(key)
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(default)
    }

    // -- mqtt -----------------------------------------------------------------

    /// Publish a JSON-serializable payload to a topic.
    pub async fn publish(&self, topic: &str, payload: impl Serialize) -> Result<()> {
        let json = serde_json::to_vec(&payload)?;
        self.client
            .publish(topic, QoS::AtMostOnce, false, json)
            .await
            .context("mqtt publish")?;
        tracing::debug!(topic, "published");
        Ok(())
    }

    /// Publish a retained message (survives broker restarts, delivered to
    /// future subscribers immediately).
    pub async fn publish_retained(&self, topic: &str, payload: impl Serialize) -> Result<()> {
        let json = serde_json::to_vec(&payload)?;
        self.client
            .publish(topic, QoS::AtMostOnce, true, json)
            .await
            .context("mqtt publish retained")?;
        tracing::debug!(topic, "published (retained)");
        Ok(())
    }

    /// Subscribe to a topic and receive messages on a channel.
    pub async fn subscribe(&self, topic: &str) -> Result<mpsc::UnboundedReceiver<Message>> {
        let (tx, rx) = mpsc::unbounded_channel();
        self.client
            .subscribe(topic, QoS::AtMostOnce)
            .await
            .context("mqtt subscribe")?;
        self.subs
            .lock()
            .await
            .entry(topic.to_string())
            .or_default()
            .push(tx);
        tracing::info!(topic, "subscribed");
        Ok(rx)
    }

    /// Create a [`Setting`] backed by an MQTT retained topic.
    ///
    /// `topic_env` is the name of the env var holding the MQTT topic.
    /// If the env var is empty or unset, the setting always returns `initial`
    /// and `.set()` is a no-op.
    pub async fn setting<T: FromMqttPayload>(
        &self,
        topic_env: &str,
        initial: T,
    ) -> Result<Setting<T>> {
        let topic = self.env_or(topic_env, "");
        if topic.is_empty() {
            return Ok(Setting {
                rx: None,
                current: initial,
                topic: None,
                client: None,
            });
        }
        tracing::info!(%topic, env = topic_env, "subscribed to setting");
        let rx = self.subscribe(&topic).await?;
        Ok(Setting {
            rx: Some(rx),
            current: initial,
            topic: Some(topic),
            client: Some(self.client.clone()),
        })
    }

    // -- lifecycle ------------------------------------------------------------

    /// Future that resolves when a shutdown signal (SIGTERM/SIGINT) is received.
    /// Safe to call repeatedly in `tokio::select!`.
    pub async fn shutdown_signal(&self) {
        let mut rx = self.shutdown_rx.clone();
        let _ = rx.wait_for(|&v| v).await;
    }

    /// Trigger shutdown programmatically.
    pub fn trigger_shutdown(&self) {
        let _ = self.shutdown_tx.send(true);
    }

    // -- internals ------------------------------------------------------------

    async fn event_loop(
        mut eventloop: rumqttc::EventLoop,
        subs: Subs,
        mut shutdown: watch::Receiver<bool>,
    ) {
        loop {
            let event = tokio::select! {
                event = eventloop.poll() => event,
                _ = shutdown.wait_for(|&v| v) => {
                    tracing::info!("event loop shutting down");
                    break;
                }
            };

            match event {
                Ok(Event::Incoming(Incoming::Publish(p))) => {
                    let payload = match serde_json::from_slice(&p.payload) {
                        Ok(v) => v,
                        Err(_) => serde_json::Value::String(
                            String::from_utf8_lossy(&p.payload).into_owned(),
                        ),
                    };
                    let msg = Message {
                        topic: p.topic.clone(),
                        payload,
                    };
                    let map = subs.lock().await;
                    if let Some(senders) = map.get(&p.topic) {
                        senders.iter().for_each(|tx| { let _ = tx.send(msg.clone()); });
                    }
                }
                Ok(_) => {}
                Err(e) => {
                    tracing::warn!("mqtt event-loop error: {e}");
                    tokio::time::sleep(Duration::from_millis(500)).await;
                }
            }
        }
    }

    async fn wait_for_signal() {
        use tokio::signal::unix::{signal, SignalKind};
        let mut sigterm = signal(SignalKind::terminate()).expect("sigterm handler");
        let mut sigint = signal(SignalKind::interrupt()).expect("sigint handler");
        tokio::select! {
            _ = sigterm.recv() => tracing::info!("received SIGTERM"),
            _ = sigint.recv() => tracing::info!("received SIGINT"),
        }
    }
}
