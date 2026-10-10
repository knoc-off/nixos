//! Every light in the house, in one process: each room's logic decides what
//! the room wants (`mqtt_automations::room`), and the arbiter decides, per
//! bulb, whether the bulb listens (`mqtt_automations::arbiter`) -- the
//! automation, or a person who changed it by button, HA or app.
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
//!
//! Config: a JSON file at `$CONFIG`, see [`Config`].

use std::collections::{BTreeMap, HashMap, VecDeque};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use chrono::{DateTime, FixedOffset, Local};
use mqtt_automations::arbiter::{self, Bulb, Command, Input, Mode, Target};
use mqtt_automations::room::{self, Event, Request};
use mqtt_automations::script::Script;
use mqtt_automations::{Message, Runtime};
use serde::Deserialize;
use serde_json::{json, Value};

/// How often the rooms re-evaluate the sun curves.
const CURVE_TICK: Duration = Duration::from_secs(30);
/// Room -> arbiter -> room rounds per event. Rooms only republish what
/// changed, so this settles in one or two; the cap is a backstop against a
/// logic bug turning into a hot loop.
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
    /// Built-in room logic (the `room` module), or ...
    #[serde(default)]
    logic: Option<room::Config>,
    /// ... a Lua script (the `script` module). Exactly one of the two.
    #[serde(default)]
    lua: Option<String>,
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
    Sensor(usize),
    Button(usize),
    Script(usize),
}

struct BulbSlot {
    name: String,
    device: String,
    dimmable: bool,
    bulb: Bulb,
    published: Option<Value>,
}

/// What decides a room's wishes. Both speak per-bulb arbiter inputs.
enum Logic {
    Builtin(Box<room::Room>),
    Lua(Script),
}

impl Logic {
    fn deadline(&self) -> Option<Instant> {
        match self {
            Self::Builtin(r) => r.deadline(),
            Self::Lua(s) => s.deadline(),
        }
    }
}

struct Room {
    name: String,
    group: Option<String>,
    bulbs: Vec<BulbSlot>,
    logic: Logic,
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
            let logic = match (room.logic, room.lua) {
                (Some(mut logic), None) => {
                    if let Some(light) = logic.lights.keys().find(|l| !room.bulbs.contains_key(*l))
                    {
                        bail!("room {name}: logic names unknown bulb {light:?}");
                    }
                    (logic.latitude, logic.longitude) = (cfg.latitude, cfg.longitude);
                    for device in logic.sensors() {
                        route(format!("zigbee2mqtt/{device}"), Route::Sensor(r));
                    }
                    for device in logic.buttons() {
                        route(format!("zigbee2mqtt/{device}/action"), Route::Button(r));
                    }
                    let logic =
                        room::Room::new(logic, now).with_context(|| format!("room {name}"))?;
                    Logic::Builtin(Box::new(logic))
                }
                (None, Some(source)) => {
                    let lights = room
                        .bulbs
                        .iter()
                        .map(|(n, b)| (n.clone(), b.device.clone()));
                    let script = Script::new(
                        &name,
                        &source,
                        lights,
                        (cfg.latitude, cfg.longitude),
                        now,
                        wall,
                    )?;
                    for topic in script.topics() {
                        route(topic, Route::Script(r));
                    }
                    Logic::Lua(script)
                }
                _ => bail!("room {name}: needs exactly one of `logic` and `lua`"),
            };
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
                logic,
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

