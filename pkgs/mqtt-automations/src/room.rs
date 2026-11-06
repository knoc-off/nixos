//! One room as the state machine its Lua file declares ([`crate::script`]).
//! Nothing here knows what a bedroom is: the room is always in exactly one
//! state, events and `when` rows move it, and each light shows what the
//! state's look says -- unless a person changed it, which the arbiter
//! detects and holds until the room changes state.
//!
//! The only memory is `resume`'s: leaving a mode (a state that isn't
//! hidden) remembers it together with every bulb held at that moment, so
//! coming back within `forget_after` restores both.
//!
//! Pure apart from calling the room's Lua functions: no MQTT, no wall clock;
//! the caller passes the time in and calls [`Room::step`] with
//! [`Event::Tick`] at [`Room::deadline`].

use std::collections::{BTreeMap, BTreeSet};
use std::time::{Duration, Instant};

use anyhow::Result;
use chrono::{DateTime, FixedOffset, Timelike};
use serde_json::{json, Value};

use crate::arbiter::{self, Bulb, Command, Input, Target};
use crate::script::{Cond, Ctx, Go, Row, Script, Spec};

/// Looks are re-evaluated at least this often (the sun moves).
const EVAL_EVERY: Duration = Duration::from_secs(30);
/// Transition for look changes while a state lasts.
const DRIFT: Duration = Duration::from_secs(2);
/// Transition on entering a state whose look names none, and for toggles.
const ENTER: Duration = Duration::from_millis(400);
/// State changes per step: a backstop against two `when` rows bouncing.
const MAX_HOPS: usize = 8;

pub struct Light {
    pub name: String,
    pub device: String,
    pub dimmable: bool,
    pub bulb: Bulb,
}

#[derive(Clone, Copy, Debug)]
pub enum Event<'a> {
    Tick,
    Presence {
        device: &'a str,
        present: bool,
    },
    Door {
        name: &'a str,
        open: bool,
    },
    Button {
        name: &'a str,
        action: &'a str,
    },
    Report {
        bulb: usize,
        target: Target,
    },
    /// Hand one bulb back to the room (HA "release").
    Release(usize),
    /// Forget everything and go to the default state (HA room "reset").
    Reset,
    /// A mode picked in HA.
    Select(&'a str),
    Setting {
        topic: &'a str,
        payload: &'a Value,
    },
}

#[derive(Default, Debug)]
pub struct Outcome {
    /// The last command per bulb this step, by bulb index.
    pub commands: BTreeMap<usize, Command>,
    /// Retained (topic, value) pairs that changed.
    pub publish: Vec<(String, Value)>,
}

struct Memory {
    state: usize,
    holds: Vec<(usize, Target)>,
    at: Instant,
}

pub struct Room {
    pub name: String,
    pub bulbs: Vec<Light>,
    script: Script,
    spec: Spec,
    state: usize,
    since: Instant,
    /// Presence sensors currently reporting someone.
    sensing: BTreeSet<String>,
    present: bool,
    /// When `present` last changed (startup counts as a change).
    present_changed: Instant,
    memory: Option<Memory>,
    /// Each trigger's last value, to fire on the rising edge only.
    triggered: Vec<bool>,
    last_eval: Instant,
    published: BTreeMap<String, Value>,
}

