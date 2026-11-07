//! A room's Lua file, evaluated once into a [`Spec`]: its states, how each
//! light looks in them, and what moves the room between them. Lua keeps
//! only the small functions a spec may contain (look values, `test`
//! conditions, triggers), which [`crate::room`] calls with a read-only
//! context. The file format is documented at the top of `prelude.lua`.
//!
//! Globals besides the prelude's (durations in seconds, brightness 1-254,
//! colour temperature in mireds):
//!   - `lights`: `{ <name> = { device, dimmable } }`, the room's bulbs.
//!   - `setting(topic, default)` -> a getter for a retained value HA sets,
//!     parsed as the default's type. Top level only.
//!   - `sun.level{ min, max, gamma, invert }` -> brightness for now,
//!     `sun.ct{ warm, cool }` -> mireds, `sun.daylight()` -> 0..1.
//!   - `clock()` -> local time of day in hours (13.5 = 13:30).
//!   - `log(...)`.
//!
//! Errors while loading (including any spec function failing on a first
//! dry run) fail startup and `lights --check`; at runtime they are logged
//! and that light or condition is skipped.

use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;

use anyhow::{anyhow, bail, Context as _, Result};
use chrono::{DateTime, FixedOffset, Timelike};
use mlua::{
    Function, HookTriggers, Lua, LuaOptions, LuaSerdeExt, RegistryKey, StdLib, Table, Value,
    Variadic, VmState,
};
use serde::Serialize;

use crate::arbiter::Target;
use crate::{curves, sun};

/// One spec function may run this long before it is stopped.
const CALL_BUDGET: Duration = Duration::from_millis(200);
const MEMORY_LIMIT: usize = 32 << 20;

const SETTINGS: &str = "settings";
const ROOM: &str = "room";

/// Helpers loaded ahead of every room file (`room`, `sunlight`, ...).
const PRELUDE: &str = include_str!("prelude.lua");

const LOOK_KEYS: [&str; 4] = ["on", "brightness", "color_temp", "transition"];
const ROW_KEYS: [&str; 9] = [
    "to",
    "toggle",
    "announce",
    "house",
    "present",
    "absent_for",
    "time_in_state",
    "between",
    "outside",
];
/// Rows may also carry `test`; listed apart so ROW_KEYS stays the data part.
const ROW_TEST: &str = "test";
const ROOM_KEYS: [&str; 8] = [
    "presence",
    "doors",
    "buttons",
    "triggers",
    "default",
    "start",
    "forget_after",
    "states",
];

/// A Lua function or table kept alive in the registry.
pub struct Func(RegistryKey);

/// A room, as its file declares it.
pub struct Spec {
    /// z2m devices reporting `occupancy` or `presence`.
    pub presence: Vec<String>,
    /// (name, z2m contact device): events `<name>.open` / `<name>.closed`.
    pub doors: Vec<(String, String)>,
    /// (name, z2m device): events `<name>.<action>`.
    pub buttons: Vec<(String, String)>,
    /// (name, predicate): event `<name>` when the predicate turns true.
    pub triggers: Vec<(String, Func)>,
    pub default: usize,
    pub start: usize,
    pub forget_after: Duration,
    /// Sorted by name; indices are state ids.
    pub states: Vec<State>,
}

pub struct State {
    pub name: String,
    /// A phase, not a mode: not offered in HA, never remembered.
    pub hidden: bool,
    look: Option<Func>,
    per_light: Option<Func>,
    /// Event -> rows; the first whose condition holds is taken.
    pub on: BTreeMap<String, Vec<Row>>,
    /// Checked after every event and tick; the first that holds is taken.
    pub when: Vec<Row>,
}

/// At least one of `go` and `announce`.
pub struct Row {
    pub go: Option<Go>,
    /// A house mode to tell every room about (event `house.<name>`).
    pub announce: Option<String>,
    pub cond: Cond,
}

pub enum Go {
    State(usize),
    /// The mode the room left last, within `forget_after`; else `default`.
    Resume,
    /// A person's toggle of these bulbs (indices): any on -> all off, else
    /// all on as the state looks.
    Toggle(Vec<usize>),
}

/// All set fields must hold.
#[derive(Default)]
pub struct Cond {
    /// The house mode last announced.
    pub house: Option<String>,
    pub present: Option<bool>,
    pub absent_for: Option<Duration>,
    pub time_in_state: Option<Duration>,
    /// Hours `[from, to)`, wrapping past midnight.
    pub between: Option<(f64, f64)>,
    pub outside: Option<(f64, f64)>,
    pub test: Option<Func>,
}

