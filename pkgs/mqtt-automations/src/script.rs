//! Room logic written in Lua: one sandboxed Lua state per room, driven by
//! the same events as the built-in logic and answering with the same
//! per-bulb arbiter inputs, so ownership, fades and group commands stay in
//! Rust and a script can't fight the user or flicker a bulb.
//!
//! API (all durations in seconds, brightness 1-254, colour temperature in
//! mireds):
//!   - `on(device, fn(payload))`: z2m messages from `zigbee2mqtt/<device>`.
//!     `on_topic(topic, fn(payload))` for any other topic. Top level only:
//!     subscriptions are fixed once the script has loaded.
//!   - `after(s, fn)` / `every(s, fn)` -> id, `cancel(id)`.
//!   - `light(name)`: one of the room's bulbs, with
//!     `:auto{ on, brightness, color_temp, scale, transition }` (what the
//!     automation wants; the bulb follows unless a person took over),
//!     `:user{ ... }` (a person's choice: applied and held),
//!     `:release{ transition }` (hand back to the automation) and
//!     `:state()` -> `{ mode = "auto"|"held"|"unknown", on, brightness,
//!     color_temp }` or nil before the bulb has reported.
//!     `lights` lists the room's bulb names.
//!   - `sun.level{ min, max, gamma, invert }` -> brightness for now,
//!     `sun.ct{ warm, cool }` -> mireds, `sun.daylight()` -> 0..1.
//!   - `clock()` -> local time of day in hours (13.5 = 13:30).
//!   - `room`: this room's name. `publish(name, value)`: retain `value`
//!     (string, number or boolean, sent bare) on `lights/<room>/<name>`,
//!     for HA to show; `name` is lowercase letters, digits, `_` and `-`.
//!   - `log(...)`.
//!
//! A runtime error in a handler is logged and that handler's requests are
//! dropped; the room keeps running. Errors while loading fail startup.

use std::collections::{BTreeMap, BTreeSet};
use std::time::{Duration, Instant};

use anyhow::{anyhow, Result};
use chrono::{DateTime, FixedOffset, Timelike};
use mlua::serde::SerializeOptions;
use mlua::{
    Function, HookTriggers, Lua, LuaOptions, LuaSerdeExt, StdLib, Table, UserData, UserDataMethods,
    Value, Variadic, VmState,
};

use crate::arbiter::{Input, Target};
use crate::{curves, sun};

/// One handler or timer may run this long before it is stopped.
const CALL_BUDGET: Duration = Duration::from_millis(200);
const MEMORY_LIMIT: usize = 32 << 20;
/// Timers firing timers (`after(0, ...)` chains) per tick.
const MAX_TIMER_ROUNDS: usize = 100;
const MIN_EVERY: Duration = Duration::from_secs(1);

const HANDLERS: &str = "handlers";
const TIMERS: &str = "timers";

/// The arbiter's view of a bulb.
#[derive(Clone, Copy, Debug)]
struct Shown {
    held: bool,
    state: Target,
}

struct Bulb {
    device: String,
    shown: Option<Shown>,
}

struct Timer {
    at: Instant,
    every: Option<Duration>,
}

/// Everything the API functions share, kept as Lua app data.
struct State {
    room: String,
    latitude: f64,
    longitude: f64,
    now: Instant,
    wall: DateTime<FixedOffset>,
    lights: BTreeMap<String, Bulb>,
    requests: Vec<(String, Input)>,
    /// `publish()` calls not yet collected: (name, value).
    published: Vec<(String, serde_json::Value)>,
    timers: BTreeMap<u64, Timer>,
    next_timer: u64,
    topics: BTreeSet<String>,
    loaded: bool,
}

/// Real-time cutoff for the running call, checked by the instruction hook.
struct CallDeadline(std::time::Instant);

/// Helpers loaded ahead of every room script (`follow`, `occupancy`, ...).
const PRELUDE: &str = include_str!("prelude.lua");

pub struct Script {
    lua: Lua,
}