impl Room {
    /// `bulbs`: (name, z2m device, dimmable).
    pub fn new(
        name: &str,
        source: &str,
        bulbs: Vec<(String, String, bool)>,
        location: (f64, f64),
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Result<Self> {
        let (script, spec) = Script::load(name, source, &bulbs, location, wall)?;
        let bulbs = bulbs
            .into_iter()
            .map(|(name, device, dimmable)| Light {
                name,
                device,
                dimmable,
                bulb: Bulb::new(arbiter::Config {
                    dimmable,
                    ..arbiter::Config::default()
                }),
            })
            .collect();
        Ok(Self {
            name: name.to_owned(),
            bulbs,
            state: spec.start,
            triggered: vec![false; spec.triggers.len()],
            script,
            spec,
            since: now,
            sensing: BTreeSet::new(),
            present: false,
            present_changed: now,
            memory: None,
            // Due straight away, so the looks go out at startup.
            last_eval: now.checked_sub(EVAL_EVERY).unwrap_or(now),
            published: BTreeMap::new(),
        })
    }

    pub fn spec(&self) -> &Spec {
        &self.spec
    }

    pub fn setting_topics(&self) -> Vec<String> {
        self.script.topics()
    }

    /// The states HA may pick: every one that isn't hidden, the default
    /// first and `manual` last.
    pub fn modes(&self) -> Vec<&str> {
        let mut modes: Vec<&str> = self
            .spec
            .states
            .iter()
            .filter(|s| !s.hidden)
            .map(|s| s.name.as_str())
            .collect();
        let default = self.spec.states[self.spec.default].name.as_str();
        modes.sort_by_key(|&m| (m != default, m == "manual", m));
        modes
    }

    pub fn state_name(&self) -> &str {
        &self.spec.states[self.state].name
    }

    /// The next moment the room changes by itself.
    pub fn deadline(&self) -> Instant {
        let bulbs = self.bulbs.iter().filter_map(|l| l.bulb.deadline());
        let rows = self.spec.states[self.state]
            .when
            .iter()
            .filter_map(|r| self.due(&r.cond));
        bulbs
            .chain(rows)
            .chain([self.last_eval + EVAL_EVERY])
            .min()
            .expect("the eval deadline is always there")
    }

    pub fn step(&mut self, event: Event, now: Instant, wall: DateTime<FixedOffset>) -> Outcome {
        self.script.set_clock(wall);
        let clock = hours(wall);
        let mut step = Step::default();
        let mut events = Vec::new();
        match event {
            Event::Tick => {
                for (b, l) in self.bulbs.iter().enumerate() {
                    if l.bulb.deadline().is_some_and(|at| at <= now) {
                        step.before.push((b, Input::Tick));
                    }
                }
            }
            Event::Presence { device, present } => {
                if present {
                    self.sensing.insert(device.to_owned());
                } else {
                    self.sensing.remove(device);
                }
                let now_present = !self.sensing.is_empty();
                if now_present != self.present {
                    self.present = now_present;
                    self.present_changed = now;
                    events.push(if now_present { "present" } else { "absent" }.to_owned());
                }
            }
            Event::Door { name, open } => {
                events.push(format!("{name}.{}", if open { "open" } else { "closed" }));
            }
            Event::Button { name, action } => events.push(format!("{name}.{action}")),
            Event::Report { bulb, target } => step.before.push((bulb, Input::Report(target))),
            Event::Release(b) => step.before.push((b, Input::Release { transition: ENTER })),
            Event::Reset => {
                self.memory = None;
                for b in 0..self.bulbs.len() {
                    step.before.push((b, Input::Release { transition: ENTER }));
                }
                self.enter(self.spec.default, true, now, &mut step, "reset");
            }
            Event::Select(name) => {
                match self
                    .spec
                    .states
                    .iter()
                    .position(|s| s.name == name && !s.hidden)
                {
                    Some(i) => self.enter(i, false, now, &mut step, "picked in HA"),
                    None => self.script.log(&format!("no mode {name:?} to pick")),
                }
            }
            Event::Setting { topic, payload } => self.script.setting(topic, payload),
        }

        for i in 0..self.spec.triggers.len() {
            let v = self.test_trigger(i, now, clock);
            if v && !self.triggered[i] {
                events.push(self.spec.triggers[i].0.clone());
            }
            self.triggered[i] = v;
        }
        for e in &events {
            let rows = &self.spec.states[self.state].on;
            if let Some(i) = rows.get(e).and_then(|rows| self.first(rows, now, clock)) {
                self.take(e, i, now, clock, &mut step);
            }
        }
        for hop in 0.. {
            let Some(i) = self.first(&self.spec.states[self.state].when, now, clock) else {
                break;
            };
            if hop == MAX_HOPS {
                self.script
                    .log("`when` rows keep moving the room; stopping");
                break;
            }
            let before = self.state;
            self.take_when(i, now, clock, &mut step);
            if self.state == before {
                break;
            }
        }

        self.last_eval = now;
        self.apply(step, now, clock)
    }

    /// Index of the first row in `rows` whose condition holds.
    fn first(&self, rows: &[Row], now: Instant, clock: f64) -> Option<usize> {
        rows.iter().position(|r| self.holds(&r.cond, now, clock))
    }

    fn take(&mut self, event: &str, i: usize, now: Instant, clock: f64, step: &mut Step) {
        let go = &self.spec.states[self.state].on[event][i].go;
        self.go(go_of(go), now, clock, step, event);
    }

    fn take_when(&mut self, i: usize, now: Instant, clock: f64, step: &mut Step) {
        let go = &self.spec.states[self.state].when[i].go;
        self.go(go_of(go), now, clock, step, "when");
    }

    fn go(&mut self, go: GoOwned, now: Instant, clock: f64, step: &mut Step, why: &str) {
        match go {
            GoOwned::State(i) => self.enter(i, false, now, step, why),
            GoOwned::Resume => match self
                .memory
                .take()
                .filter(|m| now - m.at < self.spec.forget_after)
            {
                Some(m) => {
                    self.enter(m.state, false, now, step, why);
                    step.after.extend(m.holds.into_iter().map(|(b, target)| {
                        (
                            b,
                            Input::User {
                                target,
                                transition: ENTER,
                            },
                        )
                    }));
                }
                None => self.enter(self.spec.default, false, now, step, why),
            },
            GoOwned::Toggle(bulbs) => {
                let any_on = bulbs
                    .iter()
                    .any(|&b| self.bulbs[b].bulb.showing().is_some_and(|t| t.on));
                for b in bulbs {
                    let looks = self.look(b, now, clock).map(|l| l.target);
                    let target = Target {
                        on: !any_on,
                        ..looks.unwrap_or(Target {
                            on: true,
                            brightness: Target::FULL,
                            color_temp: None,
                        })
                    };
                    step.after.push((
                        b,
                        Input::User {
                            target,
                            transition: ENTER,
                        },
                    ));
                }
            }
        }
    }

    /// Move to state `i`. Leaving a mode remembers it, with its holds.
    fn enter(&mut self, i: usize, force: bool, now: Instant, step: &mut Step, why: &str) {
        if i == self.state && !force {
            return;
        }
        let from = self.state;
        if !self.spec.states[from].hidden && from != i {
            let holds = self
                .bulbs
                .iter()
                .enumerate()
                .filter_map(|(b, l)| Some((b, l.bulb.held()?)))
                .collect();
            self.memory = Some(Memory {
                state: from,
                holds,
                at: now,
            });
        }
        eprintln!(
            "{}: {} -> {} ({why})",
            self.name, self.spec.states[from].name, self.spec.states[i].name
        );
        self.state = i;
        self.since = now;
        step.entered = true;
        // A toggle queued before the change belonged to the state left.
        step.after.clear();
    }

    /// Send every bulb its look, release holds on entering a state, then
    /// apply what the step queued for after.
    fn apply(&mut self, step: Step, now: Instant, clock: f64) -> Outcome {
        let mut inputs = step.before;
        for b in 0..self.bulbs.len() {
            let Some(look) = self.look(b, now, clock) else {
                continue;
            };
            let transition = if step.entered {
                look.transition.unwrap_or(ENTER)
            } else {
                DRIFT
            };
            inputs.push((
                b,
                Input::Auto {
                    target: look.target,
                    transition,
                },
            ));
            if step.entered {
                inputs.push((b, Input::Release { transition }));
            }
        }
        inputs.extend(step.after);

        let mut out = Outcome::default();
        for (b, input) in inputs {
            let l = &mut self.bulbs[b];
            let before = l.bulb.mode;
            if let Some(cmd) = l.bulb.step(input, now) {
                out.commands.insert(b, cmd);
            }
            if l.bulb.mode != before {
                eprintln!("{}/{}: {before:?} -> {:?}", self.name, l.name, l.bulb.mode);
            }
        }

        let mode = match &self.memory {
            _ if !self.spec.states[self.state].hidden => self.state,
            Some(m) if now - m.at < self.spec.forget_after => m.state,
            _ => self.spec.default,
        };
        let mut retained = vec![
            ("state", json!(self.state_name())),
            ("mode", json!(self.spec.states[mode].name)),
        ];
        if !self.spec.presence.is_empty() {
            retained.push(("occupied", json!(self.present)));
        }
        for (name, value) in retained {
            let topic = format!("lights/{}/{name}", self.name);
            if self.published.get(&topic) != Some(&value) {
                self.published.insert(topic.clone(), value.clone());
                out.publish.push((topic, value));
            }
        }
        out
    }

    fn look(&self, b: usize, now: Instant, clock: f64) -> Option<crate::script::Look> {
        let light = &self.bulbs[b].name;
        let state = &self.spec.states[self.state];
        match self
            .script
            .look(state, light, &self.ctx(Some(light), now, clock))
        {
            Ok(look) => look,
            Err(e) => {
                self.script.log(&format!("{}: {light}: {e:#}", state.name));
                None
            }
        }
    }

    fn test_trigger(&self, i: usize, now: Instant, clock: f64) -> bool {
        let (name, f) = &self.spec.triggers[i];
        self.script
            .test(f, &self.ctx(None, now, clock))
            .unwrap_or_else(|e| {
                self.script.log(&format!("trigger {name}: {e:#}"));
                false
            })
    }

    fn ctx<'a>(&'a self, light: Option<&'a str>, now: Instant, clock: f64) -> Ctx<'a> {
        let since_change = (now - self.present_changed).as_secs_f64();
        Ctx {
            light,
            state: self.state_name(),
            present: self.present,
            present_for: if self.present { since_change } else { 0.0 },
            absent_for: if self.present { 0.0 } else { since_change },
            time_in_state: (now - self.since).as_secs_f64(),
            clock,
        }
    }

    fn holds(&self, c: &Cond, now: Instant, clock: f64) -> bool {
        let absent = now - self.present_changed;
        c.present.is_none_or(|p| p == self.present)
            && c.absent_for.is_none_or(|d| !self.present && absent >= d)
            && c.time_in_state.is_none_or(|d| now - self.since >= d)
            && c.between.is_none_or(|(a, b)| in_hours(clock, a, b))
            && c.outside.is_none_or(|(a, b)| !in_hours(clock, a, b))
            && c.test.as_ref().is_none_or(|f| {
                self.script
                    .test(f, &self.ctx(None, now, clock))
                    .unwrap_or_else(|e| {
                        self.script.log(&format!("test: {e:#}"));
                        false
                    })
            })
    }

    /// When a row's durations will all have passed, if that is still ahead
    /// and presence can't rule it out. Other conditions wait for the
    /// periodic evaluation.
    fn due(&self, c: &Cond) -> Option<Instant> {
        if c.present.is_some_and(|p| p != self.present) || (c.absent_for.is_some() && self.present)
        {
            return None;
        }
        let at = [
            c.absent_for.map(|d| self.present_changed + d),
            c.time_in_state.map(|d| self.since + d),
        ];
        at.into_iter()
            .flatten()
            .max()
            .filter(|&at| at > self.last_eval)
    }
}

/// What a step queues around the looks.
#[derive(Default)]
struct Step {
    /// Applied first: reports, releases, plug timers.
    before: Vec<(usize, Input)>,
    entered: bool,
    /// Applied last: restored holds and toggles.
    after: Vec<(usize, Input)>,
}

/// [`Go`] without the borrow on the spec.
enum GoOwned {
    State(usize),
    Resume,
    Toggle(Vec<usize>),
}

fn go_of(go: &Go) -> GoOwned {
    match go {
        Go::State(i) => GoOwned::State(*i),
        Go::Resume => GoOwned::Resume,
        Go::Toggle(b) => GoOwned::Toggle(b.clone()),
    }
}

fn hours(wall: DateTime<FixedOffset>) -> f64 {
    f64::from(wall.time().num_seconds_from_midnight()) / 3600.0
}

/// Is `h` in `[from, to)`? Wraps past midnight (`22, 8`).
fn in_hours(h: f64, from: f64, to: f64) -> bool {
    if from <= to {
        h >= from && h < to
    } else {
        h >= from || h < to
    }
}