/// One light's look in a state. `transition` applies on entering it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Look {
    pub target: Target,
    pub transition: Option<Duration>,
}

/// What spec functions see, as their one argument `c`.
#[derive(Serialize)]
pub struct Ctx<'a> {
    pub light: Option<&'a str>,
    pub state: &'a str,
    pub house: Option<&'a str>,
    pub present: bool,
    pub present_for: f64,
    pub absent_for: f64,
    pub time_in_state: f64,
    pub clock: f64,
}

#[derive(Clone, Copy)]
enum Kind {
    Number,
    Bool,
    Text,
}

struct Env {
    latitude: f64,
    longitude: f64,
    wall: DateTime<FixedOffset>,
    settings: BTreeMap<String, Kind>,
    loaded: bool,
}

/// Real-time cutoff for the running call, checked by the instruction hook.
struct CallDeadline(std::time::Instant);

pub struct Script {
    lua: Lua,
    room: String,
}

impl Script {
    /// `lights`: the room's bulbs as (name, z2m device, dimmable), in the
    /// order the room indexes them.
    pub fn load(
        room: &str,
        source: &str,
        lights: &[(String, String, bool)],
        (latitude, longitude): (f64, f64),
        wall: DateTime<FixedOffset>,
    ) -> Result<(Self, Spec)> {
        let lua = Lua::new_with(
            StdLib::STRING | StdLib::TABLE | StdLib::MATH | StdLib::UTF8,
            LuaOptions::default(),
        )
        .map_err(lua_err)?;
        lua.set_memory_limit(MEMORY_LIMIT).map_err(lua_err)?;
        lua.set_app_data(Env {
            latitude,
            longitude,
            wall,
            settings: BTreeMap::new(),
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
        install(&lua, lights).map_err(lua_err)?;

        let script = Self {
            lua,
            room: room.to_owned(),
        };
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
        script.env().loaded = true;

        let names: Vec<&str> = lights.iter().map(|(n, _, _)| n.as_str()).collect();
        let spec = script
            .parse(&names)
            .with_context(|| format!("room {room}"))?;
        script
            .dry_run(&spec, &names)
            .with_context(|| format!("room {room}"))?;
        Ok((script, spec))
    }

    /// Topics of the settings the file reads.
    pub fn topics(&self) -> Vec<String> {
        self.env().settings.keys().cloned().collect()
    }

    /// A message on a setting's topic. Payloads that don't parse as the
    /// setting's type are ignored.
    pub fn setting(&self, topic: &str, payload: &serde_json::Value) {
        let Some(kind) = self.env().settings.get(topic).copied() else {
            return;
        };
        let text = payload.as_str();
        let value = match kind {
            Kind::Number => payload
                .as_f64()
                .or_else(|| text.and_then(|s| s.trim().parse().ok()))
                .map(Value::Number),
            Kind::Bool => match (payload.as_bool(), text) {
                (Some(b), _) => Some(b),
                (_, Some("true" | "on" | "ON")) => Some(true),
                (_, Some("false" | "off" | "OFF")) => Some(false),
                _ => None,
            }
            .map(Value::Boolean),
            Kind::Text => text.and_then(|s| self.lua.create_string(s).ok().map(Value::String)),
        };
        let Some(value) = value else {
            self.log(&format!("{topic}: ignoring {payload}"));
            return;
        };
        if let Err(e) = self
            .lua
            .named_registry_value::<Table>(SETTINGS)
            .and_then(|t| t.set(topic, value))
        {
            self.log(&format!("{topic}: {e}"));
        }
    }

    pub fn set_clock(&self, wall: DateTime<FixedOffset>) {
        self.env().wall = wall;
    }

    /// `light`'s look in `state`, or `None` if the state leaves it alone.
    pub fn look(&self, state: &State, light: &str, ctx: &Ctx) -> Result<Option<Look>> {
        let look: Option<Table> = state.look.as_ref().map(|f| self.get(f)).transpose()?;
        let own: Option<Table> = match &state.per_light {
            Some(f) => self.get::<Table>(f)?.get(light).map_err(lua_err)?,
            None => None,
        };
        if look.is_none() && own.is_none() {
            return Ok(None);
        }
        let ctx = self.ctx(ctx)?;
        let field = |key: &str| -> Result<Value> {
            for t in [&own, &look].into_iter().flatten() {
                let v: Value = t.get(key).map_err(lua_err)?;
                if !v.is_nil() {
                    return self.value(v, &ctx).with_context(|| format!("look.{key}"));
                }
            }
            Ok(Value::Nil)
        };
        let number = |key: &str, lo: f64, hi: f64| -> Result<Option<f64>> {
            match field(key)? {
                Value::Nil => Ok(None),
                Value::Integer(i) => Ok(Some((i as f64).clamp(lo, hi))),
                Value::Number(n) if n.is_finite() => Ok(Some(n.clamp(lo, hi))),
                v => bail!("{key} must be a number, got {}", v.type_name()),
            }
        };
        let on = match field("on")? {
            Value::Nil => true,
            Value::Boolean(b) => b,
            v => bail!("on must be a boolean, got {}", v.type_name()),
        };
        let brightness =
            number("brightness", 1.0, 254.0)?.map_or(Target::FULL, |b| b.round() as u8);
        let color_temp = number("color_temp", 100.0, 1000.0)?.map(|c| c.round() as u16);
        let transition = number("transition", 0.0, 3600.0)?.map(Duration::from_secs_f64);
        Ok(Some(Look {
            target: Target {
                on,
                brightness,
                color_temp,
            },
            transition,
        }))
    }

    /// Run a `test` or trigger predicate.
    pub fn test(&self, f: &Func, ctx: &Ctx) -> Result<bool> {
        let f: Function = self.get(f)?;
        let ctx = self.ctx(ctx)?;
        self.budget();
        let v: Value = f.call(ctx).map_err(lua_err)?;
        Ok(!matches!(v, Value::Nil | Value::Boolean(false)))
    }

    fn value(&self, v: Value, ctx: &Table) -> Result<Value> {
        match v {
            Value::Function(f) => {
                self.budget();
                f.call(ctx.clone()).map_err(lua_err)
            }
            v => Ok(v),
        }
    }

    fn ctx(&self, ctx: &Ctx) -> Result<Table> {
        match self.lua.to_value(ctx).map_err(lua_err)? {
            Value::Table(t) => Ok(t),
            _ => bail!("context is not a table"),
        }
    }

    fn get<T: mlua::FromLua>(&self, f: &Func) -> Result<T> {
        self.lua.registry_value(&f.0).map_err(lua_err)
    }

    fn keep(&self, v: impl mlua::IntoLua) -> Result<Func> {
        Ok(Func(self.lua.create_registry_value(v).map_err(lua_err)?))
    }

    fn parse(&self, lights: &[&str]) -> Result<Spec> {
        let t: Table = self
            .lua
            .named_registry_value(ROOM)
            .map_err(|_| anyhow!("the file never calls room{{}}"))?;
        check_keys(&t, &ROOM_KEYS, "room{}")?;

        let presence: Vec<String> = list(&t, "presence")?;
        let doors = named(&t, "doors")?;
        let buttons = named(&t, "buttons")?;
        let mut triggers = Vec::new();
        if let Some(tt) = t.get::<Option<Table>>("triggers").map_err(lua_err)? {
            for pair in tt.pairs::<String, Function>() {
                let (name, f) = pair.map_err(|e| anyhow!("triggers: {e}"))?;
                triggers.push((name, self.keep(f)?));
            }
        }
        triggers.sort_by(|a, b| a.0.cmp(&b.0));

        let states_t: Table = t
            .get::<Option<Table>>("states")
            .map_err(lua_err)?
            .ok_or_else(|| anyhow!("room{{}} has no states"))?;
        let mut names: Vec<String> = states_t
            .pairs::<String, Value>()
            .map(|p| p.map(|(k, _)| k).map_err(lua_err))
            .collect::<Result<_>>()?;
        names.sort();
        let index = |name: &str| -> Result<usize> {
            names
                .iter()
                .position(|n| n == name)
                .ok_or_else(|| anyhow!("no state {name:?}"))
        };

        let mut events: BTreeSet<String> = BTreeSet::new();
        if !presence.is_empty() {
            events.extend(["present".into(), "absent".into()]);
        }
        for (d, _) in &doors {
            events.extend([format!("{d}.open"), format!("{d}.closed")]);
        }
        events.extend(triggers.iter().map(|(n, _)| n.clone()));
        let known_event = |e: &str| {
            events.contains(e)
                || e.strip_prefix("house.").is_some_and(|n| !n.is_empty())
                || buttons.iter().any(|(b, _)| {
                    e.strip_prefix(b.as_str())
                        .is_some_and(|a| a.len() > 1 && a.starts_with('.'))
                })
        };

        let mut states = Vec::new();
        for name in &names {
            let s: Table = states_t.get(name.as_str()).map_err(lua_err)?;
            let state = self
                .state(name, &s, &index, lights, &known_event)
                .with_context(|| format!("state {name}"))?;
            states.push(state);
        }

        let default_name: String = t
            .get::<Option<String>>("default")
            .map_err(lua_err)?
            .ok_or_else(|| anyhow!("room{{}} needs a default state"))?;
        let default = index(&default_name)?;
        let start = match t.get::<Option<String>>("start").map_err(lua_err)? {
            Some(s) => index(&s)?,
            None => default,
        };
        if states[default].hidden {
            bail!("the default state {default_name:?} is hidden");
        }
        let forget_after = secs(t.get("forget_after").map_err(lua_err)?, "forget_after")?
            .unwrap_or(Duration::from_secs(3600));
        Ok(Spec {
            presence,
            doors,
            buttons,
            triggers,
            default,
            start,
            forget_after,
            states,
        })
    }

    fn state(
        &self,
        name: &str,
        s: &Table,
        index: &dyn Fn(&str) -> Result<usize>,
        lights: &[&str],
        known_event: &dyn Fn(&str) -> bool,
    ) -> Result<State> {
        let look: Option<Table> = s.get("look").map_err(lua_err)?;
        if let Some(l) = &look {
            check_keys(l, &LOOK_KEYS, "look")?;
        }
        let per_light: Option<Table> = s.get("per_light").map_err(lua_err)?;
        if let Some(p) = &per_light {
            for pair in p.pairs::<String, Table>() {
                let (light, l) = pair.map_err(|e| anyhow!("per_light: {e}"))?;
                if !lights.contains(&light.as_str()) {
                    bail!("per_light: no light {light:?} in this room");
                }
                check_keys(&l, &LOOK_KEYS, &format!("per_light.{light}"))?;
            }
        }
        let mut on = BTreeMap::new();
        if let Some(t) = s.get::<Option<Table>>("on").map_err(lua_err)? {
            for pair in t.pairs::<String, Value>() {
                let (event, v) = pair.map_err(|e| anyhow!("on: {e}"))?;
                if !known_event(&event) {
                    bail!("on: no event {event:?} (declare its sensor, door, button or trigger)");
                }
                let rows = self
                    .rows(v, index, lights)
                    .with_context(|| format!("on[{event:?}]"))?;
                on.insert(event, rows);
            }
        }
        let when = match s.get::<Value>("when").map_err(lua_err)? {
            Value::Nil => Vec::new(),
            v => self.rows(v, index, lights).context("when")?,
        };
        // Checked all the time, so anything but a move would repeat forever.
        if when
            .iter()
            .any(|r| r.announce.is_some() || !matches!(r.go, Some(Go::State(_) | Go::Resume)))
        {
            bail!("when: rows can only `to` a state (toggles and announces belong in `on`)");
        }
        Ok(State {
            name: name.to_owned(),
            hidden: s
                .get::<Option<bool>>("hidden")
                .map_err(lua_err)?
                .unwrap_or(false),
            look: look.map(|t| self.keep(t)).transpose()?,
            per_light: per_light.map(|t| self.keep(t)).transpose()?,
            on,
            when,
        })
    }

    /// A state name, one row table, or a list of rows.
    fn rows(
        &self,
        v: Value,
        index: &dyn Fn(&str) -> Result<usize>,
        lights: &[&str],
    ) -> Result<Vec<Row>> {
        match v {
            Value::String(s) => Ok(vec![Row {
                go: Some(go(&s.to_str().map_err(lua_err)?, index)?),
                announce: None,
                cond: Cond::default(),
            }]),
            Value::Table(t)
                if ["to", "toggle", "announce"]
                    .iter()
                    .any(|k| t.contains_key(*k).unwrap_or(false)) =>
            {
                Ok(vec![self.row(&t, index, lights)?])
            }
            Value::Table(t) => t
                .sequence_values::<Table>()
                .enumerate()
                .map(|(i, r)| {
                    self.row(&r.map_err(lua_err)?, index, lights)
                        .with_context(|| format!("row {}", i + 1))
                })
                .collect(),
            v => bail!("expected a state name or rows, got {}", v.type_name()),
        }
    }

    fn row(
        &self,
        t: &Table,
        index: &dyn Fn(&str) -> Result<usize>,
        lights: &[&str],
    ) -> Result<Row> {
        let mut allowed = ROW_KEYS.to_vec();
        allowed.push(ROW_TEST);
        check_keys(t, &allowed, "row")?;
        let to: Option<String> = t.get("to").map_err(lua_err)?;
        let toggle: Option<Vec<String>> = t.get("toggle").map_err(lua_err)?;
        let announce: Option<String> = t.get("announce").map_err(lua_err)?;
        let go = match (to, toggle) {
            (Some(to), None) => Some(go(&to, index)?),
            (None, Some(names)) => Some(Go::Toggle(
                names
                    .iter()
                    .map(|n| {
                        lights
                            .iter()
                            .position(|l| l == n)
                            .ok_or_else(|| anyhow!("toggle: no light {n:?} in this room"))
                    })
                    .collect::<Result<_>>()?,
            )),
            (None, None) if announce.is_some() => None,
            _ => bail!("a row needs one of `to` and `toggle`, or an `announce`"),
        };
        if announce.as_deref() == Some("") {
            bail!("announce needs a name");
        }
        let hours = |key: &str| -> Result<Option<(f64, f64)>> {
            let v: Option<Vec<f64>> = t.get(key).map_err(lua_err)?;
            match v.as_deref() {
                None => Ok(None),
                Some(&[from, to]) if (0.0..=24.0).contains(&from) && (0.0..=24.0).contains(&to) => {
                    Ok(Some((from, to)))
                }
                Some(_) => bail!("{key} must be {{ from_hour, to_hour }}"),
            }
        };
        let test: Option<Function> = t.get(ROW_TEST).map_err(lua_err)?;
        Ok(Row {
            go,
            announce,
            cond: Cond {
                house: t.get("house").map_err(lua_err)?,
                present: t.get("present").map_err(lua_err)?,
                absent_for: secs(t.get("absent_for").map_err(lua_err)?, "absent_for")?,
                time_in_state: secs(t.get("time_in_state").map_err(lua_err)?, "time_in_state")?,
                between: hours("between")?,
                outside: hours("outside")?,
                test: test.map(|f| self.keep(f)).transpose()?,
            },
        })
    }

    /// Call every spec function once, so a typo fails the build, not the
    /// first evening.
    fn dry_run(&self, spec: &Spec, lights: &[&str]) -> Result<()> {
        for state in &spec.states {
            let ctx = |light| Ctx {
                light,
                state: &state.name,
                house: None,
                present: false,
                present_for: 0.0,
                absent_for: 0.0,
                time_in_state: 0.0,
                clock: 12.0,
            };
            for light in lights {
                self.look(state, light, &ctx(Some(light)))
                    .with_context(|| format!("state {}, light {light}", state.name))?;
            }
            let rows = state.on.values().flatten().chain(&state.when);
            for f in rows.filter_map(|r| r.cond.test.as_ref()) {
                self.test(f, &ctx(None))
                    .with_context(|| format!("state {}: test", state.name))?;
            }
        }
        for (name, f) in &spec.triggers {
            let ctx = Ctx {
                light: None,
                state: &spec.states[spec.start].name,
                house: None,
                present: false,
                present_for: 0.0,
                absent_for: 0.0,
                time_in_state: 0.0,
                clock: 12.0,
            };
            self.test(f, &ctx)
                .with_context(|| format!("trigger {name}"))?;
        }
        Ok(())
    }

    fn budget(&self) {
        self.lua
            .set_app_data(CallDeadline(std::time::Instant::now() + CALL_BUDGET));
    }

    pub fn log(&self, msg: &str) {
        eprintln!("{}: {msg}", self.room);
    }

    fn env(&self) -> mlua::AppDataRefMut<'_, Env> {
        self.lua
            .app_data_mut::<Env>()
            .expect("env is installed in load")
    }
}

fn go(name: &str, index: &dyn Fn(&str) -> Result<usize>) -> Result<Go> {
    if name == "resume" {
        Ok(Go::Resume)
    } else {
        Ok(Go::State(index(name)?))
    }
}

fn check_keys(t: &Table, allowed: &[&str], what: &str) -> Result<()> {
    for pair in t.pairs::<Value, Value>() {
        let (key, _) = pair.map_err(lua_err)?;
        let key = key.to_string().map_err(lua_err)?;
        if !allowed.contains(&key.as_str()) {
            bail!(
                "{what}: unknown key {key:?} (expected one of {})",
                allowed.join(", ")
            );
        }
    }
    Ok(())
}

fn list(t: &Table, key: &str) -> Result<Vec<String>> {
    Ok(t.get::<Option<Vec<String>>>(key)
        .map_err(|e| anyhow!("{key}: {e}"))?
        .unwrap_or_default())
}

fn named(t: &Table, key: &str) -> Result<Vec<(String, String)>> {
    let m: Option<BTreeMap<String, String>> = t.get(key).map_err(|e| anyhow!("{key}: {e}"))?;
    Ok(m.unwrap_or_default().into_iter().collect())
}

fn secs(v: Option<f64>, what: &str) -> Result<Option<Duration>> {
    v.map(|s| Duration::try_from_secs_f64(s).map_err(|_| anyhow!("{what}: bad duration {s}")))
        .transpose()
}

/// mlua errors aren't `Send`; keep the message.
fn lua_err(e: mlua::Error) -> anyhow::Error {
    anyhow!("{e}")
}

fn env(lua: &Lua) -> mlua::Result<mlua::AppDataRefMut<'_, Env>> {
    lua.app_data_mut::<Env>()
        .ok_or_else(|| mlua::Error::runtime("room env missing"))
}

