//! Every light in the house, in one process: each room's Lua script decides
//! what the room wants (`mqtt_automations::script`), and the arbiter
//! decides, per bulb, whether the bulb listens (`mqtt_automations::arbiter`)
//! -- the automation, or a person who changed it by button, HA or app.
//!
//! This is the only writer to z2m light and plug `/set` topics. A room-wide
//! identical change goes out as one group command, so bulbs don't pop on
//! one after another.
//!
//! MQTT surface, besides z2m:
//!   - `lights/<room>/<bulb>/state` (retained, from here):
//!     `{ "mode": "auto"|"held"|"unknown", "on", "brightness", "color_temp" }`.
//!   - `lights/<room>/<bulb>/release` (to here): hand one bulb back to the
//!     automation (the HA "release hold" button).
//!   - `lights/release` (to here): the same for every bulb in the house.
//!   - `lights/<room>/mode` (retained, from here): "held" if any of the
//!     room's bulbs is, else "auto".
//!   - `lights/<room>/<name>` (retained, from here): whatever the room's
//!     script `publish()`es -- the prelude's `occupied` and `scene`.
//!   - Room controls the prelude reads (`release`, `scene`, `automatic`
//!     under `lights/<room>/`) arrive as script topics.
//!
//! Config: a JSON file, see [`Config`]. `lights --check <file>` loads it and
//! every script without connecting, for build-time validation.

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use chrono::{DateTime, FixedOffset, Local};
use mqtt_automations::arbiter::{self, Bulb, Command, Input, Mode, Target};
use mqtt_automations::script::Script;
use mqtt_automations::{Message, Runtime};
use serde::Deserialize;
use serde_json::{json, Value};