impl Script {
    /// `lights`: the room's bulbs as (name, z2m device).
    pub fn new(
        room: &str,
        source: &str,
        lights: impl IntoIterator<Item = (String, String)>,
        (latitude, longitude): (f64, f64),
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Result<Self> {
        let lua = Lua::new_with(
            StdLib::STRING | StdLib::TABLE | StdLib::MATH | StdLib::UTF8,
            LuaOptions::default(),
        )
        .map_err(lua_err)?;
        lua.set_memory_limit(MEMORY_LIMIT).map_err(lua_err)?;
        lua.set_app_data(State {
            room: room.to_owned(),
            latitude,
            longitude,
            now,
            wall,
            lights: lights
                .into_iter()
                .map(|(name, device)| {
                    let bulb = Bulb {
                        device,
                        shown: None,
                    };
                    (name, bulb)
                })
                .collect(),
            requests: Vec::new(),
            published: Vec::new(),
            timers: BTreeMap::new(),
            next_timer: 1,
            topics: BTreeSet::new(),
            loaded: false,
        });
        let triggers = HookTriggers::new().every_nth_instruction(10_000);
        lua.set_hook(triggers, |lua, _| {
            match lua.try_app_data_ref::<CallDeadline>() {
                Ok(Some(d)) if std::time::Instant::now() > d.0 => {
                    Err(mlua::Error::runtime("took too long, stopped"))
                }
                _ => Ok(VmState::Continue),
            }
        })
        .map_err(lua_err)?;
        install(&lua).map_err(lua_err)?;

        let script = Self { lua };
        script.budget();
        script
            .lua
            .load(PRELUDE)
            .set_name("@prelude.lua")
            .exec()
            .map_err(|e| anyhow!("prelude: {e}"))?;
        script.budget();
        script
            .lua
            .load(source)
            .set_name(format!("@{room}.lua"))
            .exec()
            .map_err(|e| anyhow!("room {room}: {e}"))?;
        script.state().loaded = true;
        Ok(script)
    }

    /// Topics the script listens to.
    pub fn topics(&self) -> Vec<String> {
        self.state().topics.iter().cloned().collect()
    }

    pub fn deadline(&self) -> Option<Instant> {
        self.state().timers.values().map(|t| t.at).min()
    }

    pub fn message(
        &mut self,
        topic: &str,
        payload: &serde_json::Value,
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Vec<(String, Input)> {
        self.set_clock(now, wall);
        let handlers = self
            .lua
            .named_registry_value::<Table>(HANDLERS)
            .and_then(|h| h.get::<Option<Table>>(topic));
        if let Ok(Some(list)) = handlers {
            let payload = self.lua.to_value_with(payload, serialize_options());
            match payload {
                Ok(payload) => {
                    for f in list.sequence_values::<Function>().flatten() {
                        self.call(&f, payload.clone());
                    }
                }
                Err(e) => self.log(&format!("{topic}: {e}")),
            }
        }
        self.take()
    }

    pub fn bulb(&mut self, light: &str, held: bool, state: Target) -> Vec<(String, Input)> {
        if let Some(slot) = self.state().lights.get_mut(light) {
            slot.shown = Some(Shown { held, state });
        }
        self.take()
    }

    /// Run due timers, plus anything the script did while loading.
    pub fn tick(&mut self, now: Instant, wall: DateTime<FixedOffset>) -> Vec<(String, Input)> {
        self.set_clock(now, wall);
        for _ in 0..MAX_TIMER_ROUNDS {
            let due = {
                let state = self.state();
                let mut due: Vec<_> = state.timers.iter().filter(|(_, t)| t.at <= now).collect();
                due.sort_by_key(|(id, t)| (t.at, **id));
                due.into_iter().map(|(id, _)| *id).collect::<Vec<_>>()
            };
            if due.is_empty() {
                return self.take();
            }
            for id in due {
                let Ok(Some(f)) = self
                    .lua
                    .named_registry_value::<Table>(TIMERS)
                    .and_then(|t| t.get::<Option<Function>>(id))
                else {
                    continue;
                };
                {
                    let mut state = self.state();
                    match state.timers.get_mut(&id) {
                        Some(Timer { at, every: Some(d) }) => *at = now + *d,
                        Some(_) => {
                            state.timers.remove(&id);
                        }
                        // Cancelled by an earlier timer this round.
                        None => continue,
                    }
                }
                if !self.state().timers.contains_key(&id) {
                    let _ = self
                        .lua
                        .named_registry_value::<Table>(TIMERS)
                        .and_then(|t| t.set(id, Value::Nil));
                }
                self.call(&f, Value::Nil);
            }
        }
        self.log("timers keep firing immediately, deferring the rest");
        self.take()
    }

    fn call(&self, f: &Function, arg: Value) {
        let marks = {
            let s = self.state();
            (s.requests.len(), s.published.len())
        };
        self.budget();
        if let Err(e) = f.call::<()>(arg) {
            // A half-run handler would leave the room half-applied.
            let mut s = self.state();
            s.requests.truncate(marks.0);
            s.published.truncate(marks.1);
            drop(s);
            self.log(&e.to_string());
        }
    }

    /// Values the script published since the last call, as (name, value).
    pub fn take_published(&mut self) -> Vec<(String, serde_json::Value)> {
        std::mem::take(&mut self.state().published)
    }

    fn budget(&self) {
        self.lua
            .set_app_data(CallDeadline(std::time::Instant::now() + CALL_BUDGET));
    }

    fn set_clock(&self, now: Instant, wall: DateTime<FixedOffset>) {
        let mut state = self.state();
        state.now = now;
        state.wall = wall;
    }

    fn take(&self) -> Vec<(String, Input)> {
        std::mem::take(&mut self.state().requests)
    }

    fn log(&self, msg: &str) {
        eprintln!("{}: {msg}", self.state().room);
    }

    fn state(&self) -> mlua::AppDataRefMut<'_, State> {
        self.lua
            .app_data_mut::<State>()
            .expect("state is installed in new")
    }
}

fn serialize_options() -> SerializeOptions {
    // Absent JSON fields and `null` should both read as nil in Lua.
    SerializeOptions::new()
        .serialize_none_to_null(false)
        .serialize_unit_to_null(false)
}

/// mlua errors aren't `Send`; keep the message.
fn lua_err(e: mlua::Error) -> anyhow::Error {
    anyhow!("{e}")
}

fn state(lua: &Lua) -> mlua::Result<mlua::AppDataRefMut<'_, State>> {
    lua.app_data_mut::<State>()
        .ok_or_else(|| mlua::Error::runtime("room state missing"))
}

