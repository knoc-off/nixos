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

        let mut opts = MqttOptions::new(name, &host, port);
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
