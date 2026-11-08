//! Every light in the house, in one process. Each room is a state machine
//! declared in Lua and run by `mqtt_automations::room`; this file only
//! routes MQTT to rooms and turns their commands into z2m messages.
//!
//! This is the only writer to z2m light and plug `/set` topics. A room-wide
//! identical change goes out as one group command, so bulbs don't pop on
//! one after another.
//!
//! MQTT surface, besides z2m:
//!   - `lights/<room>/state` (retained, from here): the current state.
//!   - `lights/<room>/mode` (retained, from here): the current mode -- the
//!     state, or while in a hidden one, the mode the room will resume.
//!   - `lights/<room>/mode/set` (to here): pick a mode. The HA select for it
//!     is published here by discovery, with the room's modes as options.
//!   - `lights/<room>/occupied` (retained, from here), for rooms with
//!     presence sensors.
//!   - `lights/<room>/release` (to here): reset the room as if just started:
//!     holds and memory dropped, start state, sensors replayed.
//!     `lights/release`: every room, and the house back to its first mode.
//!   - `lights/<room>/<bulb>/state` (retained, from here):
//!     `{ "mode": "auto"|"held"|"unknown", "on", "brightness", "color_temp" }`.
//!   - `lights/<room>/<bulb>/release` (to here): hand one bulb back.
//!   - `lights/house` (retained, from here): the house mode (one of the
//!     config's `house_modes`) some room last announced (`announce` rows);
//!     read back once at startup to restore it. `lights/house/set` (to
//!     here): set it from HA, whose select is announced by discovery like
//!     the rooms'.
//!   - Whatever settings topics the room files read.
//!
//! Config: a JSON file, see [`Config`]. `lights --check <file>` loads it and
//! every room without connecting, for build-time validation.

