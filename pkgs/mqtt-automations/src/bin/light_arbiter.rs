//! The only process that writes to z2m light and plug `/set` topics.
//!
//! Rooms publish what they want; this decides, per bulb, whether the bulb
//! listens (see `mqtt_automations::arbiter`), and turns the result into z2m
//! commands -- one group command when a whole room changes identically, so
//! the bulbs don't pop on one after another.
//!
//! Contract (all payloads JSON, `transition` in seconds):
//!   - `lights/<room>/auto` (retained, from the room):
//!     `{ "bulbs": { "<bulb>": Target, ... }, "scale": 0..1, "transition": s }`.
//!     Retained so a restarted arbiter can adopt every bulb straight away.
//!   - `lights/<room>/user` (from the room, never retained): a button
//!     gesture, `{ "bulbs": {...}, "transition": s }`. Applied and held.
//!   - `lights/<room>/release` (from the room, never retained): reset
//!     point reached, every held bulb in the room goes back to auto.
//!   - `lights/<room>/<bulb>/release`: the same for one bulb (HA button).
//!   - `lights/<room>/<bulb>/state` (retained, from here):
//!     `{ "mode": "auto"|"held"|"unknown", "on", "brightness", "color_temp" }`.
//!
//! `Target` is `{ "on": bool, "brightness"?: 1-254, "color_temp"?: mireds }`.
//!
//! Config: a JSON file at `$CONFIG`, see [`Config`].

use std::collections::{BTreeMap, HashMap};
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use mqtt_automations::arbiter::{self, Bulb, Command, Input, Mode, Target};
use mqtt_automations::{Message, Runtime};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
struct Config {
    rooms: BTreeMap<String, RoomConfig>,
}

#[derive(Deserialize)]
struct RoomConfig {
    /// z2m group containing exactly this room's bulbs, if there is one.
    #[serde(default)]
    group: Option<String>,
    bulbs: BTreeMap<String, BulbConfig>,
}

#[derive(Deserialize)]
struct BulbConfig {
    /// z2m friendly name.
    device: String,
    #[serde(default = "yes")]
    dimmable: bool,
}

fn yes() -> bool {
    true
}

#[derive(Deserialize)]
struct RoomMessage {
    #[serde(default)]
    bulbs: BTreeMap<String, Target>,
    #[serde(default = "full_scale")]
    scale: f32,
    #[serde(default)]
    transition: f32,
}

fn full_scale() -> f32 {
    1.0
}

impl RoomMessage {
    fn transition(&self) -> Duration {
        // Rooms are a trust boundary of sorts: a NaN or negative value must
        // not panic the one process that owns every light.
        Duration::try_from_secs_f32(self.transition).unwrap_or_default()
    }
}

/// One MQTT publish.
#[derive(Debug, PartialEq)]
struct Out {
    topic: String,
    payload: Value,
    retain: bool,
}

#[derive(Clone, Copy)]
enum Route {
    Auto(usize),
    User(usize),
    Release(usize),
    BulbRelease(usize, usize),
    Report(usize, usize),
}

struct BulbSlot {
    name: String,
    device: String,
    dimmable: bool,
    bulb: Bulb,
    published: Option<Value>,
}

struct Room {
    name: String,
    group: Option<String>,
    bulbs: Vec<BulbSlot>,
}

/// All routing and z2m formatting, without MQTT -- so it can be tested.
struct House {
    rooms: Vec<Room>,
    routes: HashMap<String, Route>,
}