fn install(lua: &Lua) -> mlua::Result<()> {
    lua.set_named_registry_value(HANDLERS, lua.create_table()?)?;
    lua.set_named_registry_value(TIMERS, lua.create_table()?)?;
    let g = lua.globals();

    g.set(
        "on",
        lua.create_function(|lua, (device, f): (String, Function)| {
            subscribe(lua, format!("zigbee2mqtt/{device}"), f)
        })?,
    )?;
    g.set(
        "on_topic",
        lua.create_function(|lua, (topic, f): (String, Function)| subscribe(lua, topic, f))?,
    )?;
    g.set(
        "after",
        lua.create_function(|lua, (s, f): (f64, Function)| schedule(lua, s, f, false))?,
    )?;
    g.set(
        "every",
        lua.create_function(|lua, (s, f): (f64, Function)| schedule(lua, s, f, true))?,
    )?;
    g.set(
        "cancel",
        lua.create_function(|lua, id: u64| {
            state(lua)?.timers.remove(&id);
            lua.named_registry_value::<Table>(TIMERS)?
                .set(id, Value::Nil)
        })?,
    )?;
    g.set(
        "light",
        lua.create_function(|lua, name: String| {
            if !state(lua)?.lights.contains_key(&name) {
                return Err(mlua::Error::runtime(format!(
                    "no bulb {name:?} in this room"
                )));
            }
            Ok(Light(name))
        })?,
    )?;
    let names: Vec<String> = state(lua)?.lights.keys().cloned().collect();
    g.set("lights", names)?;
    let room = state(lua)?.room.clone();
    g.set("room", room)?;
    g.set(
        "publish",
        lua.create_function(|lua, (name, value): (String, Value)| {
            let ok = !name.is_empty()
                && name.bytes().all(|b| {
                    b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-'
                });
            if !ok {
                return Err(mlua::Error::runtime(format!("bad publish name {name:?}")));
            }
            if !matches!(
                value,
                Value::String(_) | Value::Boolean(_) | Value::Integer(_) | Value::Number(_)
            ) {
                return Err(mlua::Error::runtime(
                    "publish() takes a string, number or boolean",
                ));
            }
            let value: serde_json::Value = lua.from_value(value)?;
            state(lua)?.published.push((name, value));
            Ok(())
        })?,
    )?;

    let sun_table = lua.create_table()?;
    sun_table.set(
        "level",
        lua.create_function(|lua, opts: Option<Table>| {
            let opts = Opts::new(opts, &["min", "max", "gamma", "invert"])?;
            let (min, max) = (opts.pct("min", 1)?, opts.pct("max", 100)?);
            let gamma = opts.number("gamma", 1.0, 0.1, 10.0)?;
            let invert = opts.flag("invert", false)?;
            let raw = daylight(lua)?;
            let frac = if invert { 1.0 - raw } else { raw };
            Ok(curves::brightness_254(
                min,
                max,
                curves::apply_gamma(frac, gamma),
            ))
        })?,
    )?;
    sun_table.set(
        "ct",
        lua.create_function(|lua, opts: Option<Table>| {
            let opts = Opts::new(opts, &["warm", "cool"])?;
            let warm = opts.number("warm", 454.0, 100.0, 1000.0)? as u16;
            let cool = opts.number("cool", 250.0, 100.0, 1000.0)? as u16;
            let s = state(lua)?;
            let progress = sun::day_progress(s.latitude, s.longitude, s.wall);
            Ok(curves::color_temp(progress, warm, cool))
        })?,
    )?;
    sun_table.set("daylight", lua.create_function(|lua, ()| daylight(lua))?)?;
    g.set("sun", sun_table)?;

    g.set(
        "clock",
        lua.create_function(|lua, ()| {
            let t = state(lua)?.wall.time();
            Ok(f64::from(t.num_seconds_from_midnight()) / 3600.0)
        })?,
    )?;
    g.set(
        "log",
        lua.create_function(|lua, args: Variadic<Value>| {
            let parts: Vec<String> = args
                .iter()
                .map(|v| v.to_string().unwrap_or_else(|_| format!("{v:?}")))
                .collect();
            eprintln!("{}: {}", state(lua)?.room, parts.join(" "));
            Ok(())
        })?,
    )?;
    Ok(())
}

fn subscribe(lua: &Lua, topic: String, f: Function) -> mlua::Result<()> {
    if state(lua)?.loaded {
        return Err(mlua::Error::runtime(
            "on() only works at the top level of the script",
        ));
    }
    let handlers = lua.named_registry_value::<Table>(HANDLERS)?;
    let list = match handlers.get::<Option<Table>>(topic.as_str())? {
        Some(list) => list,
        None => {
            let list = lua.create_table()?;
            handlers.set(topic.as_str(), &list)?;
            list
        }
    };
    list.push(f)?;
    state(lua)?.topics.insert(topic);
    Ok(())
}

fn schedule(lua: &Lua, secs: f64, f: Function, every: bool) -> mlua::Result<u64> {
    let d = Duration::try_from_secs_f64(secs)
        .map_err(|_| mlua::Error::runtime(format!("bad duration {secs}")))?;
    if every && d < MIN_EVERY {
        return Err(mlua::Error::runtime("every() needs at least 1 second"));
    }
    let id = {
        let mut s = state(lua)?;
        let id = s.next_timer;
        s.next_timer += 1;
        let at = s.now + d;
        s.timers.insert(
            id,
            Timer {
                at,
                every: every.then_some(d),
            },
        );
        id
    };
    lua.named_registry_value::<Table>(TIMERS)?.set(id, f)?;
    Ok(id)
}

fn daylight(lua: &Lua) -> mlua::Result<f64> {
    let s = state(lua)?;
    Ok(sun::daylight_fraction(s.latitude, s.longitude, s.wall))
}

/// A table of named options; unknown keys are errors, so typos surface.
struct Opts(Option<Table>);

impl Opts {
    fn new(t: Option<Table>, allowed: &[&str]) -> mlua::Result<Self> {
        if let Some(t) = &t {
            for pair in t.pairs::<Value, Value>() {
                let (key, _) = pair?;
                let key = key.to_string()?;
                if !allowed.contains(&key.as_str()) {
                    return Err(mlua::Error::runtime(format!(
                        "unknown option {key:?} (expected one of {})",
                        allowed.join(", ")
                    )));
                }
            }
        }
        Ok(Self(t))
    }

    fn get<T: mlua::FromLua>(&self, key: &str) -> mlua::Result<Option<T>> {
        match &self.0 {
            Some(t) => t.get(key),
            None => Ok(None),
        }
    }

    fn number(&self, key: &str, default: f64, lo: f64, hi: f64) -> mlua::Result<f64> {
        let Some(v) = self.get::<f64>(key)? else {
            return Ok(default);
        };
        if !(lo..=hi).contains(&v) {
            return Err(mlua::Error::runtime(format!(
                "{key} = {v} is outside {lo}..{hi}"
            )));
        }
        Ok(v)
    }

    fn pct(&self, key: &str, default: u8) -> mlua::Result<u8> {
        Ok(self.number(key, default.into(), 0.0, 100.0)?.round() as u8)
    }