fn install(lua: &Lua, lights: &[(String, String, bool)]) -> mlua::Result<()> {
    lua.set_named_registry_value(SETTINGS, lua.create_table()?)?;
    let g = lua.globals();

    g.set(
        "__room",
        lua.create_function(|lua, t: Table| {
            if lua.named_registry_value::<Option<Table>>(ROOM)?.is_some() {
                return Err(mlua::Error::runtime("room{} is called more than once"));
            }
            lua.set_named_registry_value(ROOM, t)
        })?,
    )?;

    let ls = lua.create_table()?;
    for (name, device, dimmable) in lights {
        let l = lua.create_table()?;
        l.set("device", device.as_str())?;
        l.set("dimmable", *dimmable)?;
        ls.set(name.as_str(), l)?;
    }
    g.set("lights", ls)?;

    g.set(
        "setting",
        lua.create_function(|lua, (topic, default): (String, Value)| {
            let kind = match default {
                Value::Integer(_) | Value::Number(_) => Kind::Number,
                Value::Boolean(_) => Kind::Bool,
                Value::String(_) => Kind::Text,
                _ => {
                    return Err(mlua::Error::runtime(
                        "setting() default must be a number, boolean or string",
                    ))
                }
            };
            {
                let mut e = env(lua)?;
                if e.loaded {
                    return Err(mlua::Error::runtime(
                        "setting() only works at the top level",
                    ));
                }
                e.settings.insert(topic.clone(), kind);
            }
            let values: Table = lua.named_registry_value(SETTINGS)?;
            if values.get::<Value>(topic.as_str())?.is_nil() {
                values.set(topic.as_str(), default)?;
            }
            lua.create_function(move |lua, ()| {
                lua.named_registry_value::<Table>(SETTINGS)?
                    .get::<Value>(topic.as_str())
            })
        })?,
    )?;

    let sun_table = lua.create_table()?;
    sun_table.set(
        "level",
        lua.create_function(|lua, opts: Option<Table>| {
            let get = |k: &str| -> mlua::Result<Option<f64>> {
                opts.as_ref().map_or(Ok(None), |t| t.get(k))
            };
            if let Some(t) = &opts {
                for pair in t.pairs::<String, Value>() {
                    let (k, _) = pair?;
                    if !["min", "max", "gamma", "invert"].contains(&k.as_str()) {
                        return Err(mlua::Error::runtime(format!(
                            "sun.level: unknown option {k:?}"
                        )));
                    }
                }
            }
            let pct = |k| -> mlua::Result<Option<u8>> {
                Ok(get(k)?.map(|v| v.clamp(0.0, 100.0).round() as u8))
            };
            let (min, max) = (pct("min")?.unwrap_or(1), pct("max")?.unwrap_or(100));
            let gamma = get("gamma")?.unwrap_or(1.0).clamp(0.1, 10.0);
            let invert: bool = opts
                .as_ref()
                .map_or(Ok(None), |t| t.get("invert"))?
                .unwrap_or(false);
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
            let get = |k: &str, d: f64| -> mlua::Result<u16> {
                let v: Option<f64> = opts.as_ref().map_or(Ok(None), |t| t.get(k))?;
                Ok(v.unwrap_or(d).clamp(100.0, 1000.0) as u16)
            };
            let (warm, cool) = (get("warm", 454.0)?, get("cool", 250.0)?);
            let e = env(lua)?;
            let progress = sun::day_progress(e.latitude, e.longitude, e.wall);
            Ok(curves::color_temp(progress, warm, cool))
        })?,
    )?;
    sun_table.set("daylight", lua.create_function(|lua, ()| daylight(lua))?)?;
    g.set("sun", sun_table)?;

    g.set(
        "clock",
        lua.create_function(|lua, ()| {
            let t = env(lua)?.wall.time();
            Ok(f64::from(t.num_seconds_from_midnight()) / 3600.0)
        })?,
    )?;
    g.set(
        "log",
        lua.create_function(|_, args: Variadic<Value>| {
            let parts: Vec<String> = args
                .iter()
                .map(|v| v.to_string().unwrap_or_else(|_| format!("{v:?}")))
                .collect();
            eprintln!("{}", parts.join(" "));
            Ok(())
        })?,
    )?;
    Ok(())
}