impl House {
    fn new(cfg: Config) -> Self {
        let mut routes = HashMap::new();
        let rooms = cfg
            .rooms
            .into_iter()
            .enumerate()
            .map(|(r, (name, room))| {
                let base = format!("lights/{name}");
                routes.insert(format!("{base}/auto"), Route::Auto(r));
                routes.insert(format!("{base}/user"), Route::User(r));
                routes.insert(format!("{base}/release"), Route::Release(r));
                let bulbs = room
                    .bulbs
                    .into_iter()
                    .enumerate()
                    .map(|(b, (bulb_name, bulb))| {
                        routes.insert(
                            format!("{base}/{bulb_name}/release"),
                            Route::BulbRelease(r, b),
                        );
                        routes.insert(format!("zigbee2mqtt/{}", bulb.device), Route::Report(r, b));
                        BulbSlot {
                            name: bulb_name,
                            device: bulb.device,
                            dimmable: bulb.dimmable,
                            bulb: Bulb::new(arbiter::Config {
                                dimmable: bulb.dimmable,
                                ..arbiter::Config::default()
                            }),
                            published: None,
                        }
                    })
                    .collect();
                Room {
                    name,
                    group: room.group,
                    bulbs,
                }
            })
            .collect();
        Self { rooms, routes }
    }

    fn topics(&self) -> Vec<String> {
        self.routes.keys().cloned().collect()
    }

    /// Ask every bulb for its current state, so startup can adopt it.
    fn startup(&self) -> Vec<Out> {
        self.rooms
            .iter()
            .flat_map(|room| &room.bulbs)
            .map(|slot| Out {
                topic: format!("zigbee2mqtt/{}/get", slot.device),
                payload: json!({ "state": "" }),
                retain: false,
            })
            .collect()
    }

    fn deadline(&self) -> Option<Instant> {
        self.rooms
            .iter()
            .flat_map(|room| &room.bulbs)
            .filter_map(|slot| slot.bulb.deadline())
            .min()
    }

    fn handle(&mut self, msg: &Message, now: Instant) -> Vec<Out> {
        let Some(&route) = self.routes.get(&msg.topic) else {
            return Vec::new();
        };
        let (r, inputs) = match route {
            Route::Auto(r) | Route::User(r) => {
                let Some(m) = parse::<RoomMessage>(msg) else {
                    return Vec::new();
                };
                let transition = m.transition();
                let user = matches!(route, Route::User(_));
                let bulbs = &self.rooms[r].bulbs;
                let inputs = m
                    .bulbs
                    .into_iter()
                    .filter_map(|(name, target)| {
                        let Some(b) = bulbs.iter().position(|s| s.name == name) else {
                            eprintln!("{}: unknown bulb {name:?}", msg.topic);
                            return None;
                        };
                        let input = if user {
                            Input::User { target, transition }
                        } else {
                            Input::Auto {
                                target,
                                scale: m.scale,
                                transition,
                            }
                        };
                        Some((b, input))
                    })
                    .collect();
                (r, inputs)
            }
            Route::Release(r) => {
                let transition =
                    parse::<RoomMessage>(msg).map_or_else(Duration::default, |m| m.transition());
                let n = self.rooms[r].bulbs.len();
                (
                    r,
                    (0..n).map(|b| (b, Input::Release { transition })).collect(),
                )
            }
            Route::BulbRelease(r, b) => (
                r,
                vec![(
                    b,
                    Input::Release {
                        transition: Duration::default(),
                    },
                )],
            ),
            Route::Report(r, b) => match parse_report(&msg.payload) {
                Some(report) => (r, vec![(b, Input::Report(report))]),
                None => return Vec::new(),
            },
        };
        self.step_room(r, inputs, now)
    }

    fn tick(&mut self, now: Instant) -> Vec<Out> {
        (0..self.rooms.len())
            .flat_map(|r| {
                let due: Vec<_> = self.rooms[r]
                    .bulbs
                    .iter()
                    .enumerate()
                    .filter(|(_, s)| s.bulb.deadline().is_some_and(|at| at <= now))
                    .map(|(b, _)| (b, Input::Tick))
                    .collect();
                self.step_room(r, due, now)
            })
            .collect()
    }