use std::collections::{BTreeMap, HashMap};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use chrono::{DateTime, FixedOffset, Local};
use mqtt_automations::arbiter::{Command, Mode, Target};
use mqtt_automations::room::{Event, Room};
use mqtt_automations::{Message, Runtime};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Config {
    latitude: f64,
    longitude: f64,
    /// The house modes rooms may announce and react to; the first is what
    /// resetting every room returns the house to.
    #[serde(default)]
    house_modes: Vec<String>,
    rooms: BTreeMap<String, RoomConfig>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RoomConfig {
    /// Shown in HA ("<label> mode"); defaults to the room's name.
    #[serde(default)]
    label: Option<String>,
    /// z2m group containing exactly this room's bulbs, if there is one.
    #[serde(default)]
    group: Option<String>,
    bulbs: BTreeMap<String, BulbConfig>,
    /// The room's Lua file; see `prelude.lua` for the format.
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

#[derive(Clone, Debug)]
enum Route {
    Report(usize, usize),
    Presence(usize),
    Door(usize, String),
    Button(usize, String),
    Setting(usize),
    Select(usize),
    Release(usize, usize),
    Reset(usize),
    ResetAll,
    /// HA picked a house mode.
    HouseSet,
    /// Our own retained `lights/house`, read back once to restore it.
    HouseRestore,
}

struct Slot {
    room: Room,
    label: String,
    group: Option<String>,
    /// Last `lights/<room>/<bulb>/state` sent, per bulb.
    shown: Vec<Option<Value>>,
}

/// All routing and z2m formatting, without MQTT -- so it can be tested.
struct House {
    rooms: Vec<Slot>,
    /// One topic can feed several rooms (a shared setting or sensor).
    routes: HashMap<String, Vec<Route>>,
    /// The house mode, once announced or restored.
    house: Option<String>,
    /// From the config; every one a room uses is among them.
    house_modes: Vec<String>,
}

impl House {
    fn new(cfg: Config, now: Instant, wall: DateTime<FixedOffset>) -> Result<Self> {
        let mut routes: HashMap<String, Vec<Route>> = HashMap::new();
        let mut route = |topic: String, to: Route| routes.entry(topic).or_default().push(to);
        route("lights/release".into(), Route::ResetAll);
        route("lights/house/set".into(), Route::HouseSet);
        route("lights/house".into(), Route::HouseRestore);
        let mut rooms = Vec::new();
        for (r, (name, rc)) in cfg.rooms.into_iter().enumerate() {
            let bulbs = rc
                .bulbs
                .into_iter()
                .map(|(n, b)| (n, b.device, b.dimmable))
                .collect();
            let room = Room::new(
                &name,
                &rc.lua,
                bulbs,
                (cfg.latitude, cfg.longitude),
                now,
                wall,
            )?;
            for (b, l) in room.bulbs.iter().enumerate() {
                route(format!("zigbee2mqtt/{}", l.device), Route::Report(r, b));
                route(
                    format!("lights/{name}/{}/release", l.name),
                    Route::Release(r, b),
                );
            }
            let spec = room.spec();
            for device in &spec.presence {
                route(format!("zigbee2mqtt/{device}"), Route::Presence(r));
            }
            for (door, device) in &spec.doors {
                route(
                    format!("zigbee2mqtt/{device}"),
                    Route::Door(r, door.clone()),
                );
            }
            for (button, device) in &spec.buttons {
                route(
                    format!("zigbee2mqtt/{device}/action"),
                    Route::Button(r, button.clone()),
                );
            }
            for topic in room.setting_topics() {
                route(topic, Route::Setting(r));
            }
            route(format!("lights/{name}/mode/set"), Route::Select(r));
            route(format!("lights/{name}/release"), Route::Reset(r));
            rooms.push(Slot {
                shown: vec![None; room.bulbs.len()],
                label: rc.label.unwrap_or_else(|| name.clone()),
                group: rc.group,
                room,
            });
        }
        let mut seen = HashMap::new();
        for slot in &rooms {
            for l in &slot.room.bulbs {
                if let Some(other) = seen.insert(&l.device, &slot.room.name) {
                    bail!(
                        "bulb {} is in both {other} and {}",
                        l.device,
                        slot.room.name
                    );
                }
            }
        }
        for slot in &rooms {
            if let Some(m) = slot
                .room
                .house_modes()
                .into_iter()
                .find(|m| !cfg.house_modes.iter().any(|h| h == m))
            {
                bail!("room {}: no house mode {m:?} (houseModes)", slot.room.name);
            }
        }
        Ok(Self {
            rooms,
            routes,
            house: None,
            house_modes: cfg.house_modes,
        })
    }

    fn topics(&self) -> Vec<String> {
        self.routes.keys().cloned().collect()
    }

    /// Ask every bulb for its state, so startup can adopt it, and announce
    /// each room's mode select to HA.
    fn startup(&self) -> Vec<Out> {
        let gets = self.rooms.iter().flat_map(|s| &s.room.bulbs).map(|l| Out {
            topic: format!("zigbee2mqtt/{}/get", l.device),
            payload: json!({ "state": "" }),
            retain: false,
        });
        let selects = self.rooms.iter().map(|s| {
            let name = &s.room.name;
            Out {
                topic: format!("homeassistant/select/lights_{name}_mode/config"),
                payload: json!({
                    "unique_id": format!("lights_{name}_mode_select"),
                    "name": format!("{} mode", s.label),
                    "icon": "mdi:home-lightbulb-outline",
                    "command_topic": format!("lights/{name}/mode/set"),
                    "state_topic": format!("lights/{name}/mode"),
                    "value_template": "{{ value_json }}",
                    "options": s.room.modes(),
                }),
                retain: true,
            }
        });
        let house = (!self.house_modes.is_empty()).then(|| Out {
            topic: "homeassistant/select/lights_house_mode/config".into(),
            payload: json!({
                "unique_id": "lights_house_mode_select",
                "name": "House mode",
                "icon": "mdi:home-clock-outline",
                "command_topic": "lights/house/set",
                "state_topic": "lights/house",
                "value_template": "{{ value_json }}",
                "options": self.house_modes,
            }),
            retain: true,
        });
        gets.chain(selects).chain(house).collect()
    }

    /// The next moment anything changes by itself.
    fn deadline(&self) -> Option<Instant> {
        self.rooms.iter().map(|s| s.room.deadline()).min()
    }

    fn handle(&mut self, msg: &Message, now: Instant, wall: DateTime<FixedOffset>) -> Vec<Out> {
        let Some(routes) = self.routes.get(&msg.topic).cloned() else {
            return Vec::new();
        };
        let p = &msg.payload;
        let mut out = Vec::new();
        for route in routes {
            let (r, event) = match &route {
                Route::Report(r, b) => match parse_report(p) {
                    Some(target) => (*r, Event::Report { bulb: *b, target }),
                    None => continue,
                },
                Route::Presence(r) => {
                    let v = p.get("occupancy").or_else(|| p.get("presence"));
                    let Some(present) = v.and_then(Value::as_bool) else {
                        continue;
                    };
                    let device = msg.topic.trim_start_matches("zigbee2mqtt/");
                    (*r, Event::Presence { device, present })
                }
                // z2m: `contact = true` is closed.
                Route::Door(r, name) => match p.get("contact").and_then(Value::as_bool) {
                    Some(closed) => (
                        *r,
                        Event::Door {
                            name,
                            open: !closed,
                        },
                    ),
                    None => continue,
                },
                Route::Button(r, name) => {
                    match p
                        .get("action")
                        .unwrap_or(p)
                        .as_str()
                        .filter(|a| !a.is_empty())
                    {
                        Some(action) => (*r, Event::Button { name, action }),
                        None => continue,
                    }
                }
                Route::Setting(r) => (
                    *r,
                    Event::Setting {
                        topic: &msg.topic,
                        payload: p,
                    },
                ),
                Route::Select(r) => match p.as_str() {
                    Some(mode) => (*r, Event::Select(mode)),
                    None => continue,
                },
                Route::Release(r, b) => (*r, Event::Release(*b)),
                Route::Reset(r) => (*r, Event::Reset),
                Route::ResetAll => {
                    // The house first, so rooms reset straight into it.
                    if let Some(mode) = self.house_modes.first().cloned() {
                        out.extend(self.broadcast(mode, now, wall));
                    }
                    for r in 0..self.rooms.len() {
                        out.extend(self.step(r, Event::Reset, now, wall));
                    }
                    continue;
                }
                Route::HouseSet | Route::HouseRestore => {
                    let restore = matches!(route, Route::HouseRestore);
                    // After the first, `lights/house` is only our own echo.
                    if restore && self.house.is_some() {
                        continue;
                    }
                    match p
                        .as_str()
                        .filter(|m| self.house_modes.iter().any(|h| h == m))
                    {
                        Some(mode) => out.extend(self.broadcast(mode.to_owned(), now, wall)),
                        None => eprintln!("house: no mode {p}"),
                    }
                    continue;
                }
            };
            out.extend(self.step(r, event, now, wall));
        }
        out
    }

    /// Every room that is due.
    fn tick(&mut self, now: Instant, wall: DateTime<FixedOffset>) -> Vec<Out> {
        let mut out = Vec::new();
        for r in 0..self.rooms.len() {
            if self.rooms[r].room.deadline() <= now {
                out.extend(self.step(r, Event::Tick, now, wall));
            }
        }
        out
    }

    fn step(
        &mut self,
        r: usize,
        event: Event,
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Vec<Out> {
        let slot = &mut self.rooms[r];
        let outcome = slot.room.step(event, now, wall);
        let mut out = commands(slot, &outcome.commands);
        for (b, l) in slot.room.bulbs.iter().enumerate() {
            let Some(t) = l.bulb.showing() else {
                continue;
            };
            let mode = match l.bulb.mode {
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
            if slot.shown[b].as_ref() != Some(&payload) {
                slot.shown[b] = Some(payload.clone());
                out.push(Out {
                    topic: format!("lights/{}/{}/state", slot.room.name, l.name),
                    payload,
                    retain: true,
                });
            }
        }
        out.extend(outcome.publish.into_iter().map(|(topic, payload)| Out {
            topic,
            payload,
            retain: true,
        }));
        for mode in outcome.announce {
            if matches!(event, Event::House(_)) {
                // One level only: a room answering a house mode with another
                // could ping-pong the house forever.
                eprintln!(
                    "{}: ignoring announce {mode:?} made in reply to the house",
                    self.rooms[r].room.name
                );
                continue;
            }
            out.extend(self.broadcast(mode, now, wall));
        }
        out
    }

    /// Set the house mode and tell every room, the announcing one included.
    fn broadcast(&mut self, mode: String, now: Instant, wall: DateTime<FixedOffset>) -> Vec<Out> {
        eprintln!("house: {mode}");
        let mut out = Vec::new();
        if self.house.as_ref() != Some(&mode) {
            out.push(Out {
                topic: "lights/house".into(),
                payload: json!(mode),
                retain: true,
            });
        }
        self.house = Some(mode.clone());
        for r in 0..self.rooms.len() {
            out.extend(self.step(r, Event::House(&mode), now, wall));
        }
        out
    }
}

/// z2m messages for a step's commands: one group command if every bulb
/// got the same one, else one per device.
fn commands(slot: &Slot, cmds: &BTreeMap<usize, Command>) -> Vec<Out> {
    let bulbs = &slot.room.bulbs;
    let first = cmds.values().next().copied();
    let all_same = cmds.len() == bulbs.len() && cmds.values().all(|c| Some(*c) == first);
    // One payload must suit every member: a group mixing bulbs and plugs
    // would get a plug's state-only payload and leave the bulbs at
    // whatever brightness they had, so those rooms address each device.
    let dimmable = bulbs.iter().all(|l| l.dimmable);
    let uniform = dimmable || bulbs.iter().all(|l| !l.dimmable);
    match (&slot.group, first) {
        (Some(group), Some(cmd)) if all_same && uniform && bulbs.len() > 1 => {
            vec![set(group, cmd, dimmable)]
        }
        _ => cmds
            .iter()
            .map(|(&b, &cmd)| set(&bulbs[b].device, cmd, bulbs[b].dimmable))
            .collect(),
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

fn wall_now() -> DateTime<FixedOffset> {
    Local::now().fixed_offset()
}

fn load(path: &str) -> Result<Config> {
    let text = std::fs::read_to_string(path).with_context(|| format!("reading {path:?}"))?;
    serde_json::from_str(&text).with_context(|| format!("parsing {path:?}"))
}

const IDLE_TICK: Duration = Duration::from_secs(60);

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

    // Rooms start due, so their looks go out straight away.
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
        let now = Instant::now();
        wake_at = house
            .deadline()
            .unwrap_or(now + IDLE_TICK)
            .clamp(now, now + IDLE_TICK);
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

    /// A Sunday, 13:10 local.
    const NOON: &str = "2026-06-21T13:10:00+02:00";

    struct Rig {
        house: House,
        now: Instant,
        wall: DateTime<FixedOffset>,
    }

    /// As in systems/rpi-4b-plus/services/lighting/default.nix.
    const HOUSE_MODES: [&str; 3] = ["day", "bright", "night"];

    impl Rig {
        fn new(rooms: Value) -> Self {
            Self::at(rooms, NOON)
        }

        fn at(rooms: Value, wall: &str) -> Self {
            let cfg = json!({
                "latitude": 52.52, "longitude": 13.405,
                "house_modes": HOUSE_MODES, "rooms": rooms,
            });
            let now = Instant::now();
            let wall = DateTime::parse_from_rfc3339(wall).unwrap();
            let mut rig = Self {
                house: House::new(serde_json::from_value(cfg).unwrap(), now, wall).unwrap(),
                now,
                wall,
            };
            rig.wait(Duration::ZERO);
            rig
        }

        fn send(&mut self, topic: &str, payload: Value) -> Vec<Out> {
            let msg = Message {
                topic: topic.into(),
                payload,
            };
            self.house.handle(&msg, self.now, self.wall)
        }

        /// Advance the clock, ticking at every deadline on the way.
        fn wait(&mut self, d: Duration) -> Vec<Out> {
            let end = self.now + d;
            let mut out = Vec::new();
            loop {
                let next = self.house.deadline().unwrap_or(end).max(self.now).min(end);
                let step = next - self.now;
                self.now = next;
                self.wall += chrono::TimeDelta::from_std(step).unwrap();
                out.extend(self.house.tick(self.now, self.wall));
                if self.now >= end {
                    return out;
                }
            }
        }

        fn mins(&mut self, m: u64) -> Vec<Out> {
            self.wait(Duration::from_secs(m * 60))
        }

        /// Every bulb reports `payload`, then settles.
        fn report_all(&mut self, devices: &[&str], payload: Value) {
            for d in devices {
                self.send(&format!("zigbee2mqtt/{d}"), payload.clone());
            }
            self.wait(Duration::from_secs(5));
        }

        fn presence(&mut self, sensor: &str, present: bool) -> Vec<Out> {
            self.send(
                &format!("zigbee2mqtt/{sensor}"),
                json!({ "occupancy": present }),
            )
        }

        fn state(&self, room: usize) -> &str {
            self.house.rooms[room].room.state_name()
        }
    }

    fn sets(outs: &[Out]) -> Vec<(&str, &Value)> {
        outs.iter()
            .filter(|o| o.topic.ends_with("/set"))
            .map(|o| (o.topic.as_str(), &o.payload))
            .collect()
    }

    fn last<'a>(outs: &'a [Out], topic: &str) -> Option<&'a Value> {
        outs.iter()
            .rev()
            .find(|o| o.topic == topic)
            .map(|o| &o.payload)
    }

    const HALLWAY: &str = r#"
        room{
          presence = { "motion" },
          buttons = { button = "button" },
          default = "auto",
          start = "off",
          states = {
            off = { hidden = true, look = { on = false, transition = 30 }, on = { present = "resume" } },
            auto = {
              look = { brightness = 200 },
              on = { ["button.single"] = { toggle = { "a" } } },
              when = { { to = "off", absent_for = 60 } },
            },
            dim = { extends = "auto", look = { brightness = 76 } },
          },
        }"#;

    fn hallway() -> Rig {
        let mut rig = Rig::new(json!({ "hallway": {
            "label": "Hallway",
            "group": "hallway",
            "bulbs": { "a": { "device": "hallway_a" }, "b": { "device": "hallway_b" } },
            "lua": HALLWAY,
        } }));
        rig.report_all(&["hallway_a", "hallway_b"], json!({ "state": "OFF" }));
        rig
    }

    #[test]
    fn startup_adopts_and_announces_the_mode_select() {
        let rig = hallway();
        let outs = rig.house.startup();
        let select = last(&outs, "homeassistant/select/lights_hallway_mode/config").unwrap();
        assert_eq!(select["name"], "Hallway mode");
        assert_eq!(select["options"], json!(["auto", "dim", "manual"]));
        assert_eq!(rig.state(0), "off");
        for l in &rig.house.rooms[0].room.bulbs {
            assert_eq!(l.bulb.mode, Mode::Auto);
        }
    }

    #[test]
    fn a_light_left_on_is_not_yanked_at_startup() {
        let mut rig = Rig::new(json!({ "hallway": {
            "bulbs": { "a": { "device": "hallway_a" } },
            "lua": HALLWAY,
        } }));
        let outs = rig.send(
            "zigbee2mqtt/hallway_a",
            json!({ "state": "ON", "brightness": 250 }),
        );
        assert!(sets(&outs).is_empty());
        assert_eq!(
            last(&outs, "lights/hallway/a/state").unwrap()["mode"],
            "held"
        );
        // Someone arriving hands it back to the room.
        let outs = rig.presence("motion", true);
        assert_eq!(sets(&outs)[0].1["brightness"], 200);
    }

    #[test]
    fn arrival_turns_the_room_on_as_one_group_command_and_leaving_fades_it() {
        let mut rig = hallway();
        let outs = rig.presence("motion", true);
        assert_eq!(
            sets(&outs),
            [(
                "zigbee2mqtt/hallway/set",
                &json!({ "state": "ON", "brightness": 200, "transition": 0.4 })
            )]
        );
        assert_eq!(last(&outs, "lights/hallway/state"), Some(&json!("auto")));
        assert_eq!(last(&outs, "lights/hallway/occupied"), Some(&json!(true)));

        rig.presence("motion", false);
        assert!(sets(&rig.wait(Duration::from_secs(59))).is_empty());
        let outs = rig.wait(Duration::from_secs(1));
        assert_eq!(
            sets(&outs),
            [(
                "zigbee2mqtt/hallway/set",
                &json!({ "state": "OFF", "transition": 30.0 })
            )]
        );
        assert_eq!(last(&outs, "lights/hallway/state"), Some(&json!("off")));
        // Hidden state: HA keeps showing the mode it will come back to.
        assert_eq!(last(&outs, "lights/hallway/mode"), None);
    }

    #[test]
    fn a_manual_change_holds_for_the_state_and_comes_back_with_resume() {
        let mut rig = hallway();
        rig.presence("motion", true);
        rig.wait(Duration::from_secs(5));
        rig.send(
            "zigbee2mqtt/hallway_a",
            json!({ "state": "ON", "brightness": 40 }),
        );
        assert_eq!(
            rig.house.rooms[0].room.bulbs[0]
                .bulb
                .held()
                .map(|t| t.brightness),
            Some(40)
        );

        // Leave: the hold ends with the state, everything fades.
        rig.presence("motion", false);
        let outs = rig.mins(1);
        assert_eq!(sets(&outs)[0].0, "zigbee2mqtt/hallway/set");
        rig.report_all(&["hallway_a", "hallway_b"], json!({ "state": "OFF" }));

        // Back within the hour: the 40 is remembered for bulb a.
        let outs = rig.presence("motion", true);
        let s = sets(&outs);
        assert_eq!(s.len(), 2, "{s:?}");
        assert!(s.contains(&(
            "zigbee2mqtt/hallway_a/set",
            &json!({ "state": "ON", "brightness": 40, "transition": 0.4 })
        )));

        // Empty for over an hour: forgotten.
        rig.presence("motion", false);
        rig.mins(2);
        rig.report_all(&["hallway_a", "hallway_b"], json!({ "state": "OFF" }));
        rig.mins(61);
        let outs = rig.presence("motion", true);
        assert_eq!(sets(&outs)[0].0, "zigbee2mqtt/hallway/set");
    }

    #[test]
    fn a_scene_picked_in_ha_is_resumed_then_forgotten() {
        let mut rig = hallway();
        rig.presence("motion", true);
        let outs = rig.send("lights/hallway/mode/set", json!("dim"));
        assert_eq!(sets(&outs)[0].1["brightness"], 76);
        assert_eq!(last(&outs, "lights/hallway/mode"), Some(&json!("dim")));

        rig.presence("motion", false);
        rig.mins(2);
        let outs = rig.presence("motion", true);
        assert_eq!(rig.state(0), "dim");
        assert_eq!(sets(&outs)[0].1["brightness"], 76);

        rig.presence("motion", false);
        rig.mins(62);
        rig.presence("motion", true);
        assert_eq!(rig.state(0), "auto");
        // Unknown and hidden modes are ignored.
        rig.send("lights/hallway/mode/set", json!("off"));
        rig.send("lights/hallway/mode/set", json!("disco"));
        assert_eq!(rig.state(0), "auto");
    }

    #[test]
    fn a_reset_with_someone_there_drops_the_manual_change() {
        let mut rig = hallway();
        rig.presence("motion", true);
        rig.wait(Duration::from_secs(5));
        rig.send(
            "zigbee2mqtt/hallway_a",
            json!({ "state": "ON", "brightness": 20 }),
        );
        let outs = rig.send("lights/hallway/release", json!("release"));
        assert_eq!(rig.state(0), "auto");
        assert_eq!(rig.house.rooms[0].room.bulbs[0].bulb.mode, Mode::Auto);
        assert_eq!(sets(&outs)[0].1["brightness"], 200, "{outs:?}");
    }

    #[test]
    fn manual_sends_nothing_until_another_mode() {
        let mut rig = hallway();
        rig.presence("motion", true);
        rig.send("lights/hallway/mode/set", json!("manual"));
        rig.presence("motion", false);
        assert!(sets(&rig.mins(10)).is_empty());
        assert_eq!(rig.state(0), "manual");
        // Reset: back to auto, which with nobody there goes straight off,
        // without flashing on first.
        let outs = rig.send("lights/hallway/release", json!("release"));
        assert_eq!(rig.state(0), "off");
        assert_eq!(sets(&outs)[0].1["state"], "OFF");
    }

    #[test]
    fn toggle_holds_the_bulb_and_flips_it_back() {
        let mut rig = hallway();
        rig.presence("motion", true);
        rig.report_all(
            &["hallway_a", "hallway_b"],
            json!({ "state": "ON", "brightness": 200 }),
        );
        let outs = rig.send("zigbee2mqtt/button/action", json!("single"));
        assert_eq!(
            sets(&outs),
            [(
                "zigbee2mqtt/hallway_a/set",
                &json!({ "state": "OFF", "transition": 0.4 })
            )]
        );
        let outs = rig.send("zigbee2mqtt/button/action", json!({ "action": "single" }));
        assert_eq!(sets(&outs)[0].1["state"], "ON");
        // Actions the state doesn't handle are ignored.
        assert!(sets(&rig.send("zigbee2mqtt/button/action", json!("double"))).is_empty());
    }

    #[test]
    fn release_hands_one_bulb_back() {
        let mut rig = hallway();
        rig.presence("motion", true);
        rig.wait(Duration::from_secs(5));
        rig.send("zigbee2mqtt/hallway_a", json!({ "state": "OFF" }));
        let outs = rig.send("lights/hallway/a/release", json!(""));
        assert_eq!(
            sets(&outs),
            [(
                "zigbee2mqtt/hallway_a/set",
                &json!({ "state": "ON", "brightness": 200, "transition": 0.4 })
            )]
        );
    }

    #[test]
    fn doors_triggers_and_when_rows_drive_a_room() {
        // A cupboard-like room with a time-based trigger.
        let lua = r#"
            local late = function() return clock() >= 14 end
            room{
              doors = { door = "door" },
              triggers = { late = late },
              default = "open", start = "shut", forget_after = 0,
              states = {
                shut = { hidden = true, look = { on = false }, on = { ["door.open"] = "resume", late = "late" } },
                open = { look = { brightness = 100 }, on = { ["door.closed"] = "shut" } },
                late = { look = { brightness = 3 }, when = { { to = "shut", time_in_state = 600 } } },
              },
            }"#;
        let mut rig =
            Rig::new(json!({ "cupboard": { "bulbs": { "bulb": { "device": "c" } }, "lua": lua } }));
        rig.report_all(&["c"], json!({ "state": "OFF" }));
        let outs = rig.send("zigbee2mqtt/door", json!({ "contact": false }));
        assert_eq!(sets(&outs)[0].1["brightness"], 100);
        rig.send("zigbee2mqtt/door", json!({ "contact": true }));
        assert_eq!(rig.state(0), "shut");

        // 14:00 comes round: the trigger fires once, the row ends it.
        rig.mins(50);
        assert_eq!(rig.state(0), "late");
        rig.mins(10);
        assert_eq!(rig.state(0), "shut");
        rig.mins(10);
        assert_eq!(rig.state(0), "shut");
    }

    #[test]
    fn plugs_fade_out_as_a_delayed_off() {
        let lua = r#"room{ presence = { "m" }, default = "on", states = {
            on = { look = {}, when = { { to = "off", absent_for = 1 } } },
            off = { hidden = true, look = { on = false, transition = 60 }, on = { present = "on" } },
        } }"#;
        let mut rig = Rig::new(
            json!({ "r": { "bulbs": { "p": { "device": "p", "dimmable": false } }, "lua": lua } }),
        );
        rig.report_all(&["p"], json!({ "state": "ON" }));
        rig.presence("m", true);
        rig.presence("m", false);
        assert!(sets(&rig.wait(Duration::from_secs(59))).is_empty());
        let outs = rig.wait(Duration::from_secs(2));
        assert_eq!(
            sets(&outs),
            [("zigbee2mqtt/p/set", &json!({ "state": "OFF" }))]
        );
    }

    /// The real room files, when the repo is around (not in the Nix build).
    fn real(room: &str) -> Option<String> {
        let dir = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../systems/rpi-4b-plus/services/lighting"
        );
        std::fs::read_to_string(format!("{dir}/{room}.lua")).ok()
    }

    fn bedroom_at(wall: &str) -> Option<Rig> {
        let lua = real("bedroom")?;
        let mut rig = Rig::at(
            json!({ "bedroom": {
                "group": "bedroom",
                "bulbs": { "bulb_1": { "device": "b1" }, "bulb_2": { "device": "b2" } },
                "lua": lua,
            } }),
            wall,
        );
        rig.report_all(&["b1", "b2"], json!({ "state": "OFF" }));
        Some(rig)
    }

    #[test]
    fn bedroom_day_floor_rises_while_there_and_resets_after_leaving() {
        // After sunset, so the sun alone would keep it at the minimum.
        let Some(mut rig) = bedroom_at("2026-01-10T17:00:00+01:00") else {
            return;
        };
        let bri = |outs: &[Out]| {
            sets(outs)
                .last()
                .map(|s| s.1["brightness"].as_u64().unwrap())
        };
        let first = bri(&rig.presence("bedroom_presence", true)).unwrap();
        rig.mins(120);
        let later = rig.house.rooms[0].room.bulbs[0]
            .bulb
            .showing()
            .unwrap()
            .brightness;
        assert!(u64::from(later) > first + 30, "{first} -> {later}");

        rig.presence("bedroom_presence", false);
        rig.mins(31);
        assert_eq!(rig.state(0), "off");
        let back = bri(&rig.presence("bedroom_presence", true)).unwrap();
        assert!(back < first + 10, "{first} vs {back}");
    }

    #[test]
    fn bedroom_button_walks_through_bedtime() {
        let Some(mut rig) = bedroom_at("2026-01-10T21:30:00+01:00") else {
            return;
        };
        rig.presence("bedroom_presence", true);
        let press = |rig: &mut Rig, a: &str| {
            let outs = rig.send("zigbee2mqtt/bedroom_button/action", json!(a));
            sets(&outs).last().map(|s| s.1.clone())
        };
        assert_eq!(press(&mut rig, "single").unwrap()["brightness"], 25);
        assert_eq!(rig.state(0), "bedtime");
        assert_eq!(press(&mut rig, "single").unwrap()["state"], "OFF");
        assert_eq!(press(&mut rig, "single").unwrap()["brightness"], 25);

        // Hold: dim now, off after five minutes.
        press(&mut rig, "hold");
        assert_eq!(rig.state(0), "winddown");
        rig.mins(5);
        assert_eq!(rig.state(0), "bedtime_off");

        // A trip out at night and back: still dark, still bedtime.
        rig.presence("bedroom_presence", false);
        rig.mins(10);
        let outs = rig.presence("bedroom_presence", true);
        assert!(sets(&outs).is_empty());
    }

    #[test]
    fn bedroom_sleeps_until_the_wake_ramp() {
        let Some(mut rig) = bedroom_at("2026-01-10T23:00:00+01:00") else {
            return;
        };
        rig.send("mqtt-auto/sunrise-lights/start-time", json!("07:30:00"));
        rig.send("zigbee2mqtt/bedroom_button/action", json!("single"));
        rig.mins(31);
        assert_eq!(rig.state(0), "off");
        // 07:00, moving in bed: the house sleeps, so nothing comes on.
        rig.mins(7 * 60 + 29);
        assert!(sets(&rig.presence("bedroom_presence", true)).is_empty());
        rig.presence("bedroom_presence", false);
        // 07:30: the ramp starts, from any state, even with nobody seen.
        rig.mins(29);
        assert_eq!(rig.state(0), "off");
        rig.mins(2);
        assert_eq!(rig.state(0), "wake");
        assert_eq!(rig.house.house.as_deref(), Some("day"));
        let early = rig.house.rooms[0].room.bulbs[0].bulb.showing().unwrap();
        rig.mins(40);
        let late = rig.house.rooms[0].room.bulbs[0].bulb.showing().unwrap();
        assert!(
            early.on && late.brightness > early.brightness,
            "{early:?} {late:?}"
        );
        assert_eq!(rig.state(0), "wake");
        // Over, and nobody seen for hours: off.
        rig.mins(10);
        assert_eq!(rig.state(0), "off");
    }

    #[test]
    fn bedroom_without_a_ramp_wakes_at_nine() {
        let Some(mut rig) = bedroom_at("2026-01-10T23:00:00+01:00") else {
            return;
        };
        rig.send("mqtt-auto/sunrise-lights/duration", json!(0));
        // Before bed, the house still awake: arriving lights the room.
        assert!(!sets(&rig.presence("bedroom_presence", true)).is_empty());
        rig.presence("bedroom_presence", false);
        rig.mins(31);
        assert_eq!(rig.state(0), "off");
        // Nobody pressed the button: 02:00 puts the house to sleep anyway.
        rig.mins(3 * 60);
        assert_eq!(rig.house.house.as_deref(), Some("night"));
        // 08:31: still night, nothing comes on.
        rig.mins(6 * 60);
        assert!(sets(&rig.presence("bedroom_presence", true)).is_empty());
        rig.presence("bedroom_presence", false);
        // 09:01: day, so the next movement lights the room.
        rig.mins(30);
        assert_eq!(rig.house.house.as_deref(), Some("day"));
        assert!(!sets(&rig.presence("bedroom_presence", true)).is_empty());
        assert_eq!(rig.state(0), "day");
    }

    #[test]
    fn bathroom_door_and_sensor() {
        let Some(lua) = real("bathroom") else {
            return;
        };
        let mut rig = Rig::new(json!({ "bathroom": {
            "bulbs": { "light": { "device": "l" } },
            "lua": lua,
        } }));
        rig.report_all(&["l"], json!({ "state": "OFF" }));
        let door = |rig: &mut Rig, open: bool| {
            rig.send("zigbee2mqtt/bathroom_door", json!({ "contact": !open }))
        };

        // Door opened, nobody ever seen: on, then off after a minute.
        assert_eq!(sets(&door(&mut rig, true))[0].1["state"], "ON");
        rig.wait(Duration::from_secs(59));
        assert_eq!(rig.state(0), "auto");
        rig.wait(Duration::from_secs(1));
        assert_eq!(rig.state(0), "off");

        // In with the door shut behind them: stays on while seen, off 30s
        // after.
        door(&mut rig, true);
        rig.presence("bathroom_presence", true);
        door(&mut rig, false);
        rig.mins(10);
        assert_eq!(rig.state(0), "auto");
        rig.presence("bathroom_presence", false);
        rig.wait(Duration::from_secs(30));
        assert_eq!(rig.state(0), "off");

        // Out, door shut, nobody seen: off 3s later.
        rig.presence("bathroom_presence", true);
        rig.mins(2);
        rig.presence("bathroom_presence", false);
        door(&mut rig, true);
        door(&mut rig, false);
        assert_eq!(rig.state(0), "closing");
        rig.wait(Duration::from_secs(3));
        assert_eq!(rig.state(0), "off");

        // Shut in, seen within the grace: stays on.
        door(&mut rig, true);
        door(&mut rig, false);
        rig.wait(Duration::from_secs(1));
        rig.presence("bathroom_presence", true);
        assert_eq!(rig.state(0), "auto");

        // Reset, nobody there: dark, not a minute of light.
        rig.presence("bathroom_presence", false);
        rig.mins(1);
        assert_eq!(rig.state(0), "off");
        let outs = rig.send("lights/bathroom/release", json!("release"));
        assert!(
            !sets(&outs).iter().any(|s| s.1["state"] == "ON"),
            "{outs:?}"
        );
        assert_eq!(rig.state(0), "off");
        // Reset with the door open: lit, as at startup.
        door(&mut rig, true);
        rig.send("lights/bathroom/release", json!("release"));
        assert_eq!(rig.state(0), "auto");

        // While the house sleeps: dim, warm, the same rules.
        rig.mins(2);
        door(&mut rig, false);
        rig.wait(Duration::from_secs(3));
        rig.send("lights/house/set", json!("night"));
        let outs = door(&mut rig, true);
        assert_eq!(rig.state(0), "night");
        assert_eq!(sets(&outs)[0].1["brightness"], 20);
        rig.wait(Duration::from_secs(60));
        assert_eq!(rig.state(0), "off");
    }

    #[test]
    fn living_room_plugs_follow_daylight_and_buttons_toggle() {
        let Some(lua) = real("living-room") else {
            return;
        };
        let mut rig = Rig::at(
            json!({ "living-room": {
                "group": "living_room",
                "bulbs": {
                    "light": { "device": "ceiling" }, "bulb_1": { "device": "b1" }, "bulb_2": { "device": "b2" },
                    "carla_desk_lamp": { "device": "lamp1", "dimmable": false },
                    "standing_lamp": { "device": "lamp2", "dimmable": false },
                },
                "lua": lua,
            } }),
            "2026-01-10T12:00:00+01:00",
        );
        // The knobs as HA has them: lamps on in the dark.
        for d in ["lamp1", "lamp2"] {
            rig.send(&format!("mqtt-auto/sun-follow/{d}/invert"), json!(true));
        }
        rig.report_all(
            &["ceiling", "b1", "b2", "lamp1", "lamp2"],
            json!({ "state": "OFF" }),
        );
        let on = |rig: &Rig, name: &str| {
            let l = rig.house.rooms[0]
                .room
                .bulbs
                .iter()
                .find(|l| l.name == name)
                .unwrap();
            l.bulb.showing().unwrap().on
        };

        // Midday, nobody here: everything off. Evening: the lamps come on
        // by themselves.
        assert!(!on(&rig, "carla_desk_lamp") && !on(&rig, "standing_lamp"));
        rig.mins(6 * 60);
        assert_eq!(rig.state(0), "off");
        assert!(on(&rig, "carla_desk_lamp") && on(&rig, "standing_lamp"));
        assert!(!on(&rig, "light"));

        // Someone in: the room lights up. Single toggles the ceiling only.
        rig.presence("livingroom_presence", true);
        assert!(on(&rig, "light") && on(&rig, "bulb_1"));
        rig.send("zigbee2mqtt/livingroom_button/action", json!("single"));
        assert!(!on(&rig, "light") && on(&rig, "bulb_1"));
        // Double: something is on, so everything goes off, lamps too.
        rig.send("zigbee2mqtt/livingroom_button/action", json!("double"));
        let all = [
            "light",
            "bulb_1",
            "bulb_2",
            "carla_desk_lamp",
            "standing_lamp",
        ];
        assert!(all.iter().all(|b| !on(&rig, b)));
    }

    /// Bedroom, hallway and living room from the real files.
    fn house_at(wall: &str) -> Option<Rig> {
        let rooms = json!({
            "bedroom": {
                "bulbs": { "bulb_1": { "device": "b1" }, "bulb_2": { "device": "b2" } },
                "lua": real("bedroom")?,
            },
            "hallway": {
                "bulbs": { "bulb_1": { "device": "h1" } },
                "lua": real("hallway")?,
            },
            "living-room": {
                "bulbs": {
                    "light": { "device": "ceiling" }, "bulb_1": { "device": "l1" }, "bulb_2": { "device": "l2" },
                    "carla_desk_lamp": { "device": "lamp1", "dimmable": false },
                    "standing_lamp": { "device": "lamp", "dimmable": false },
                },
                "lua": real("living-room")?,
            },
        });
        let mut rig = Rig::at(rooms, wall);
        rig.send("mqtt-auto/sun-follow/lamp/invert", json!(true));
        let all = ["b1", "b2", "h1", "ceiling", "l1", "l2", "lamp1", "lamp"];
        rig.report_all(&all, json!({ "state": "OFF" }));
        Some(rig)
    }

    fn showing(rig: &Rig, room: usize, bulb: &str) -> Target {
        let l = rig.house.rooms[room]
            .room
            .bulbs
            .iter()
            .find(|l| l.name == bulb)
            .unwrap();
        l.bulb.showing().unwrap()
    }

    #[test]
    fn bedtime_puts_the_house_to_sleep_and_the_wake_ramp_wakes_it() {
        let Some(mut rig) = house_at("2026-01-10T23:00:00+01:00") else {
            return;
        };
        let (bedroom, hallway, living) = (0, 1, 2);
        rig.presence("livingroom_presence", true);
        assert_eq!(rig.state(living), "auto");
        assert!(
            showing(&rig, living, "standing_lamp").on,
            "the lamp is on in the dark"
        );

        // Bedtime: the house goes to sleep, the living room dims at once and
        // its lamp goes off.
        let outs = rig.send("zigbee2mqtt/bedroom_button/action", json!("single"));
        assert_eq!(last(&outs, "lights/house"), Some(&json!("night")));
        assert_eq!(rig.state(bedroom), "bedtime");
        assert_eq!(rig.state(living), "night");
        assert_eq!(showing(&rig, living, "light").brightness, 25);
        assert!(!showing(&rig, living, "standing_lamp").on);
        // Two minutes after leaving, not thirty.
        rig.presence("livingroom_presence", false);
        rig.wait(Duration::from_secs(120));
        assert_eq!(rig.state(living), "off");

        // A walk down the hallway: faint, and off 30 seconds after.
        let outs = rig.presence("hallway_motion", true);
        assert_eq!(sets(&outs)[0].1["brightness"], 8);
        rig.presence("hallway_motion", false);
        rig.wait(Duration::from_secs(30));
        assert_eq!(rig.state(hallway), "off");

        // 06:30, the ramp: day again. The hallway is back to normal.
        rig.mins(7 * 60 + 31);
        assert_eq!(rig.state(bedroom), "wake");
        assert_eq!(rig.house.house.as_deref(), Some("day"));
        rig.presence("hallway_motion", true);
        assert_eq!(rig.state(hallway), "auto");
        rig.presence("hallway_motion", false);
        rig.mins(1);
        assert_eq!(rig.state(hallway), "off");
    }

    #[test]
    fn the_house_falls_asleep_at_two_and_ha_can_set_it() {
        let Some(mut rig) = house_at("2026-01-10T01:50:00+01:00") else {
            return;
        };
        rig.presence("hallway_motion", true);
        assert_eq!(rig.state(1), "auto");
        rig.mins(11);
        assert_eq!(rig.house.house.as_deref(), Some("night"));
        assert_eq!(rig.state(1), "night");

        let startup = rig.house.startup();
        let select = last(&startup, "homeassistant/select/lights_house_mode/config").unwrap();
        assert_eq!(select["options"], json!(HOUSE_MODES));
        rig.send("lights/house/set", json!("day"));
        assert_eq!(rig.state(1), "auto");
        rig.send("lights/house/set", json!("disco"));
        assert_eq!(rig.house.house.as_deref(), Some("day"));
    }

    #[test]
    fn bright_lifts_every_room_until_bedtime() {
        let Some(mut rig) = house_at("2026-01-10T21:00:00+01:00") else {
            return;
        };
        let (bedroom, living) = (0, 2);
        rig.presence("livingroom_presence", true);
        rig.presence("bedroom_presence", true);
        let evening = showing(&rig, living, "light");
        assert!(evening.brightness < 100, "{evening:?}");

        // Already on: it glides up and cools, no state change.
        rig.send("lights/house/set", json!("bright"));
        for (r, bulb) in [(living, "light"), (bedroom, "bulb_1")] {
            let t = showing(&rig, r, bulb);
            assert!(t.brightness >= 190, "{t:?}");
            assert_eq!(t.color_temp, Some(250));
        }
        assert_eq!(rig.state(living), "auto");

        // Bedtime ends it.
        rig.send("zigbee2mqtt/bedroom_button/action", json!("single"));
        assert_eq!(rig.state(living), "night");
        assert_eq!(showing(&rig, living, "light").brightness, 25);
        // Bright from HA wakes a sleeping room too.
        rig.send("lights/house/set", json!("bright"));
        assert_eq!(rig.state(living), "auto");
        assert!(showing(&rig, living, "light").brightness >= 190);
    }

    #[test]
    fn a_reset_never_contradicts_the_house_or_lights_an_empty_room() {
        let Some(mut rig) = house_at("2026-01-10T23:00:00+01:00") else {
            return;
        };
        let (hallway, living) = (1, 2);
        rig.presence("livingroom_presence", true);
        rig.send("lights/house/set", json!("night"));
        assert_eq!(rig.state(living), "night");

        // One room reset while the house sleeps: still night.
        rig.send("lights/living-room/release", json!("release"));
        assert_eq!(rig.state(living), "night");
        // Someone picking auto in HA: straight back to night too.
        rig.send("lights/living-room/mode/set", json!("auto"));
        assert_eq!(rig.state(living), "night");

        // Reset everything: the house wakes with it, the empty hallway stays
        // dark.
        let outs = rig.send("lights/release", json!("release"));
        assert_eq!(last(&outs, "lights/house"), Some(&json!("day")));
        assert_eq!(rig.state(living), "auto");
        assert_eq!(rig.state(hallway), "off");
        assert!(!outs
            .iter()
            .any(|o| o.topic.starts_with("zigbee2mqtt/h1") && o.payload["state"] == "ON"));
    }

    #[test]
    fn a_house_mode_not_in_the_config_fails_loading() {
        let cfg = json!({ "latitude": 0.0, "longitude": 0.0, "house_modes": ["day"], "rooms": { "r": {
            "bulbs": { "a": { "device": "a" } },
            "lua": r#"room{ default = "on", states = { on = { look = {}, when = { { to = "on", house = "nite" } } } } }"#,
        } } });
        let wall = DateTime::parse_from_rfc3339(NOON).unwrap();
        let err = House::new(serde_json::from_value(cfg).unwrap(), Instant::now(), wall).err();
        assert!(format!("{err:?}").contains("nite"), "{err:?}");
    }

    #[test]
    fn a_restart_restores_the_house_mode_once() {
        let Some(mut rig) = house_at("2026-01-10T23:00:00+01:00") else {
            return;
        };
        rig.send("lights/house", json!("night"));
        let outs = rig.presence("hallway_motion", true);
        assert_eq!(sets(&outs)[0].1["brightness"], 8);
        // Later copies are our own echo, never an instruction.
        rig.send("lights/house", json!("day"));
        assert_eq!(rig.house.house.as_deref(), Some("night"));
    }

    #[test]
    fn every_real_room_loads() {
        for room in [
            "bathroom",
            "bedroom",
            "cupboard",
            "hallway",
            "kitchen",
            "living-room",
        ] {
            let Some(lua) = real(room) else {
                return;
            };
            let cfg = json!({ "latitude": 52.52, "longitude": 13.405, "house_modes": HOUSE_MODES, "rooms": { room: {
                "bulbs": {
                    "light": { "device": "x1" }, "bulb_1": { "device": "x2" }, "bulb_2": { "device": "x3" },
                    "bulb": { "device": "x4" }, "a": { "device": "x5" },
                    "carla_desk_lamp": { "device": "x6", "dimmable": false },
                    "standing_lamp": { "device": "x7", "dimmable": false },
                },
                "lua": lua,
            } } });
            let wall = DateTime::parse_from_rfc3339(NOON).unwrap();
            if let Err(e) = House::new(serde_json::from_value(cfg).unwrap(), Instant::now(), wall) {
                panic!("{room}: {e:#}");
            }
        }
    }
}