/// Room -> arbiter -> room rounds per event. Scripts only react to what
/// changed, so this settles in one or two; the cap is a backstop against a
/// script bug turning into a hot loop.
const MAX_ROUNDS: usize = 8;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    latitude: f64,
    longitude: f64,
    rooms: BTreeMap<String, RoomConfig>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RoomConfig {
    /// z2m group containing exactly this room's bulbs, if there is one.
    #[serde(default)]
    group: Option<String>,
    bulbs: BTreeMap<String, BulbConfig>,
    /// The room's script; see `mqtt_automations::script` for the API.
    lua: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct BulbConfig {
    /// z2m friendly name.
    device: String,
    #[serde(default = "yes")]
    dimmable: bool,
}

fn yes() -> bool {
    true
}

/// One MQTT publish.
#[derive(Debug, PartialEq)]
struct Out {
    topic: String,
    payload: Value,
    retain: bool,
}

#[derive(Clone, Copy, Debug)]
enum Route {
    Report(usize, usize),
    BulbRelease(usize, usize),
    Script(usize),
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
    script: Script,
    /// Last `lights/<room>/mode` sent.
    mode: Option<&'static str>,
}

/// All routing and z2m formatting, without MQTT -- so it can be tested.
struct House {
    rooms: Vec<Room>,
    /// One topic can feed several rooms (a sensor on a shared doorway).
    routes: HashMap<String, Vec<Route>>,
}

impl House {
    fn new(cfg: Config, now: Instant, wall: DateTime<FixedOffset>) -> Result<Self> {
        let mut routes: HashMap<String, Vec<Route>> = HashMap::new();
        let mut rooms = Vec::new();
        for (r, (name, room)) in cfg.rooms.into_iter().enumerate() {
            let mut route = |topic: String, to: Route| routes.entry(topic).or_default().push(to);
            let lights = room
                .bulbs
                .iter()
                .map(|(n, b)| (n.clone(), b.device.clone()));
            let script = Script::new(
                &name,
                &room.lua,
                lights,
                (cfg.latitude, cfg.longitude),
                now,
                wall,
            )?;
            for topic in script.topics() {
                route(topic, Route::Script(r));
            }
            let bulbs = room
                .bulbs
                .into_iter()
                .enumerate()
                .map(|(b, (bulb_name, bulb))| {
                    route(
                        format!("lights/{name}/{bulb_name}/release"),
                        Route::BulbRelease(r, b),
                    );
                    route(format!("zigbee2mqtt/{}", bulb.device), Route::Report(r, b));
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
            rooms.push(Room {
                name,
                group: room.group,
                bulbs,
                script,
                mode: None,
            });
        }
        let mut seen = HashMap::new();
        for room in &rooms {
            for slot in &room.bulbs {
                if let Some(other) = seen.insert(&slot.device, &room.name) {
                    bail!("bulb {} is in both {other} and {}", slot.device, room.name);
                }
            }
        }
        Ok(Self { rooms, routes })
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

    /// The next moment anything changes by itself.
    fn deadline(&self) -> Option<Instant> {
        self.rooms
            .iter()
            .flat_map(|room| {
                let bulbs = room.bulbs.iter().filter_map(|s| s.bulb.deadline());
                bulbs.chain(room.script.deadline())
            })
            .min()
    }

    fn handle(&mut self, msg: &Message, now: Instant, wall: DateTime<FixedOffset>) -> Vec<Out> {
        let Some(routes) = self.routes.get(&msg.topic).cloned() else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for route in routes {
            out.extend(match route {
                Route::Report(r, b) => match parse_report(&msg.payload) {
                    Some(report) => self.step_bulbs(r, vec![(b, Input::Report(report))], now),
                    None => Vec::new(),
                },
                Route::BulbRelease(r, b) => {
                    let release = Input::Release {
                        transition: Duration::ZERO,
                    };
                    self.step_bulbs(r, vec![(b, release)], now)
                }
                Route::Script(r) => {
                    let reqs = self.rooms[r]
                        .script
                        .message(&msg.topic, &msg.payload, now, wall);
                    let inputs = self.named(r, reqs);
                    self.step_bulbs(r, inputs, now)
                }
            });
        }
        out
    }

    /// Timers: every room's script and every due bulb.
    fn tick(&mut self, now: Instant, wall: DateTime<FixedOffset>) -> Vec<Out> {
        let mut out = Vec::new();
        for r in 0..self.rooms.len() {
            let due = self.rooms[r]
                .bulbs
                .iter()
                .enumerate()
                .filter(|(_, s)| s.bulb.deadline().is_some_and(|at| at <= now))
                .map(|(b, _)| (b, Input::Tick))
                .collect();
            out.extend(self.step_bulbs(r, due, now));
            let reqs = self.rooms[r].script.tick(now, wall);
            let inputs = self.named(r, reqs);
            out.extend(self.step_bulbs(r, inputs, now));
        }
        out
    }

    /// Feed inputs to the bulbs as one batch, so a room-wide change can go
    /// out as a single group command. Bulb changes flow back to the room's
    /// script, whose answers are fed in the same way until it is quiet.
    fn step_bulbs(&mut self, r: usize, inputs: Vec<(usize, Input)>, now: Instant) -> Vec<Out> {
        let mut out = self.step_rounds(r, inputs, now);
        let room = &mut self.rooms[r];
        out.extend(
            room.script
                .take_published()
                .into_iter()
                .map(|(name, value)| Out {
                    topic: format!("lights/{}/{name}", room.name),
                    payload: value,
                    retain: true,
                }),
        );
        let mode = if room
            .bulbs
            .iter()
            .any(|s| matches!(s.bulb.mode, Mode::Held(_)))
        {
            "held"
        } else {
            "auto"
        };
        if room.mode != Some(mode) {
            room.mode = Some(mode);
            out.push(Out {
                topic: format!("lights/{}/mode", room.name),
                payload: json!(mode),
                retain: true,
            });
        }
        out
    }

    fn step_rounds(&mut self, r: usize, inputs: Vec<(usize, Input)>, now: Instant) -> Vec<Out> {
        let mut out = Vec::new();
        let mut queue = VecDeque::from([inputs]);
        for _ in 0..MAX_ROUNDS {
            let Some(inputs) = queue.pop_front() else {
                return out;
            };
            let changed = self.apply(r, inputs, now, &mut out);
            let room = &mut self.rooms[r];
            let mut answers = Vec::new();
            for b in changed {
                let slot = &room.bulbs[b];
                let Some(state) = slot.bulb.showing() else {
                    continue;
                };
                let held = matches!(slot.bulb.mode, Mode::Held(_));
                answers.extend(room.script.bulb(&slot.name, held, state));
            }
            let next = self.named(r, answers);
            if !next.is_empty() {
                queue.push_back(next);
            }
        }
        eprintln!("{}: script and arbiter did not settle", self.rooms[r].name);
        out
    }

    /// Step the bulbs, collect z2m commands into `out`, and return which
    /// bulbs' published state changed.
    fn apply(
        &mut self,
        r: usize,
        inputs: Vec<(usize, Input)>,
        now: Instant,
        out: &mut Vec<Out>,
    ) -> Vec<usize> {
        let room = &mut self.rooms[r];
        // Only each bulb's last command goes out: a handler that releases
        // and then sets a new target must not flash the bulb in between.
        let mut commands: BTreeMap<usize, Command> = BTreeMap::new();
        for (b, input) in inputs {
            let slot = &mut room.bulbs[b];
            let before = slot.bulb.mode;
            if let Some(cmd) = slot.bulb.step(input, now) {
                commands.insert(b, cmd);
            }
            if slot.bulb.mode != before {
                eprintln!(
                    "{}/{}: {before:?} -> {:?}",
                    room.name, slot.name, slot.bulb.mode
                );
            }
        }

        let first = commands.values().next().copied();
        let all_same =
            commands.len() == room.bulbs.len() && commands.values().all(|c| Some(*c) == first);
        // One payload must suit every member: a group mixing bulbs and plugs
        // would get a plug's state-only payload and leave the bulbs at
        // whatever brightness they had, so those rooms address each device.
        let dimmable = room.bulbs.iter().all(|s| s.dimmable);
        let uniform = dimmable || room.bulbs.iter().all(|s| !s.dimmable);
        match (&room.group, first) {
            (Some(group), Some(cmd)) if all_same && uniform && room.bulbs.len() > 1 => {
                out.push(set(group, cmd, dimmable));
            }
            _ => out.extend(commands.iter().map(|(&b, &cmd)| {
                let slot = &room.bulbs[b];
                set(&slot.device, cmd, slot.dimmable)
            })),
        }

        let mut changed = Vec::new();
        for (b, slot) in room.bulbs.iter_mut().enumerate() {
            if let Some(state) = publish_state(&room.name, slot) {
                out.push(state);
                changed.push(b);
            }
        }
        changed
    }

    /// Resolve bulb names to indices. Scripts can only name their own bulbs.
    fn named(&self, r: usize, reqs: Vec<(String, Input)>) -> Vec<(usize, Input)> {
        let bulbs = &self.rooms[r].bulbs;
        reqs.into_iter()
            .filter_map(|(name, input)| Some((bulbs.iter().position(|s| s.name == name)?, input)))
            .collect()
    }
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

fn wall_now() -> DateTime<FixedOffset> {
    Local::now().fixed_offset()
}

fn load(path: &str) -> Result<Config> {
    let text = std::fs::read_to_string(path).with_context(|| format!("reading {path:?}"))?;
    serde_json::from_str(&text).with_context(|| format!("parsing {path:?}"))
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let [flag, path] = &args[..] {
        if flag == "--check" {
            let house = House::new(load(path)?, Instant::now(), wall_now())?;
            println!("{path}: {} rooms ok", house.rooms.len());
            return Ok(());
        }
    }
    if !args.is_empty() {
        bail!("usage: lights [--check CONFIG]  (otherwise CONFIG comes from $CONFIG)");
    }

    let rt = Runtime::from_env("lights").await?;
    let mut house = House::new(load(&rt.env_or("CONFIG", ""))?, Instant::now(), wall_now())?;
    let mut msgs = rt.subscribe_many(house.topics()).await?;
    for out in house.startup() {
        send(&rt, out).await;
    }
    eprintln!("lights started: {} rooms", house.rooms.len());

    // Ticks once straight away, so scripts' top-level requests go out.
    let mut wake_at = Instant::now();
    loop {
        let outs = tokio::select! {
            Some(msg) = msgs.recv() => house.handle(&msg, Instant::now(), wall_now()),
            () = tokio::time::sleep_until(wake_at.into()) => house.tick(Instant::now(), wall_now()),
            () = rt.shutdown_signal() => break,
        };
        for out in outs {
            send(&rt, out).await;
        }
        // Scripts keep their own `every()` timers, so a deadline always
        // exists in practice; the fallback only bounds a script without one.
        let now = Instant::now();
        wake_at = house
            .deadline()
            .unwrap_or(now + IDLE_TICK)
            .clamp(now, now + IDLE_TICK);
    }
    Ok(())
}

const IDLE_TICK: Duration = Duration::from_secs(60);

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

    const NOON: &str = "2026-06-21T13:10:00+02:00";

    struct Rig {
        house: House,
        now: Instant,
        wall: DateTime<FixedOffset>,
    }

    impl Rig {
        fn new(rooms: Value) -> Self {
            Self::try_new(rooms).unwrap()
        }

        fn try_new(rooms: Value) -> Result<Self> {
            let now = Instant::now();
            let wall = DateTime::parse_from_rfc3339(NOON).unwrap();
            Ok(Self {
                house: House::new(config(rooms)?, now, wall)?,
                now,
                wall,
            })
        }

        fn send(&mut self, topic: &str, payload: Value) -> Vec<Out> {
            let msg = Message {
                topic: topic.into(),
                payload,
            };
            self.house.handle(&msg, self.now, self.wall)
        }

        fn wait(&mut self, d: Duration) -> Vec<Out> {
            self.now += d;
            self.wall += chrono::TimeDelta::from_std(d).unwrap();
            self.house.tick(self.now, self.wall)
        }

        /// Every bulb reports on at `brightness`.
        fn report_all(&mut self, devices: &[&str], payload: Value) {
            for d in devices {
                self.send(&format!("zigbee2mqtt/{d}"), payload.clone());
            }
        }
    }

    fn sets(outs: &[Out]) -> Vec<(&str, &Value)> {
        outs.iter()
            .filter(|o| o.topic.ends_with("/set"))
            .map(|o| (o.topic.as_str(), &o.payload))
            .collect()
    }

    fn state<'a>(outs: &'a [Out], topic: &str) -> Option<&'a Value> {
        outs.iter()
            .rev()
            .find(|o| o.topic == topic)
            .map(|o| &o.payload)
    }

    fn hallway() -> Value {
        json!({ "hallway": {
            "group": "hallway",
            "bulbs": { "a": { "device": "hallway_a" }, "b": { "device": "hallway_b" } },
            "lua": r#"follow{ when = occupancy{ sensors = { "hallway_motion" }, hold = 90 }, fade = 180 }"#,
        } })
    }

    /// Hallway with both bulbs off and adopted.
    fn quiet_hallway() -> Rig {
        let mut rig = Rig::new(hallway());
        rig.report_all(&["hallway_a", "hallway_b"], json!({ "state": "OFF" }));
        rig.wait(Duration::ZERO);
        rig
    }

    #[test]
    fn global_release_hands_every_bulb_back() {
        let mut rig = quiet_hallway();
        rig.send(
            "zigbee2mqtt/hallway_a",
            json!({ "state": "ON", "brightness": 200 }),
        );
        rig.send(
            "zigbee2mqtt/hallway_b",
            json!({ "state": "ON", "brightness": 200 }),
        );
        assert_eq!(rig.house.rooms[0].mode, Some("held"));
        let outs = rig.send("lights/release", json!("release"));
        for b in ["a", "b"] {
            assert_eq!(
                state(&outs, &format!("lights/hallway/{b}/state")).unwrap()["mode"],
                "auto"
            );
        }
        assert_eq!(state(&outs, "lights/hallway/mode"), Some(&json!("auto")));
    }

    #[test]
    fn script_publishes_are_retained_under_the_room() {
        let mut rig = Rig::new(hallway());
        rig.wait(Duration::ZERO);
        let outs = rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        let out = outs
            .iter()
            .find(|o| o.topic == "lights/hallway/occupied")
            .unwrap();
        assert_eq!((&out.payload, out.retain), (&json!(true), true));
    }

    #[test]
    fn startup_adopts_bulbs_from_their_reports() {
        let mut rig = Rig::new(hallway());
        // The main loop ticks once at startup, so rooms state their targets
        // before the first reports come back. The hallway starts vacant.
        rig.wait(Duration::ZERO);
        let outs = rig.send("zigbee2mqtt/hallway_a", json!({ "state": "OFF" }));
        assert_eq!(
            state(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "auto"
        );
        // A light someone left on is not yanked off by a restart.
        let outs = rig.send(
            "zigbee2mqtt/hallway_b",
            json!({ "state": "ON", "brightness": 250 }),
        );
        assert!(sets(&outs).is_empty());
        assert_eq!(
            state(&outs, "lights/hallway/b/state").unwrap()["mode"],
            "held"
        );
    }

    #[test]
    fn motion_turns_the_whole_room_on_as_one_group_command() {
        let mut rig = quiet_hallway();
        let outs = rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        let sets = sets(&outs);
        assert_eq!(sets.len(), 1, "{sets:?}");
        assert_eq!(sets[0].0, "zigbee2mqtt/hallway/set");
        assert_eq!(sets[0].1["state"], "ON");
        assert_eq!(sets[0].1["transition"], 0.4);
    }

    #[test]
    fn app_override_holds_until_the_room_empties() {
        let mut rig = quiet_hallway();
        rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        rig.wait(Duration::from_secs(5));
        let outs = rig.send("zigbee2mqtt/hallway_a", json!({ "state": "OFF" }));
        assert_eq!(
            state(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "held"
        );

        // More motion: only the bulb that isn't held follows the room.
        rig.wait(Duration::from_secs(60));
        rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        assert_eq!(
            rig.house.rooms[0].bulbs[0].bulb.held().map(|t| t.on),
            Some(false)
        );

        // Leaving: hold, then vacant -- released, fading off.
        rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": false }));
        assert!(sets(&rig.wait(Duration::from_secs(89))).is_empty());
        let outs = rig.wait(Duration::from_secs(1));
        assert_eq!(
            state(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "auto"
        );
        rig.report_all(&["hallway_a", "hallway_b"], json!({ "state": "OFF" }));
        rig.wait(Duration::from_secs(181));

        // Next walk-through works normally again, as one group command.
        let outs = rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        assert_eq!(sets(&outs)[0].0, "zigbee2mqtt/hallway/set");
    }

    #[test]
    fn button_press_goes_through_script_and_arbiter() {
        let mut rig = Rig::new(json!({ "bedroom": {
            "bulbs": { "light": { "device": "bedroom_light" } },
            "lua": r#"
                follow{}
                button("bedroom_button", { single = toggle() })
            "#,
        } }));
        rig.send("zigbee2mqtt/bedroom_light", json!({ "state": "OFF" }));
        rig.wait(Duration::from_secs(5));

        let outs = rig.send(
            "zigbee2mqtt/bedroom_button/action",
            json!({ "action": "single" }),
        );
        let sets = sets(&outs);
        assert_eq!(sets[0].0, "zigbee2mqtt/bedroom_light/set");
        assert_eq!(sets[0].1["state"], "ON");
        // A follow room without occupancy keeps a light on once it is on.
        let later = rig.wait(Duration::from_secs(60));
        assert!(later.iter().all(|o| o.payload["state"] != "OFF"));

        // The script saw the new state through the arbiter: next press is off.
        let outs = rig.send("zigbee2mqtt/bedroom_button/action", json!("single"));
        assert_eq!(sets_of(&outs)["state"], "OFF");
    }

    fn sets_of(outs: &[Out]) -> &Value {
        sets(outs)[0].1
    }

    #[test]
    fn ha_release_button_hands_one_bulb_back() {
        let mut rig = quiet_hallway();
        rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        rig.wait(Duration::from_secs(5));
        rig.send("zigbee2mqtt/hallway_a", json!({ "state": "OFF" }));
        let outs = rig.send("lights/hallway/a/release", json!(""));
        assert_eq!(
            state(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "auto"
        );
        assert_eq!(
            sets(&outs),
            vec![("zigbee2mqtt/hallway_a/set", &sets_of(&outs).clone())]
        );
    }

    #[test]
    fn mixed_bulb_and_plug_rooms_never_use_the_group() {
        let mut rig = Rig::new(json!({ "lounge": {
            "group": "lounge",
            "bulbs": {
                "lamp": { "device": "lamp" },
                "plug": { "device": "plug", "dimmable": false },
            },
            "lua": r#"button("btn", { single = toggle() })"#,
        } }));
        rig.report_all(
            &["lamp", "plug"],
            json!({ "state": "ON", "brightness": 254 }),
        );
        let outs = rig.send("zigbee2mqtt/btn/action", json!("single"));
        let topics: Vec<_> = sets(&outs).into_iter().map(|(t, _)| t).collect();
        assert_eq!(topics, ["zigbee2mqtt/lamp/set", "zigbee2mqtt/plug/set"]);
    }

    #[test]
    fn plug_commands_carry_only_state() {
        let cmd = Command {
            target: Target {
                on: true,
                brightness: 254,
                color_temp: Some(300),
            },
            transition: Duration::from_millis(400),
        };
        assert_eq!(
            set("plug", cmd, false).payload,
            json!({ "state": "ON", "transition": 0.4 })
        );
    }

    #[test]
    fn garbage_is_ignored_not_fatal() {
        let mut rig = quiet_hallway();
        for (topic, payload) in [
            ("zigbee2mqtt/hallway_a", json!({ "linkquality": 80 })),
            (
                "zigbee2mqtt/hallway_motion",
                json!({ "occupancy": "maybe" }),
            ),
            ("zigbee2mqtt/hallway_motion", json!(42)),
            ("lights/hallway/nope/release", json!("")),
            ("other/topic", json!({})),
        ] {
            assert!(sets(&rig.send(topic, payload)).is_empty());
        }
    }

    #[test]
    fn config_errors_are_caught_at_startup() {
        let mut ghost = hallway();
        ghost["hallway"]["lua"] = json!("light('ghost')");
        assert!(Rig::try_new(ghost).is_err(), "unknown bulb");

        let mut twice = hallway();
        twice["attic"] = twice["hallway"].clone();
        assert!(Rig::try_new(twice).is_err(), "bulb in two rooms");

        let mut extra = hallway();
        extra["hallway"]["logic"] = json!({});
        assert!(Rig::try_new(extra).is_err(), "unknown field");
    }

    fn config(rooms: Value) -> Result<Config> {
        let cfg = json!({ "latitude": 52.52, "longitude": 13.405, "rooms": rooms });
        Ok(serde_json::from_value(cfg)?)
    }

    /// The cupboard as it will actually be configured: on while the door is
    /// open, off when it closes, at the sun's level.
    fn cupboard() -> Value {
        json!({ "cupboard": {
            "bulbs": { "bulb": { "device": "cupboard_bulb" } },
            "lua": r#"
                local bulb = light("bulb")
                local open = false
                local function update()
                  bulb:auto{
                    on = open,
                    brightness = sun.level{ min = 30 },
                    color_temp = sun.ct{},
                    transition = open and 0.4 or 1,
                  }
                end
                on("cupboard_door", function(p)
                  if p.contact == nil then return end
                  open = not p.contact
                  -- Shut means done: forget any manual change.
                  if not open then bulb:release{ transition = 1 } end
                  update()
                end)
                every(30, update)
                update()
            "#,
        } })
    }

    #[test]
    fn cupboard_is_on_while_the_door_is_open() {
        let mut rig = Rig::new(cupboard());
        rig.send("zigbee2mqtt/cupboard_bulb", json!({ "state": "OFF" }));
        rig.wait(Duration::ZERO);

        let outs = rig.send("zigbee2mqtt/cupboard_door", json!({ "contact": false }));
        let on = sets_of(&outs);
        assert_eq!(
            (&on["state"], &on["transition"]),
            (&json!("ON"), &json!(0.4))
        );
        assert!(on["color_temp"].is_number());

        // Left open for an hour: still on, following the sun.
        let outs = rig.wait(Duration::from_secs(3600));
        assert!(sets(&outs).iter().all(|(_, p)| p["state"] == "ON"));

        let outs = rig.send("zigbee2mqtt/cupboard_door", json!({ "contact": true }));
        assert_eq!(sets_of(&outs)["state"], "OFF");

        // Battery reports carry no `contact`: ignored.
        assert!(sets(&rig.send("zigbee2mqtt/cupboard_door", json!({ "battery": 80 }))).is_empty());
    }

    #[test]
    fn cupboard_manual_change_lasts_until_the_door_shuts() {
        let mut rig = Rig::new(cupboard());
        rig.send("zigbee2mqtt/cupboard_bulb", json!({ "state": "OFF" }));
        rig.wait(Duration::ZERO);
        rig.send("zigbee2mqtt/cupboard_door", json!({ "contact": false }));
        rig.wait(Duration::from_secs(5));

        let outs = rig.send(
            "zigbee2mqtt/cupboard_bulb",
            json!({ "state": "ON", "brightness": 20 }),
        );
        assert_eq!(
            state(&outs, "lights/cupboard/bulb/state").unwrap()["mode"],
            "held"
        );
        assert!(
            sets(&rig.wait(Duration::from_secs(60))).is_empty(),
            "held at 20"
        );

        let outs = rig.send("zigbee2mqtt/cupboard_door", json!({ "contact": true }));
        assert_eq!(sets_of(&outs)["state"], "OFF");
        assert_eq!(
            state(&outs, "lights/cupboard/bulb/state").unwrap()["mode"],
            "auto"
        );
    }

    #[test]
    fn startup_asks_every_bulb_for_its_state() {
        let rig = Rig::new(hallway());
        let topics: Vec<_> = rig.house.startup().into_iter().map(|o| o.topic).collect();
        assert_eq!(
            topics,
            ["zigbee2mqtt/hallway_a/get", "zigbee2mqtt/hallway_b/get"]
        );
    }
}