    /// Feed the inputs to their bulbs as one batch, so a room-wide change
    /// can go out as a single group command.
    fn step_room(&mut self, r: usize, inputs: Vec<(usize, Input)>, now: Instant) -> Vec<Out> {
        let room = &mut self.rooms[r];
        let mut commands: Vec<(usize, Command)> = Vec::new();
        for (b, input) in inputs {
            let slot = &mut room.bulbs[b];
            let before = slot.bulb.mode;
            if let Some(cmd) = slot.bulb.step(input, now) {
                commands.push((b, cmd));
            }
            log_mode_change(&room.name, slot, before);
        }

        let mut out = Vec::new();
        let all_same =
            commands.len() == room.bulbs.len() && commands.windows(2).all(|w| w[0].1 == w[1].1);
        // A mixed room (bulbs and plugs) never matches as all-same in
        // practice, but a group of only plugs must still send plug payloads.
        let dimmable = room.bulbs.iter().all(|s| s.dimmable);
        match (&room.group, commands.first()) {
            (Some(group), Some(&(_, cmd))) if all_same && room.bulbs.len() > 1 => {
                out.push(set(group, cmd, dimmable));
            }
            _ => out.extend(commands.iter().map(|&(b, cmd)| {
                let slot = &room.bulbs[b];
                set(&slot.device, cmd, slot.dimmable)
            })),
        }
        for slot in &mut room.bulbs {
            out.extend(publish_state(&room.name, slot));
        }
        out
    }
}

fn log_mode_change(room: &str, slot: &BulbSlot, before: Mode) {
    let after = slot.bulb.mode;
    if after != before {
        eprintln!("{room}/{}: {before:?} -> {after:?}", slot.name);
    }
}

fn parse<T: serde::de::DeserializeOwned>(msg: &Message) -> Option<T> {
    // An empty payload (e.g. a bare release) arrives as an empty string.
    let payload = match &msg.payload {
        Value::String(s) if s.is_empty() => json!({}),
        v => v.clone(),
    };
    serde_json::from_value(payload)
        .inspect_err(|e| eprintln!("{}: bad payload: {e}", msg.topic))
        .ok()
}

/// A z2m device state message. Messages without `state` (availability,
/// partial updates) are not reports.
fn parse_report(payload: &Value) -> Option<Target> {
    let on = match payload.get("state")?.as_str()? {
        "ON" => true,
        "OFF" => false,
        _ => return None,
    };
    let number = |key| payload.get(key).and_then(Value::as_u64);
    Some(Target {
        on,
        brightness: number("brightness").map_or(Target::FULL, |b| b.clamp(1, 254) as u8),
        color_temp: number("color_temp").and_then(|c| u16::try_from(c).ok()),
    })
}

fn set(device: &str, cmd: Command, dimmable: bool) -> Out {
    let t = cmd.target;
    let mut payload = json!({ "state": if t.on { "ON" } else { "OFF" } });
    if t.on && dimmable {
        payload["brightness"] = json!(t.brightness);
        if let Some(ct) = t.color_temp {
            payload["color_temp"] = json!(ct);
        }
    }
    if !cmd.transition.is_zero() {
        // Tenths: z2m transitions are in 0.1s units on the wire anyway.
        let secs = (cmd.transition.as_secs_f64() * 10.0).round() / 10.0;
        payload["transition"] = json!(secs);
    }
    Out {
        topic: format!("zigbee2mqtt/{device}/set"),
        payload,
        retain: false,
    }
}

fn publish_state(room: &str, slot: &mut BulbSlot) -> Option<Out> {
    let t = slot.bulb.showing()?;
    let mode = match slot.bulb.mode {
        Mode::Unknown => "unknown",
        Mode::Auto => "auto",
        Mode::Held(_) => "held",
    };
    let payload = json!({
        "mode": mode,
        "on": t.on,
        "brightness": t.brightness,
        "color_temp": t.color_temp,
    });
    if slot.published.as_ref() == Some(&payload) {
        return None;
    }
    slot.published = Some(payload.clone());
    Some(Out {
        topic: format!("lights/{room}/{}/state", slot.name),
        payload,
        retain: true,
    })
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("light-arbiter").await?;
    let path = rt.env_or("CONFIG", "");
    let cfg: Config = serde_json::from_str(
        &std::fs::read_to_string(&path).with_context(|| format!("reading CONFIG {path:?}"))?,
    )
    .context("parsing CONFIG")?;

    let mut house = House::new(cfg);
    let mut msgs = rt.subscribe_many(house.topics()).await?;
    for out in house.startup() {
        send(&rt, out).await;
    }
    eprintln!("light-arbiter started: {} rooms", house.rooms.len());

    loop {
        let deadline = house.deadline();
        let wake = async {
            match deadline {
                Some(at) => tokio::time::sleep_until(at.into()).await,
                None => std::future::pending().await,
            }
        };
        let outs = tokio::select! {
            Some(msg) = msgs.recv() => house.handle(&msg, Instant::now()),
            () = wake => house.tick(Instant::now()),
            () = rt.shutdown_signal() => break,
        };
        for out in outs {
            send(&rt, out).await;
        }
    }
    Ok(())
}

