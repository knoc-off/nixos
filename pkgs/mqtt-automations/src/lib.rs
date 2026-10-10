pub mod arbiter;
pub mod curves;
pub mod script;
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

type Subs = Arc<Mutex<HashMap<String, mpsc::UnboundedSender<Message>>>>;

/// Core runtime — owns the MQTT connection, env helpers, and shutdown coordination.
pub struct Runtime {
    client: AsyncClient,
    subs: Subs,
    shutdown_rx: watch::Receiver<bool>,
}

impl Runtime {
    /// Connect to MQTT and start the background event loop.
    ///
    /// Reads `MQTT_HOST` (default `127.0.0.1`) and `MQTT_PORT` (default `1883`)
    /// from the environment.
    pub async fn from_env(name: &str) -> Result<Self> {
        let host = env_or("MQTT_HOST", "127.0.0.1");
        let port: u16 = env_parse("MQTT_PORT", 1883);

        let mut opts = MqttOptions::new(env_or("MQTT_CLIENT_ID", name), &host, port);
        opts.set_keep_alive(Duration::from_secs(30));

        let (client, eventloop) = AsyncClient::new(opts, 32);
        let subs: Subs = Arc::new(Mutex::new(HashMap::new()));
        let (shutdown_tx, shutdown_rx) = watch::channel(false);

        // Spawn the MQTT event-loop poller + message dispatcher.
        let disp_subs = subs.clone();
        let disp_shutdown = shutdown_rx.clone();
        tokio::spawn(Self::event_loop(eventloop, disp_subs, disp_shutdown));

        // Spawn signal handler.
        tokio::spawn(async move {
            Self::wait_for_signal().await;
            let _ = shutdown_tx.send(true);
        });

        eprintln!("[{name}] mqtt connected: {host}:{port}");
        Ok(Self {
            client,
            subs,
            shutdown_rx,
        })
    }

    pub fn env_or(&self, key: &str, default: &str) -> String {
        env_or(key, default)
    }

    pub fn env_parse<T: FromStr>(&self, key: &str, default: T) -> T {
        env_parse(key, default)
    }

    /// Publish a JSON-serializable payload to a topic.
    pub async fn publish(&self, topic: &str, payload: impl Serialize) -> Result<()> {
        let json = serde_json::to_vec(&payload)?;
        self.client
            .publish(topic, QoS::AtMostOnce, false, json)
            .await
            .context("mqtt publish")?;
        Ok(())
    }

    /// Publish a JSON-serializable payload to a topic with the retain flag set.
    pub async fn publish_retained(&self, topic: &str, payload: impl Serialize) -> Result<()> {
        let json = serde_json::to_vec(&payload)?;
        self.client
            .publish(topic, QoS::AtMostOnce, true, json)
            .await
            .context("mqtt publish (retained)")?;
        Ok(())
    }

    /// Subscribe to a topic and receive messages on a channel.
    pub async fn subscribe(&self, topic: &str) -> Result<mpsc::UnboundedReceiver<Message>> {
        self.subscribe_many([topic]).await
    }

    /// Subscribe to several topics, all delivered in arrival order on one
    /// channel -- for state machines that need a single ordered event stream.
    /// Topics are exact; the dispatcher does not match MQTT wildcards.
    pub async fn subscribe_many(
        &self,
        topics: impl IntoIterator<Item = impl Into<String>>,
    ) -> Result<mpsc::UnboundedReceiver<Message>> {
        let (tx, rx) = mpsc::unbounded_channel();
        for topic in topics {
            let topic = topic.into();
            self.client
                .subscribe(&topic, QoS::AtMostOnce)
                .await
                .with_context(|| format!("mqtt subscribe {topic}"))?;
            self.subs.lock().await.insert(topic, tx.clone());
        }
        Ok(rx)
    }

    /// Future that resolves when a shutdown signal (SIGTERM/SIGINT) is received.
    /// Safe to call repeatedly in `tokio::select!`.
    pub async fn shutdown_signal(&self) {
        let mut rx = self.shutdown_rx.clone();
        let _ = rx.wait_for(|&v| v).await;
    }

    async fn event_loop(
        mut eventloop: rumqttc::EventLoop,
        subs: Subs,
        mut shutdown: watch::Receiver<bool>,
    ) {
        loop {
            let event = tokio::select! {
                event = eventloop.poll() => event,
                _ = shutdown.wait_for(|&v| v) => break,
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
                    if let Some(tx) = subs.lock().await.get(&p.topic) {
                        let _ = tx.send(msg);
                    }
                }
                Ok(_) => {}
                Err(e) => {
                    eprintln!("mqtt event-loop error: {e}");
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
            _ = sigterm.recv() => {}
            _ = sigint.recv() => {}
        }
    }
}

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key).unwrap_or_else(|_| default.into())
}

fn env_parse<T: FromStr>(key: &str, default: T) -> T {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}