    /// The next moment anything changes by itself (not counting the curve
    /// tick, which the caller adds).
    fn deadline(&self) -> Option<Instant> {
        self.rooms
            .iter()
            .flat_map(|room| {
                let bulbs = room.bulbs.iter().filter_map(|s| s.bulb.deadline());
                bulbs.chain(room.logic.deadline())
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
                    Some(report) => self.step_bulbs(r, vec![(b, Input::Report(report))], now, wall),
                    None => Vec::new(),
                },
                Route::BulbRelease(r, b) => {
                    let release = Input::Release {
                        transition: Duration::ZERO,
                    };
                    self.step_bulbs(r, vec![(b, release)], now, wall)
                }
                Route::Sensor(r) => {
                    let device = device_of(&msg.topic);
                    sensor_events(device, &msg.payload)
                        .into_iter()
                        .flat_map(|e| self.step_room(r, e, now, wall))
                        .collect()
                }
                Route::Button(r) => match action_of(&msg.payload) {
                    Some(action) => {
                        let device = device_of(msg.topic.trim_end_matches("/action")).to_owned();
                        self.step_room(r, Event::Action { device, action }, now, wall)
                    }
                    None => Vec::new(),
                },
                Route::Script(r) => {
                    let inputs = match &mut self.rooms[r].logic {
                        Logic::Lua(s) => s.message(&msg.topic, &msg.payload, now, wall),
                        Logic::Builtin(_) => Vec::new(),
                    };
                    let inputs = self.named(r, inputs);
                    self.step_bulbs(r, inputs, now, wall)
                }
            });
        }
        out
    }

    /// Timers and curves: every room and every due bulb.
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
            out.extend(self.step_bulbs(r, due, now, wall));
            out.extend(self.step_room(r, Event::Tick, now, wall));
        }
        out
    }

    /// Feed one event to a room's logic, then its requests to the bulbs.
    fn step_room(
        &mut self,
        r: usize,
        event: Event,
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Vec<Out> {
        let inputs = match &mut self.rooms[r].logic {
            Logic::Builtin(logic) => by_name(logic.step(event, now, wall)),
            Logic::Lua(script) => match event {
                Event::Tick => script.tick(now, wall),
                // Lua rooms get sensor and button messages raw, through
                // their own subscriptions.
                _ => Vec::new(),
            },
        };
        let inputs = self.named(r, inputs);
        self.step_bulbs(r, inputs, now, wall)
    }

    /// Feed inputs to the bulbs as one batch, so a room-wide change can go
    /// out as a single group command. Bulb changes flow back to the room's
    /// logic, whose answers are fed in the same way until it is quiet.
    fn step_bulbs(
        &mut self,
        r: usize,
        inputs: Vec<(usize, Input)>,
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Vec<Out> {
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
                answers.extend(match &mut room.logic {
                    Logic::Builtin(logic) => {
                        let event = Event::Bulb {
                            light: slot.name.clone(),
                            held,
                            state,
                        };
                        by_name(logic.step(event, now, wall))
                    }
                    Logic::Lua(script) => script.bulb(&slot.name, held, state),
                });
            }
            let next = self.named(r, answers);
            if !next.is_empty() {
                queue.push_back(next);
            }
        }
        eprintln!("{}: room and arbiter did not settle", self.rooms[r].name);
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
        // A mixed room (bulbs and plugs) never matches as all-same in
        // practice, but a group of only plugs must still send plug payloads.
        let dimmable = room.bulbs.iter().all(|s| s.dimmable);
        match (&room.group, first) {
            (Some(group), Some(cmd)) if all_same && room.bulbs.len() > 1 => {
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

    /// Resolve bulb names to indices; `ALL` means every bulb in the room.
    fn named(&self, r: usize, reqs: Vec<(String, Input)>) -> Vec<(usize, Input)> {
        let bulbs = &self.rooms[r].bulbs;
        let mut inputs = Vec::new();
        for (name, input) in reqs {
            if name == ALL {
                inputs.extend((0..bulbs.len()).map(|b| (b, input)));
            } else if let Some(b) = bulbs.iter().position(|s| s.name == name) {
                inputs.push((b, input));
            }
        }
        inputs
    }
}

/// Bulb name standing for every bulb in the room.
const ALL: &str = "*";

/// The built-in logic's requests as per-bulb arbiter inputs.
fn by_name(outs: Vec<room::Out>) -> Vec<(String, Input)> {
    let mut reqs = Vec::new();
    for o in outs {
        match o {
            room::Out::Auto(Request {
                bulbs,
                scale,
                transition,
            }) => {
                let transition = secs(transition);
                reqs.extend(bulbs.into_iter().map(|(name, target)| {
                    let input = Input::Auto {
                        target,
                        scale,
                        transition,
                    };
                    (name, input)
                }));
            }
            room::Out::User(Request {
                bulbs, transition, ..
            }) => {
                let transition = secs(transition);
                reqs.extend(
                    bulbs
                        .into_iter()
                        .map(|(name, target)| (name, Input::User { target, transition })),
                );
            }
            room::Out::Release { transition } => {
                let transition = secs(transition);
                reqs.push((ALL.to_owned(), Input::Release { transition }));
            }
        }
    }
    reqs
}

/// A NaN or negative duration must not panic the process that owns every
/// light.
fn secs(s: f32) -> Duration {
    Duration::try_from_secs_f32(s).unwrap_or_default()
}

/// `zigbee2mqtt/<device>` -> `<device>`.
fn device_of(topic: &str) -> &str {
    topic.strip_prefix("zigbee2mqtt/").unwrap_or(topic)
}

/// What a z2m sensor message says, in room terms. One message can carry
/// several fields; a field that is absent says nothing.
fn sensor_events(device: &str, payload: &Value) -> Vec<Event> {
    let flag = |key| payload.get(key).and_then(Value::as_bool);
    let mut events = Vec::new();
    // SNZB-03P/06P report `occupancy`; the older kitchen sensor `presence`.
    if let Some(active) = flag("occupancy").or_else(|| flag("presence")) {
        events.push(Event::Sensor {
            device: device.to_owned(),
            active,
        });
    }
    // z2m's contact sensors report `contact: true` when closed.
    if let Some(contact) = flag("contact") {
        events.push(Event::Door {
            device: device.to_owned(),
            open: !contact,
        });
    }
    events
}

fn action_of(payload: &Value) -> Option<String> {
    let action = match payload {
        Value::String(s) => s.as_str(),
        Value::Object(m) => m.get("action")?.as_str()?,
        _ => return None,
    };
    (!action.is_empty()).then(|| action.to_owned())
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

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<()> {
    let rt = Runtime::from_env("lights").await?;
    let path = rt.env_or("CONFIG", "");
    let cfg: Config = serde_json::from_str(
        &std::fs::read_to_string(&path).with_context(|| format!("reading CONFIG {path:?}"))?,
    )
    .context("parsing CONFIG")?;

    let mut house = House::new(cfg, Instant::now(), wall_now())?;
    let mut msgs = rt.subscribe_many(house.topics()).await?;
    for out in house.startup() {
        send(&rt, out).await;
    }
    eprintln!("lights started: {} rooms", house.rooms.len());

    let mut next_curve = Instant::now();
    loop {
        let wake_at = house.deadline().map_or(next_curve, |d| d.min(next_curve));
        let outs = tokio::select! {
            Some(msg) = msgs.recv() => house.handle(&msg, Instant::now(), wall_now()),
            () = tokio::time::sleep_until(wake_at.into()) => {
                let now = Instant::now();
                if now >= next_curve {
                    next_curve = now + CURVE_TICK;
                }
                house.tick(now, wall_now())
            }
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

    const NOON: &str = "2026-06-21T13:10:00+02:00";
    /// The rooms' restart grace (`room::Config::interaction_hold`) plus slack.
    const GRACE: Duration = Duration::from_secs(301);

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
                house: House::new(config(rooms), now, wall)?,
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
            "logic": {
                "latitude": 52.52, "longitude": 13.405,
                "sources": [{ "type": "motion", "device": "hallway_motion", "hold": 90 }],
                "fade": 180,
                "lights": { "a": { "turnOn": true }, "b": { "turnOn": true } },
            },
        } })
    }

    /// Hallway with both bulbs off and adopted, past the restart grace.
    fn quiet_hallway() -> Rig {
        let mut rig = Rig::new(hallway());
        rig.report_all(&["hallway_a", "hallway_b"], json!({ "state": "OFF" }));
        rig.wait(GRACE);
        rig.wait(Duration::from_secs(181));
        rig
    }

    #[test]
    fn startup_adopts_bulbs_from_their_reports() {
        let mut rig = Rig::new(hallway());
        // The main loop ticks once at startup, so rooms state their targets
        // before the first reports come back.
        rig.wait(Duration::ZERO);
        let outs = rig.send(
            "zigbee2mqtt/hallway_a",
            json!({ "state": "ON", "brightness": 250 }),
        );
        assert_eq!(
            state(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "auto"
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

        // Hold, fade, vacant: released.
        rig.wait(Duration::from_secs(91));
        let outs = rig.wait(Duration::from_secs(181));
        assert_eq!(
            state(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "auto"
        );

        // Next walk-through works normally again, as one group command.
        let outs = rig.send("zigbee2mqtt/hallway_motion", json!({ "occupancy": true }));
        assert_eq!(sets(&outs)[0].0, "zigbee2mqtt/hallway/set");
    }

    #[test]
    fn button_press_goes_through_room_and_arbiter() {
        let mut rig = Rig::new(json!({ "bedroom": {
            "bulbs": { "light": { "device": "bedroom_light" } },
            "logic": {
                "latitude": 52.52, "longitude": 13.405,
                "lights": { "light": {} },
                "controls": { "bedroom_button": { "single": { "action": "dimThenOff", "level": 10 } } },
            },
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
        // On at the curve's own level, so there is nothing to hold: the
        // arbiter hands it straight back to auto, and the room keeps it on
        // because it knows a person switched it on.
        let shown = state(&outs, "lights/bedroom/light/state").unwrap();
        assert_eq!(
            (&shown["mode"], &shown["on"]),
            (&json!("auto"), &json!(true))
        );
        let later = rig.wait(Duration::from_secs(60));
        assert!(later.iter().all(|o| o.payload["state"] != "OFF"));

        // The room saw the new state through the arbiter: next press dims.
        let outs = rig.send("zigbee2mqtt/bedroom_button/action", json!("single"));
        assert_eq!(sets_of(&outs)["brightness"], 25);
        assert_eq!(
            state(&outs, "lights/bedroom/light/state").unwrap()["mode"],
            "held"
        );
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
    fn door_contact_opens_and_closes() {
        let events = sensor_events("door", &json!({ "contact": false, "battery": 90 }));
        assert!(matches!(&events[..], [Event::Door { open: true, .. }]));
        assert!(sensor_events("door", &json!({ "battery": 90 })).is_empty());
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
        let mut bad = hallway();
        bad["hallway"]["logic"]["lights"]["ghost"] = json!({});
        assert!(Rig::try_new(bad).is_err());

        let mut twice = hallway();
        twice["attic"] = twice["hallway"].clone();
        assert!(Rig::try_new(twice).is_err(), "bulb in two rooms");

        let mut both = hallway();
        both["hallway"]["lua"] = json!("");
        assert!(Rig::try_new(both).is_err(), "logic and lua");

        let broken = json!({ "cupboard": {
            "bulbs": { "bulb": { "device": "cupboard_bulb" } },
            "lua": "light('nope')",
        } });
        assert!(Rig::try_new(broken).is_err(), "script fails to load");
    }

    fn config(rooms: Value) -> Config {
        let cfg = json!({ "latitude": 52.52, "longitude": 13.405, "rooms": rooms });
        serde_json::from_value(cfg).unwrap()
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