/// A failed publish is logged, not fatal: the next event republishes.
async fn send(rt: &Runtime, out: Out) {
    let result = if out.retain {
        rt.publish_retained(&out.topic, &out.payload).await
    } else {
        rt.publish(&out.topic, &out.payload).await
    };
    if let Err(e) = result {
        eprintln!("publish {} failed: {e}", out.topic);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn house(group: Option<&str>, bulbs: &[(&str, bool)]) -> House {
        let bulbs = bulbs
            .iter()
            .map(|&(name, dimmable)| {
                let cfg = json!({ "device": format!("hall_{name}"), "dimmable": dimmable });
                (name.to_string(), cfg)
            })
            .collect::<serde_json::Map<_, _>>();
        let cfg = json!({ "rooms": { "hall": { "group": group, "bulbs": bulbs } } });
        House::new(serde_json::from_value(cfg).unwrap())
    }

    fn msg(topic: &str, payload: Value) -> Message {
        Message {
            topic: topic.into(),
            payload,
        }
    }

    fn sets(outs: &[Out]) -> Vec<(&str, &Value)> {
        outs.iter()
            .filter(|o| o.topic.ends_with("/set"))
            .map(|o| (o.topic.as_str(), &o.payload))
            .collect()
    }

    /// Both bulbs reported on at 100 and adopted, clock past settle.
    fn adopted(h: &mut House) -> Instant {
        let now = Instant::now();
        for d in ["hall_a", "hall_b"] {
            h.handle(
                &msg(
                    &format!("zigbee2mqtt/{d}"),
                    json!({ "state": "ON", "brightness": 100 }),
                ),
                now,
            );
        }
        h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "a": { "on": true, "brightness": 100 }, "b": { "on": true, "brightness": 100 } } }),
            ),
            now,
        );
        now + Duration::from_secs(10)
    }

    #[test]
    fn room_wide_identical_change_goes_out_as_one_group_command() {
        let mut h = house(Some("hall_group"), &[("a", true), ("b", true)]);
        let now = adopted(&mut h);
        let outs = h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "a": { "on": true, "brightness": 50 }, "b": { "on": true, "brightness": 50 } }, "transition": 0.4 }),
            ),
            now,
        );
        assert_eq!(
            sets(&outs),
            vec![(
                "zigbee2mqtt/hall_group/set",
                &json!({ "state": "ON", "brightness": 50, "transition": 0.4 })
            )]
        );
    }

    #[test]
    fn differing_targets_fall_back_to_per_bulb_commands() {
        let mut h = house(Some("hall_group"), &[("a", true), ("b", true)]);
        let now = adopted(&mut h);
        let outs = h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "a": { "on": true, "brightness": 50 }, "b": { "on": true, "brightness": 60 } } }),
            ),
            now,
        );
        let topics: Vec<_> = sets(&outs).into_iter().map(|(t, _)| t).collect();
        assert_eq!(topics, ["zigbee2mqtt/hall_a/set", "zigbee2mqtt/hall_b/set"]);
    }

    #[test]
    fn held_bulb_breaks_the_group_and_publishes_held_state() {
        let mut h = house(Some("hall_group"), &[("a", true), ("b", true)]);
        let now = adopted(&mut h);
        let outs = h.handle(&msg("zigbee2mqtt/hall_a", json!({ "state": "OFF" })), now);
        assert!(outs
            .iter()
            .any(|o| o.topic == "lights/hall/a/state" && o.retain && o.payload["mode"] == "held"));
        let outs = h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "a": { "on": true, "brightness": 50 }, "b": { "on": true, "brightness": 50 } } }),
            ),
            now,
        );
        let topics: Vec<_> = sets(&outs).into_iter().map(|(t, _)| t).collect();
        assert_eq!(topics, ["zigbee2mqtt/hall_b/set"]);

        let outs = h.handle(&msg("lights/hall/a/release", json!("")), now);
        let topics: Vec<_> = sets(&outs).into_iter().map(|(t, _)| t).collect();
        assert_eq!(topics, ["zigbee2mqtt/hall_a/set"]);
    }

    #[test]
    fn plug_commands_carry_only_state() {
        let mut h = house(None, &[("p", false)]);
        let now = Instant::now();
        h.handle(
            &msg("zigbee2mqtt/hall_p", json!({ "state": "OFF", "power": 0 })),
            now,
        );
        h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "p": { "on": false } } }),
            ),
            now,
        );
        let outs = h.handle(
            &msg(
                "lights/hall/user",
                json!({ "bulbs": { "p": { "on": true } }, "transition": 0.4 }),
            ),
            now + Duration::from_secs(10),
        );
        assert_eq!(
            sets(&outs),
            vec![("zigbee2mqtt/hall_p/set", &json!({ "state": "ON" }))]
        );
    }

    #[test]
    fn plug_fade_off_fires_on_tick() {
        let mut h = house(None, &[("p", false)]);
        let now = Instant::now();
        h.handle(&msg("zigbee2mqtt/hall_p", json!({ "state": "ON" })), now);
        h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "p": { "on": true } } }),
            ),
            now,
        );
        let outs = h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "p": { "on": true } }, "scale": 0.0, "transition": 60 }),
            ),
            now,
        );
        assert!(sets(&outs).is_empty());
        let at = h.deadline().expect("off scheduled");
        assert!(h.tick(at - Duration::from_secs(1)).is_empty());
        assert_eq!(
            sets(&h.tick(at)),
            vec![("zigbee2mqtt/hall_p/set", &json!({ "state": "OFF" }))]
        );
    }

    #[test]
    fn garbage_is_ignored_not_fatal() {
        let mut h = house(None, &[("a", true)]);
        let now = Instant::now();
        assert!(h
            .handle(
                &msg("lights/hall/auto", json!({ "transition": -1, "bulbs": 3 })),
                now
            )
            .is_empty());
        assert!(h
            .handle(
                &msg("zigbee2mqtt/hall_a", json!({ "linkquality": 80 })),
                now
            )
            .is_empty());
        assert!(h
            .handle(
                &msg(
                    "lights/hall/auto",
                    json!({ "bulbs": { "nope": { "on": true } } })
                ),
                now
            )
            .is_empty());
        assert!(h.handle(&msg("other/topic", json!({})), now).is_empty());
    }

    #[test]
    fn negative_transition_does_not_panic() {
        let mut h = house(None, &[("a", true)]);
        let now = Instant::now();
        h.handle(
            &msg(
                "zigbee2mqtt/hall_a",
                json!({ "state": "ON", "brightness": 100 }),
            ),
            now,
        );
        h.handle(
            &msg(
                "lights/hall/auto",
                json!({ "bulbs": { "a": { "on": true, "brightness": 100 } }, "transition": -5 }),
            ),
            now,
        );
    }

    #[test]
    fn startup_asks_every_bulb_for_its_state() {
        let h = house(None, &[("a", true), ("b", false)]);
        let topics: Vec<_> = h.startup().into_iter().map(|o| o.topic).collect();
        assert_eq!(topics, ["zigbee2mqtt/hall_a/get", "zigbee2mqtt/hall_b/get"]);
    }
}