fn daylight(lua: &Lua) -> mlua::Result<f64> {
    let e = env(lua)?;
    Ok(sun::daylight_fraction(e.latitude, e.longitude, e.wall))
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOON: &str = "2026-06-21T13:10:00+02:00";

    fn load(src: &str) -> Result<(Script, Spec)> {
        let lights = [
            ("a".to_owned(), "dev_a".to_owned(), true),
            ("plug".to_owned(), "dev_plug".to_owned(), false),
        ];
        Script::load(
            "test",
            src,
            &lights,
            (52.52, 13.405),
            DateTime::parse_from_rfc3339(NOON).unwrap(),
        )
    }

    fn ctx<'a>(light: &'a str, state: &'a str) -> Ctx<'a> {
        Ctx {
            light: Some(light),
            state,
            house: None,
            present: true,
            present_for: 0.0,
            absent_for: 0.0,
            time_in_state: 0.0,
            clock: 13.0,
        }
    }

    #[test]
    fn per_light_overrides_look_and_functions_get_the_light() {
        let (script, spec) = load(
            r#"room{ default = "on", states = { on = {
                look = { brightness = function(c) return c.light == "a" and 100 or 1 end, transition = 2 },
                per_light = { plug = { on = false } },
            } } }"#,
        )
        .unwrap();
        let on = &spec.states[spec.default];
        let a = script.look(on, "a", &ctx("a", "on")).unwrap().unwrap();
        assert_eq!(a.target.brightness, 100);
        assert_eq!(a.transition, Some(Duration::from_secs(2)));
        let plug = script
            .look(on, "plug", &ctx("plug", "on"))
            .unwrap()
            .unwrap();
        assert!(!plug.target.on);
    }

    #[test]
    fn a_state_without_look_is_hands_off_and_manual_always_exists() {
        let (script, spec) =
            load(r#"room{ default = "on", states = { on = { look = {} } } }"#).unwrap();
        let manual = spec.states.iter().find(|s| s.name == "manual").unwrap();
        assert_eq!(script.look(manual, "a", &ctx("a", "manual")).unwrap(), None);
    }

    #[test]
    fn extends_merges_look_fields_and_prepends_when_rows() {
        let (script, spec) = load(
            r#"room{ presence = { "s" }, default = "on", states = {
                on = { look = { brightness = 50, color_temp = 300 }, when = { { to = "on", absent_for = 9 } } },
                dim = { extends = "on", look = { brightness = 5 }, when = { { to = "on", time_in_state = 1 } } },
            } }"#,
        )
        .unwrap();
        let dim = spec.states.iter().find(|s| s.name == "dim").unwrap();
        let l = script.look(dim, "a", &ctx("a", "dim")).unwrap().unwrap();
        assert_eq!((l.target.brightness, l.target.color_temp), (5, Some(300)));
        assert_eq!(dim.when.len(), 2);
        assert!(dim.when[0].cond.time_in_state.is_some());
    }

    #[test]
    fn mistakes_fail_loading() {
        for (src, want) in [
            (
                r#"room{ default = "on", states = { on = { look = { brightnes = 5 } } } }"#,
                "unknown key",
            ),
            (
                r#"room{ default = "on", states = { on = { on = { present = "on" } } } }"#,
                "no event",
            ),
            (
                r#"room{ default = "on", states = { on = { when = { { to = "of" } } } } }"#,
                "no state",
            ),
            (
                r#"room{ default = "on", states = { on = { look = { brightness = function() return nil + 1 end } } } }"#,
                "arithmetic",
            ),
            (
                r#"room{ default = "on", states = { on = { when = { { to = "on", toggle = { "a" } } } } } }"#,
                "needs one of",
            ),
            (
                r#"room{ default = "on", states = { on = { when = { { present = true } } } } }"#,
                "needs one of",
            ),
            (
                r#"room{ default = "on", states = { on = { extends = "on" } } }"#,
                "loop",
            ),
            (r#"local x = 1"#, "never calls room"),
        ] {
            let err = format!(
                "{:#}",
                load(src).err().unwrap_or_else(|| panic!("{src} loaded"))
            );
            assert!(err.contains(want), "{src}: {err}");
        }
    }

    #[test]
    fn settings_parse_as_their_default_type() {
        let (script, spec) = load(
            r#"local n = setting("t/n", 5); local b = setting("t/b", false)
               room{ default = "on", states = { on = { look = {
                 brightness = function() return n() end,
                 on = function() return b() end,
               } } } }"#,
        )
        .unwrap();
        let on = &spec.states[spec.default];
        let get = || {
            script
                .look(on, "a", &ctx("a", "on"))
                .unwrap()
                .unwrap()
                .target
        };
        assert_eq!((get().brightness, get().on), (5, false));
        script.setting("t/n", &serde_json::json!("40"));
        script.setting("t/b", &serde_json::json!(true));
        script.setting("t/n", &serde_json::json!("junk"));
        assert_eq!((get().brightness, get().on), (40, true));
        // Besides the prelude's knobs for every light.
        let ours: Vec<_> = script
            .topics()
            .into_iter()
            .filter(|t| t.starts_with("t/"))
            .collect();
        assert_eq!(ours, ["t/b", "t/n"]);
        assert!(script
            .topics()
            .contains(&"mqtt-auto/sun-follow/dev_a/min-brightness".to_owned()));
    }

    #[test]
    fn sunlight_runs_from_zero_to_max_above_the_floor() {
        let (script, spec) = load(
            r#"room{ default = "on", states = {
                on = { look = sunlight() },
                cosy = { look = sunlight{ floor = 30 } },
            } }"#,
        )
        .unwrap();
        let state = |n: &str| spec.states.iter().find(|s| s.name == n).unwrap();
        let bri = |n: &str| {
            script
                .look(state(n), "a", &ctx("a", n))
                .unwrap()
                .unwrap()
                .target
                .brightness
        };
        let base = "mqtt-auto/sun-follow/dev_a/";
        script.setting(&format!("{base}min-brightness"), &serde_json::json!(10));
        script.setting(&format!("{base}max-brightness"), &serde_json::json!(80));

        // Midday: the curve's top, the floor doesn't matter.
        assert_eq!(bri("on"), 203);
        // Night: the floor (10% of 254), or the state's higher one.
        script.set_clock(DateTime::parse_from_rfc3339("2026-06-21T23:30:00+02:00").unwrap());
        assert_eq!((bri("on"), bri("cosy")), (25, 76));
        // Dusk: the curve from 0, not squeezed between floor and max.
        script.set_clock(DateTime::parse_from_rfc3339("2026-06-21T20:45:00+02:00").unwrap());
        let frac = sun::daylight_fraction(
            52.52,
            13.405,
            DateTime::parse_from_rfc3339("2026-06-21T20:45:00+02:00").unwrap(),
        );
        assert!(frac > 0.05 && frac < 0.5, "{frac}");
        assert_eq!(bri("on"), curves::brightness_254(0, 80, frac).max(25));
    }

    #[test]
    fn a_runaway_function_is_stopped() {
        let err = load(
            r#"room{ default = "on", states = { on = { look = {
                 brightness = function() while true do end end } } } }"#,
        )
        .err()
        .unwrap();
        assert!(format!("{err:#}").contains("too long"), "{err:#}");
    }
}