    fn flag(&self, key: &str, default: bool) -> mlua::Result<bool> {
        Ok(self.get(key)?.unwrap_or(default))
    }

    fn transition(&self) -> mlua::Result<Duration> {
        Ok(Duration::from_secs_f64(self.number(
            "transition",
            0.0,
            0.0,
            3600.0,
        )?))
    }

    fn target(&self) -> mlua::Result<Target> {
        Ok(Target {
            on: self.flag("on", true)?,
            brightness: self
                .number("brightness", Target::FULL.into(), 1.0, 254.0)?
                .round() as u8,
            color_temp: match self.get::<f64>("color_temp")? {
                Some(_) => Some(self.number("color_temp", 0.0, 100.0, 1000.0)?.round() as u16),
                None => None,
            },
        })
    }
}

const TARGET_KEYS: [&str; 5] = ["on", "brightness", "color_temp", "scale", "transition"];

/// A bulb handle from `light(name)`.
struct Light(String);

impl Light {
    fn request(&self, lua: &Lua, input: Input) -> mlua::Result<()> {
        state(lua)?.requests.push((self.0.clone(), input));
        Ok(())
    }
}

impl UserData for Light {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_method("auto", |lua, this, t: Option<Table>| {
            let opts = Opts::new(t, &TARGET_KEYS)?;
            let input = Input::Auto {
                target: opts.target()?,
                scale: opts.number("scale", 1.0, 0.0, 1.0)? as f32,
                transition: opts.transition()?,
            };
            this.request(lua, input)
        });
        methods.add_method("user", |lua, this, t: Option<Table>| {
            let opts = Opts::new(t, &["on", "brightness", "color_temp", "transition"])?;
            let input = Input::User {
                target: opts.target()?,
                transition: opts.transition()?,
            };
            this.request(lua, input)
        });
        methods.add_method("release", |lua, this, t: Option<Table>| {
            let opts = Opts::new(t, &["transition"])?;
            let input = Input::Release {
                transition: opts.transition()?,
            };
            this.request(lua, input)
        });
        methods.add_method("device", |lua, this, ()| {
            Ok(state(lua)?.lights.get(&this.0).map(|b| b.device.clone()))
        });
        methods.add_method("state", |lua, this, ()| {
            let Some(shown) = state(lua)?.lights.get(&this.0).and_then(|b| b.shown) else {
                return Ok(None);
            };
            let t = lua.create_table()?;
            t.set("mode", if shown.held { "held" } else { "auto" })?;
            t.set("on", shown.state.on)?;
            t.set("brightness", shown.state.brightness)?;
            t.set("color_temp", shown.state.color_temp)?;
            Ok(Some(t))
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const NOON: &str = "2026-06-21T13:10:00+02:00";

    struct Rig {
        script: Script,
        now: Instant,
        wall: DateTime<FixedOffset>,
    }

    impl Rig {
        fn new(source: &str) -> Self {
            Self::try_new(source).unwrap()
        }

        fn try_new(source: &str) -> Result<Self> {
            let now = Instant::now();
            let wall = DateTime::parse_from_rfc3339(NOON).unwrap();
            let lights = ["a", "b"].map(|n| (n.to_owned(), format!("dev_{n}")));
            Ok(Self {
                script: Script::new("test", source, lights, (52.52, 13.405), now, wall)?,
                now,
                wall,
            })
        }

        fn send(&mut self, device: &str, payload: serde_json::Value) -> Vec<(String, Input)> {
            let topic = format!("zigbee2mqtt/{device}");
            self.script.message(&topic, &payload, self.now, self.wall)
        }

        fn wait(&mut self, secs: u64) -> Vec<(String, Input)> {
            self.now += Duration::from_secs(secs);
            self.wall += chrono::TimeDelta::seconds(secs as i64);
            self.script.tick(self.now, self.wall)
        }

        fn topic(&mut self, topic: &str, payload: serde_json::Value) -> Vec<(String, Input)> {
            self.script.message(topic, &payload, self.now, self.wall)
        }
    }

    fn last_auto(reqs: &[(String, Input)], bulb: &str) -> Option<Target> {
        reqs.iter().rev().find_map(|(n, i)| match i {
            Input::Auto { target, .. } if n == bulb => Some(*target),
            _ => None,
        })
    }

    #[test]
    fn scene_sets_brightness_without_holding_and_ends_with_the_visit() {
        let mut rig = Rig::new(MOTION_ROOM);
        rig.wait(0);
        rig.send("motion", json!({ "occupancy": true }));
        let reqs = rig.topic("lights/test/scene", json!("dim"));
        let t = last_auto(&reqs, "a").expect("applied at once");
        assert_eq!((t.on, t.brightness), (true, 76));
        assert!(
            reqs.iter().all(|(_, i)| matches!(i, Input::Auto { .. })),
            "a scene is automation, not a hold"
        );

        rig.send("motion", json!({ "occupancy": false }));
        let reqs = rig.wait(60);
        assert_eq!(last_auto(&reqs, "a").map(|t| t.on), Some(false));
        assert!(rig
            .script
            .take_published()
            .contains(&("scene".into(), json!("auto"))));
        let reqs = rig.send("motion", json!({ "occupancy": true }));
        assert_ne!(
            last_auto(&reqs, "a").unwrap().brightness,
            76,
            "back on the curve"
        );
    }

    #[test]
    fn night_scene_is_warm_and_unknown_scenes_are_ignored() {
        let mut rig = Rig::new(
            "sun_curve(); on_topic('x', function() light('a'):auto(curve_target('a')) end)",
        );
        rig.topic("lights/test/scene", json!("night"));
        let t = last_auto(&rig.topic("x", json!({})), "a").unwrap();
        assert_eq!((t.brightness, t.color_temp), (8, Some(454)));
        rig.topic("lights/test/scene", json!("disco"));
        let t = last_auto(&rig.topic("x", json!({})), "a").unwrap();
        assert_eq!(t.brightness, 8);
    }

    #[test]
    fn automatic_off_stops_switching_but_keeps_shaping() {
        let mut rig = Rig::new(MOTION_ROOM);
        rig.wait(0);
        rig.topic("lights/test/automatic", json!(false));
        let reqs = rig.send("motion", json!({ "occupancy": true }));
        assert_ne!(last_auto(&reqs, "a").map(|t| t.on), Some(true));
        assert_eq!(releases(&reqs), 0);

        let reqs = rig.topic("lights/test/automatic", json!(true));
        assert_eq!(
            last_auto(&reqs, "a").map(|t| t.on),
            Some(true),
            "catches up"
        );
    }

    #[test]
    fn room_and_house_release_free_every_bulb_and_end_the_scene() {
        for topic in ["lights/test/release", "lights/release"] {
            let mut rig = Rig::new(MOTION_ROOM);
            rig.wait(0);
            rig.topic("lights/test/scene", json!("bright"));
            let reqs = rig.topic(topic, json!("release"));
            assert_eq!(releases(&reqs), 2, "{topic}");
            assert!(rig
                .script
                .take_published()
                .contains(&("scene".into(), json!("auto"))));
        }
    }

    #[test]
    fn publish_reports_occupancy_and_rejects_bad_input() {
        let mut rig = Rig::new(MOTION_ROOM);
        assert!(rig
            .script
            .take_published()
            .contains(&("occupied".into(), json!(false))));
        rig.send("motion", json!({ "occupancy": true }));
        assert_eq!(
            rig.script.take_published(),
            [("occupied".into(), json!(true))]
        );

        let mut rig = Rig::new(
            r#"
            on_topic("x", function(p) publish(p, 1) end)
            on_topic("y", function() publish("ok", {}) end)
            "#,
        );
        rig.topic("x", json!("a/b"));
        rig.topic("y", json!({}));
        assert!(rig.script.take_published().is_empty());
    }

    fn auto_on(reqs: &[(String, Input)]) -> Vec<(&str, bool)> {
        reqs.iter()
            .filter_map(|(name, i)| match i {
                Input::Auto { target, .. } => Some((name.as_str(), target.on)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn handlers_get_the_z2m_payload_and_request_targets() {
        let mut rig = Rig::new(
            r#"
            on("door", function(p)
              light("a"):auto{ on = not p.contact, brightness = 120, transition = 0.4 }
            end)
            "#,
        );
        assert!(rig.script.topics().contains(&"zigbee2mqtt/door".to_owned()));
        let reqs = rig.send("door", json!({ "contact": false, "battery": 90 }));
        match &reqs[..] {
            [(
                name,
                Input::Auto {
                    target,
                    scale,
                    transition,
                },
            )] => {
                assert_eq!(name, "a");
                assert_eq!(
                    *target,
                    Target {
                        on: true,
                        brightness: 120,
                        color_temp: None
                    }
                );
                assert_eq!((*scale, *transition), (1.0, Duration::from_millis(400)));
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn json_null_and_missing_fields_are_nil() {
        let mut rig = Rig::new(
            r#"
            on("door", function(p)
              assert(p.contact == nil and p.missing == nil)
              light("a"):auto{ on = false }
            end)
            "#,
        );
        assert_eq!(
            auto_on(&rig.send("door", json!({ "contact": null }))),
            [("a", false)]
        );
    }

    #[test]
    fn timers_fire_on_the_fake_clock_and_can_be_cancelled() {
        let mut rig = Rig::new(
            r#"
            local t
            on("button", function(p)
              if p.action == "single" then
                light("a"):user{ brightness = 25 }
                if t then cancel(t) end
                t = after(300, function() light("a"):user{ on = false } end)
              elseif p.action == "double" and t then
                cancel(t); t = nil
              end
            end)
            "#,
        );
        rig.send("button", json!({ "action": "single" }));
        assert_eq!(
            rig.script.deadline(),
            Some(rig.now + Duration::from_secs(300))
        );
        assert!(rig.wait(299).is_empty());
        let reqs = rig.wait(1);
        assert!(matches!(&reqs[..], [(_, Input::User { target, .. })] if !target.on));
        assert_eq!(rig.script.deadline(), None);

        rig.send("button", json!({ "action": "single" }));
        rig.send("button", json!({ "action": "double" }));
        assert!(rig.wait(600).is_empty());
    }

    #[test]
    fn every_repeats_and_top_level_requests_go_out_on_the_first_tick() {
        let mut rig = Rig::new(
            r#"
            local function update() light("a"):auto{ brightness = sun.level{ min = 5 } } end
            update()
            every(30, update)
            "#,
        );
        assert_eq!(auto_on(&rig.wait(0)), [("a", true)]);
        assert!(rig.wait(29).is_empty());
        assert_eq!(rig.wait(1).len(), 1);
        assert_eq!(rig.wait(30).len(), 1);
    }

    #[test]
    fn a_failing_handler_drops_its_half_made_requests_and_keeps_running() {
        let mut rig = Rig::new(
            r#"
            on("door", function(p)
              light("a"):auto{ on = true }
              if p.contact then error("boom") end
              light("b"):auto{ on = true }
            end)
            "#,
        );
        assert!(rig.send("door", json!({ "contact": true })).is_empty());
        assert_eq!(rig.send("door", json!({ "contact": false })).len(), 2);
    }

    #[test]
    fn runaway_handlers_are_stopped() {
        let mut rig = Rig::new(r#"on("x", function() while true do end end)"#);
        assert!(rig.send("x", json!({})).is_empty());
    }

    #[test]
    fn sandbox_has_no_os_or_io() {
        let mut rig = Rig::new(
            r#"on("x", function() assert(os == nil and io == nil and require == nil and load); light("a"):auto{} end)"#,
        );
        assert_eq!(rig.send("x", json!({})).len(), 1);
    }

    #[test]
    fn mistakes_fail_at_load_time() {
        for source in [
            r#"light("nope")"#,
            r#"light("a"):auto{ brigthness = 3 }"#,
            r#"light("a"):auto{ brightness = 300 }"#,
            r#"every(0.1, function() end)"#,
            r#"this is not lua"#,
        ] {
            assert!(Rig::try_new(source).is_err(), "{source}");
        }
    }

    #[test]
    fn subscribing_after_load_is_an_error() {
        let mut rig =
            Rig::new(r#"on("x", function() on("y", function() end); light("a"):auto{} end)"#);
        assert!(rig.send("x", json!({})).is_empty());
        assert!(!rig.script.topics().contains(&"zigbee2mqtt/y".to_owned()));
    }

    #[test]
    fn state_reflects_the_arbiter() {
        let mut rig = Rig::new(
            r#"
            on("x", function()
              local s = light("a"):state()
              if s and s.mode == "held" and s.on then light("b"):user{ brightness = s.brightness } end
            end)
            "#,
        );
        assert!(rig.send("x", json!({})).is_empty());
        rig.script.bulb(
            "a",
            true,
            Target {
                on: true,
                brightness: 80,
                color_temp: None,
            },
        );
        let reqs = rig.send("x", json!({}));
        assert!(
            matches!(&reqs[..], [(b, Input::User { target, .. })] if b == "b" && target.brightness == 80)
        );
    }

    #[test]
    fn sun_and_clock() {
        let mut rig = Rig::new(
            r#"
            on("x", function()
              assert(math.abs(clock() - 13.1667) < 0.01, clock())
              assert(sun.daylight() > 0.95)
              assert(sun.level{ min = 5, max = 50 } > 120)
              assert(sun.ct{} < 260)
              light("a"):auto{}
            end)
            "#,
        );
        assert_eq!(rig.send("x", json!({})).len(), 1);
    }

    fn targets(reqs: &[(String, Input)]) -> Vec<(&str, &'static str, Target)> {
        reqs.iter()
            .filter_map(|(n, i)| match i {
                Input::Auto { target, .. } => Some((n.as_str(), "auto", *target)),
                Input::User { target, .. } => Some((n.as_str(), "user", *target)),
                _ => None,
            })
            .collect()
    }

    fn releases(reqs: &[(String, Input)]) -> usize {
        reqs.iter()
            .filter(|(_, i)| matches!(i, Input::Release { .. }))
            .count()
    }

    fn last_auto_on(reqs: &[(String, Input)], bulb: &str) -> Option<bool> {
        targets(reqs)
            .into_iter()
            .rev()
            .find(|(n, k, _)| *n == bulb && *k == "auto")
            .map(|(_, _, t)| t.on)
    }

    const MOTION_ROOM: &str = r#"
        follow{ when = occupancy{ sensors = { "motion" }, doors = { "door" }, hold = 60, door_hold = 30 }, fade = 20 }
    "#;

    #[test]
    fn occupancy_turns_on_with_motion_and_off_after_hold_and_fade() {
        let mut rig = Rig::new(MOTION_ROOM);
        assert_eq!(
            last_auto_on(&rig.wait(0), "a"),
            Some(false),
            "starts vacant"
        );

        let reqs = rig.send("motion", json!({ "occupancy": true }));
        assert_eq!(last_auto_on(&reqs, "a"), Some(true));
        assert_eq!(last_auto_on(&reqs, "b"), Some(true));
        assert!(
            matches!(reqs[0].1, Input::Auto { transition, .. } if transition == Duration::from_millis(400))
        );

        // Still there as long as the sensor says so, whatever the hold.
        assert_ne!(last_auto_on(&rig.wait(600), "a"), Some(false));

        rig.send("motion", json!({ "occupancy": false }));
        assert_ne!(last_auto_on(&rig.wait(59), "a"), Some(false));
        let reqs = rig.wait(1);
        assert_eq!(last_auto_on(&reqs, "a"), Some(false));
        assert_eq!(
            releases(&reqs),
            2,
            "a manual change lasts as long as the visit"
        );
        assert!(matches!(
            reqs.iter().find(|(_, i)| matches!(i, Input::Auto { .. })).unwrap().1,
            Input::Auto { transition, .. } if transition == Duration::from_secs(20)
        ));
    }

    #[test]
    fn presence_field_counts_like_occupancy_and_noise_is_ignored() {
        let mut rig = Rig::new(MOTION_ROOM);
        rig.wait(0);
        for p in [
            json!({ "battery": 90 }),
            json!("x"),
            json!({ "occupancy": "yes" }),
        ] {
            assert_eq!(last_auto_on(&rig.send("motion", p), "a"), None);
        }
        assert_eq!(
            last_auto_on(&rig.send("motion", json!({ "presence": true })), "a"),
            Some(true)
        );
    }

    #[test]
    fn door_opening_lights_the_room_until_a_sensor_takes_over() {
        let mut rig = Rig::new(MOTION_ROOM);
        rig.wait(0);
        assert_eq!(
            last_auto_on(&rig.send("door", json!({ "contact": true })), "a"),
            None,
            "closing says nothing"
        );
        assert_eq!(
            last_auto_on(&rig.send("door", json!({ "contact": false })), "a"),
            Some(true)
        );
        rig.wait(10);
        rig.send("motion", json!({ "occupancy": true }));
        // The door's window ends, but the sensor still sees someone.
        assert_ne!(last_auto_on(&rig.wait(60), "a"), Some(false));
        rig.send("motion", json!({ "occupancy": false }));
        assert_eq!(last_auto_on(&rig.wait(60), "a"), Some(false));
    }

    #[test]
    fn door_alone_times_out() {
        let mut rig = Rig::new(MOTION_ROOM);
        rig.wait(0);
        rig.send("door", json!({ "contact": false }));
        assert_eq!(last_auto_on(&rig.wait(30), "a"), Some(false));
    }

    const BATHROOM: &str = r#"
        follow{ when = occupancy{ sensors = { "p1", "p2" }, doors = { "door" }, hold = 30, door_hold = 60, close_grace = 3 }, fade = 20 }
    "#;

    const BEDROOM: &str = r#"
        follow{ wake = wake_ramp(), when = occupancy{ sensors = { "p" }, hold = 120 }, fade = 30, quiet = { 22, 8 } }
    "#;

    fn at(rig: &mut Rig, time: &str) {
        rig.wall = DateTime::parse_from_rfc3339(&format!("2026-06-21T{time}+02:00")).unwrap();
    }

    #[test]
    fn quiet_hours_block_arrival_but_not_lights_already_on() {
        let mut rig = Rig::new(BEDROOM);
        at(&mut rig, "23:00:00");
        rig.wait(0);
        assert_eq!(
            last_auto_on(&rig.send("p", json!({ "occupancy": true })), "a"),
            Some(false),
            "arriving at night"
        );
        assert_ne!(last_auto_on(&rig.wait(600), "a"), Some(true));

        rig.send("p", json!({ "occupancy": false }));
        rig.wait(121);
        at(&mut rig, "21:50:00");
        assert_eq!(
            last_auto_on(&rig.send("p", json!({ "occupancy": true })), "a"),
            Some(true),
            "arriving by day"
        );
        assert_eq!(
            last_auto_on(&rig.wait(20 * 60), "a"),
            Some(true),
            "stays on past 22:00"
        );

        rig.send("p", json!({ "occupancy": false }));
        assert_eq!(last_auto_on(&rig.wait(120), "a"), Some(false), "empty: off");
    }

    #[test]
    fn quiet_hours_ending_switch_nothing_on() {
        let mut rig = Rig::new(BEDROOM);
        at(&mut rig, "07:55:00");
        rig.wait(0);
        rig.send("p", json!({ "occupancy": true }));
        assert_ne!(last_auto_on(&rig.wait(600), "a"), Some(true));
    }

    #[test]
    fn wake_ramp_runs_inside_quiet_hours() {
        let mut rig = Rig::new(BEDROOM);
        at(&mut rig, "06:29:00");
        rig.wait(0);
        rig.send("p", json!({ "occupancy": true }));
        assert_eq!(last_auto_on(&rig.wait(5 * 60), "a"), Some(true));
    }

    #[test]
    fn door_shut_with_nobody_detected_empties_after_the_grace() {
        let mut rig = Rig::new(BATHROOM);
        rig.wait(0);
        rig.send("door", json!({ "contact": false }));
        rig.wait(5);
        rig.send("door", json!({ "contact": true }));
        assert_ne!(last_auto_on(&rig.wait(2), "a"), Some(false));
        assert_eq!(last_auto_on(&rig.wait(1), "a"), Some(false));
    }

    #[test]
    fn door_shut_on_someone_inside_keeps_the_light_until_both_sensors_clear() {
        let mut rig = Rig::new(BATHROOM);
        rig.wait(0);
        rig.send("door", json!({ "contact": false }));
        rig.send("p1", json!({ "occupancy": true }));
        rig.send("door", json!({ "contact": true }));
        rig.send("p2", json!({ "occupancy": true }));
        assert_ne!(last_auto_on(&rig.wait(600), "a"), Some(false));

        // One sensor losing you is not enough.
        rig.send("p1", json!({ "occupancy": false }));
        assert_ne!(last_auto_on(&rig.wait(600), "a"), Some(false));

        rig.send("p2", json!({ "occupancy": false }));
        assert_ne!(last_auto_on(&rig.wait(29), "a"), Some(false));
        assert_eq!(last_auto_on(&rig.wait(1), "a"), Some(false));
    }

    #[test]
    fn leaving_and_shutting_the_door_cuts_the_sensor_hold_short() {
        let mut rig = Rig::new(BATHROOM);
        rig.wait(0);
        rig.send("p1", json!({ "occupancy": true }));
        rig.send("p1", json!({ "occupancy": false }));
        rig.wait(1);
        rig.send("door", json!({ "contact": false }));
        rig.send("door", json!({ "contact": true }));
        assert_eq!(last_auto_on(&rig.wait(3), "a"), Some(false));
    }

    #[test]
    fn follow_without_occupancy_keeps_bulbs_as_they_are() {
        let mut rig = Rig::new("follow{}");
        let reqs = rig.wait(0);
        assert_eq!(
            last_auto_on(&reqs, "a"),
            Some(false),
            "unknown bulbs: off is the safe guess"
        );
        let on = Target {
            on: true,
            brightness: 200,
            color_temp: Some(300),
        };
        rig.script.bulb("a", false, on);
        let reqs = rig.wait(30);
        assert_eq!(
            last_auto_on(&reqs, "a"),
            Some(true),
            "on stays on, at the curve"
        );
        let (_, _, t) = targets(&reqs)
            .into_iter()
            .find(|(n, _, _)| *n == "a")
            .unwrap();
        assert!(t.color_temp.is_some() && t.brightness > 100, "{t:?}");
    }

    #[test]
    fn manual_off_in_a_follow_room_is_not_shown_as_held() {
        let mut rig = Rig::new("follow{}");
        rig.wait(0);
        let off = Target {
            on: false,
            brightness: 1,
            color_temp: None,
        };
        rig.script.bulb("a", true, off);
        assert_eq!(releases(&rig.wait(30)), 1);
    }

    #[test]
    fn ha_sliders_shape_the_curve() {
        let mut rig = Rig::new("follow{}");
        rig.wait(0);
        rig.script.bulb(
            "a",
            false,
            Target {
                on: true,
                brightness: 200,
                color_temp: None,
            },
        );
        let bri = |reqs: &[(String, Input)]| {
            targets(reqs)
                .into_iter()
                .find(|(n, _, _)| *n == "a")
                .unwrap()
                .2
                .brightness
        };
        let full = bri(&rig.wait(30));
        let topic = "mqtt-auto/sun-follow/dev_a/max-brightness";
        rig.script.message(topic, &json!(50), rig.now, rig.wall);
        assert!(bri(&rig.wait(30)) < full / 2 + 5);
        // HA sends numbers as strings too; garbage keeps the last value.
        rig.script.message(topic, &json!("20"), rig.now, rig.wall);
        let low = bri(&rig.wait(30));
        rig.script.message(topic, &json!("lots"), rig.now, rig.wall);
        assert_eq!(bri(&rig.wait(30)), low);
        assert!(low <= 51);

        rig.script.message(
            "mqtt-auto/color-temp-cycle/enabled",
            &json!("false"),
            rig.now,
            rig.wall,
        );
        let reqs = rig.wait(30);
        assert_eq!(targets(&reqs)[0].2.color_temp, None);
    }

    const HELD_OFF: Target = Target {
        on: false,
        brightness: 1,
        color_temp: None,
    };
    const HELD_ON: Target = Target {
        on: true,
        brightness: 254,
        color_temp: None,
    };

    #[test]
    fn arrival_releases_a_bulb_held_off_but_keeps_one_held_on() {
        let mut rig = Rig::new(MOTION_ROOM);
        rig.wait(0);
        // Held while the room was empty: off on the way out, and on at
        // the wall switch.
        rig.script.bulb("a", true, HELD_OFF);
        rig.script.bulb("b", true, HELD_ON);
        let reqs = rig.send("motion", json!({ "occupancy": true }));
        let released: Vec<_> = reqs
            .iter()
            .filter(|(_, i)| matches!(i, Input::Release { .. }))
            .map(|(n, _)| n.as_str())
            .collect();
        assert_eq!(released, ["a"]);
        assert_eq!(last_auto_on(&reqs, "a"), Some(true));
    }

    #[test]
    fn a_manual_off_during_the_wake_ramp_survives_the_room_emptying() {
        let mut rig = Rig::new(BEDROOM);
        at(&mut rig, "06:40:00");
        rig.wait(0);
        rig.send("p", json!({ "occupancy": true }));
        rig.script.bulb("a", true, HELD_OFF);
        rig.send("p", json!({ "occupancy": false }));
        let reqs = rig.wait(121);
        assert_eq!(releases(&reqs), 0, "vacancy during the ramp");
        let reqs = rig.send("p", json!({ "occupancy": true }));
        assert_eq!(releases(&reqs), 0, "arrival during the ramp");
    }

    #[test]
    fn wake_ramp_switches_on_dim_and_releases_a_night_off() {
        let mut rig = Rig::new("follow{ wake = wake_ramp() }");
        rig.wall = DateTime::parse_from_rfc3339("2026-06-21T06:29:00+02:00").unwrap();
        assert_eq!(last_auto_on(&rig.wait(0), "a"), Some(false));
        rig.script.bulb(
            "a",
            true,
            Target {
                on: false,
                brightness: 1,
                color_temp: None,
            },
        );
        let reqs = rig.wait(30);
        assert_eq!(
            releases(&reqs),
            1,
            "follow without occupancy releases an off hold"
        );

        rig.script.bulb(
            "a",
            true,
            Target {
                on: false,
                brightness: 1,
                color_temp: None,
            },
        );
        let reqs = rig.wait(30 + 10 * 60);
        assert_eq!(last_auto_on(&reqs, "a"), Some(true));
        assert!(releases(&reqs) >= 2, "ramp start releases every bulb");
        let early = targets(&reqs)[0].2.brightness;
        let later = targets(&rig.wait(20 * 60))
            .into_iter()
            .find(|(n, _, _)| *n == "a")
            .unwrap()
            .2
            .brightness;
        assert!(
            early < later && later <= 77,
            "{early} -> {later}, capped at 30%"
        );

        // Ramp over: held where it ended, not jumped to the curve.
        let end = Target {
            on: true,
            brightness: 77,
            color_temp: Some(400),
        };
        rig.script.bulb("a", false, end);
        let reqs = rig.wait(20 * 60);
        assert!(
            targets(&reqs)
                .iter()
                .any(|(n, k, t)| *n == "a" && *k == "user" && t.brightness == 77),
            "{reqs:?}"
        );
    }

    #[test]
    fn sun_switch_flips_once_per_crossing_and_releases() {
        let mut rig = Rig::new(r#"sun_switch{ lights = { "a" } }"#);
        assert_eq!(last_auto_on(&rig.wait(0), "a"), Some(true), "noon: bright");
        rig.script.message(
            "mqtt-auto/sun-follow/dev_a/invert",
            &json!("true"),
            rig.now,
            rig.wall,
        );
        let reqs = rig.wait(30);
        assert_eq!(last_auto_on(&reqs, "a"), Some(false));
        assert_eq!(releases(&reqs), 1);
        assert_eq!(releases(&rig.wait(30)), 0);
    }

    #[test]
    fn buttons_toggle_at_the_curve() {
        let mut rig = Rig::new(
            r#"
            follow{}
            button("btn", { single = toggle(), double = toggle{ "b" } })
            "#,
        );
        rig.wait(0);
        let reqs = rig.script.message(
            "zigbee2mqtt/btn/action",
            &json!("single"),
            rig.now,
            rig.wall,
        );
        let t = targets(&reqs);
        assert_eq!(t.len(), 2);
        assert!(t
            .iter()
            .all(|(_, k, t)| *k == "user" && t.on && t.color_temp.is_some()));

        rig.script.bulb(
            "b",
            false,
            Target {
                on: true,
                brightness: 200,
                color_temp: None,
            },
        );
        let reqs = rig.script.message(
            "zigbee2mqtt/btn/action",
            &json!({ "action": "double" }),
            rig.now,
            rig.wall,
        );
        assert!(matches!(&targets(&reqs)[..], [("b", "user", t)] if !t.on));
        assert!(rig
            .script
            .message(
                "zigbee2mqtt/btn/action",
                &json!({ "action": "triple" }),
                rig.now,
                rig.wall
            )
            .is_empty());
    }
}
