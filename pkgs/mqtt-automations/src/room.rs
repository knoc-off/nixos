//! Room logic: turns one room's sensors, buttons and the time of day into
//! requests for the light arbiter (see `bin/light_arbiter.rs` for the
//! contract). Pure -- the caller passes both clocks (`Instant` for timers,
//! wall time for the sun) and calls back with `Event::Tick` at
//! [`Room::deadline`] and periodically, so the curves keep moving.
//!
//! Every room has the same shape:
//!   1. Occupancy: `Occupied -> Leaving -> Vacant`, fed by sources.
//!      Presence holds while it reports someone, plus `hold` after it
//!      clears. Motion holds for `hold` after each trigger; the sensor's
//!      own "clear" is ignored, so the room is the only timing source. A
//!      door holds for `hold` after opening, and closing it with someone
//!      inside latches the room until it opens again (wasp in a box).
//!      Button presses and wake ramps count as someone being here. A room
//!      without sources is always occupied.
//!   2. Per light: a level from the sun (dimming, or a plug's on/off
//!      threshold), colour temperature, an optional wake ramp, and whether
//!      occupancy may turn it on (`turnOn`) or only keep it on.
//!   3. Controls: button gestures mapped to a closed set of verbs.
//!
//! Leaving *is* the fade: the room asks the arbiter for scale 0 over `fade`,
//! and turns vacant -- releasing every hold -- once the fade has run out.

use std::collections::BTreeMap;
use std::time::{Duration, Instant};

use anyhow::{bail, Result};
use chrono::{DateTime, FixedOffset, NaiveTime};
use serde::{Deserialize, Serialize};

use crate::arbiter::Target;
use crate::{curves, sun};

/// Hysteresis half-width for plug thresholds, in daylight percent.
const DEADBAND: f64 = 5.0;
/// "Already dim" margin for `dimThenOff`, tolerating bulb rounding.
const LOW_MARGIN: u8 = 10;

/// Durations are plain seconds in the JSON config.
mod secs {
    use serde::{de::Error, Deserialize, Deserializer};
    use std::time::Duration;

    pub fn deserialize<'de, D: Deserializer<'de>>(d: D) -> Result<Duration, D::Error> {
        Duration::try_from_secs_f64(f64::deserialize(d)?).map_err(D::Error::custom)
    }
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Config {
    pub latitude: f64,
    pub longitude: f64,
    #[serde(default)]
    pub sources: Vec<Source>,
    /// How long the lights take to fade out once nobody is detected.
    #[serde(default, with = "secs")]
    pub fade: Duration,
    /// How long a button press or wake ramp counts as someone being here.
    /// Also the grace period after a restart, so a restart never turns
    /// anything off.
    #[serde(default = "Config::interaction_hold", with = "secs")]
    pub interaction_hold: Duration,
    #[serde(default = "Config::fast_transition", with = "secs")]
    pub fast_transition: Duration,
    #[serde(default = "Config::curve_transition", with = "secs")]
    pub curve_transition: Duration,
    pub lights: BTreeMap<String, Light>,
    /// Device -> z2m action -> verb.
    #[serde(default)]
    pub controls: BTreeMap<String, BTreeMap<String, Verb>>,
}

impl Config {
    /// z2m devices whose state messages feed the sources.
    pub fn sensors(&self) -> impl Iterator<Item = &str> {
        self.sources.iter().map(Source::device)
    }

    /// z2m devices whose actions are mapped in `controls`.
    pub fn buttons(&self) -> impl Iterator<Item = &str> {
        self.controls.keys().map(String::as_str)
    }

    fn interaction_hold() -> Duration {
        Duration::from_secs(300)
    }
    fn fast_transition() -> Duration {
        Duration::from_millis(400)
    }
    fn curve_transition() -> Duration {
        Duration::from_secs(2)
    }
}

#[derive(Deserialize, Debug, Clone)]
#[serde(
    tag = "type",
    rename_all = "lowercase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum Source {
    Presence {
        device: String,
        #[serde(default, with = "secs")]
        hold: Duration,
    },
    Motion {
        device: String,
        #[serde(with = "secs")]
        hold: Duration,
    },
    Door {
        device: String,
        #[serde(with = "secs")]
        hold: Duration,
        /// How long after the door closes to check whether someone is
        /// still inside: the presence sensor's own clear delay plus a
        /// margin, or someone who just left would latch the room.
        #[serde(with = "secs")]
        latch_after: Duration,
    },
}

impl Source {
    fn device(&self) -> &str {
        match self {
            Self::Presence { device, .. }
            | Self::Motion { device, .. }
            | Self::Door { device, .. } => device,
        }
    }
}

#[derive(Deserialize, Debug, Clone, Default)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Light {
    /// Occupancy turns this light on. Otherwise occupancy only keeps it on
    /// once someone switched it on, and turns it off when the room empties.
    #[serde(default)]
    pub turn_on: bool,
    #[serde(default)]
    pub sun: Sun,
    #[serde(default)]
    pub color_temp: Option<ColorTemp>,
    #[serde(default)]
    pub wake: Option<Wake>,
}

/// Same knobs as the HA sun-follow entities.
#[derive(Deserialize, Debug, Clone)]
#[serde(default, rename_all = "camelCase", deny_unknown_fields)]
pub struct Sun {
    /// Off (or outside a followed half of the day): the level stays where
    /// it last was.
    pub enabled: bool,
    pub follow_sunrise: bool,
    pub follow_sunset: bool,
    pub invert: bool,
    /// Brightness range in percent; the floor is what night looks like.
    pub min: u8,
    pub max: u8,
    pub gamma: f64,
    /// Plugs: on above this daylight percent instead of dimming.
    pub threshold: Option<u8>,
}

impl Default for Sun {
    fn default() -> Self {
        Self {
            enabled: true,
            follow_sunrise: true,
            follow_sunset: true,
            invert: false,
            min: 1,
            max: 100,
            gamma: 1.0,
            threshold: None,
        }
    }
}

#[derive(Deserialize, Debug, Clone, Copy)]
#[serde(default, deny_unknown_fields)]
pub struct ColorTemp {
    pub enabled: bool,
    /// Mireds, night and the ends of the day.
    pub warm: u16,
    /// Mireds, the middle of the day.
    pub cool: u16,
}

impl Default for ColorTemp {
    fn default() -> Self {
        Self {
            enabled: true,
            warm: 454,
            cool: 250,
        }
    }
}

/// A fixed-clock wake-up ramp, deliberately not sun-based (see
/// `bin/sunrise_lights.rs`).
#[derive(Deserialize, Debug, Clone, Copy)]
#[serde(default, deny_unknown_fields)]
pub struct Wake {
    pub at: NaiveTime,
    pub minutes: u32,
    /// Brightness cap, percent.
    pub max: u8,
    pub gamma: f64,
}

impl Default for Wake {
    fn default() -> Self {
        Self {
            at: NaiveTime::from_hms_opt(6, 30, 0).expect("valid time"),
            minutes: 45,
            max: 30,
            gamma: 2.2,
        }
    }
}

/// What a button gesture does. `lights` empty means every light in the room.
#[derive(Deserialize, Debug, Clone)]
#[serde(
    tag = "action",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum Verb {
    /// Anything on -> all off, otherwise all on at the curve.
    Toggle {
        #[serde(default)]
        lights: Vec<String>,
    },
    /// Off -> on at the curve; bright -> `level`%; dim -> off.
    DimThenOff {
        level: u8,
        #[serde(default)]
        lights: Vec<String>,
    },
    /// `level`% now, off after `after`.
    LowThenOff {
        level: u8,
        #[serde(with = "secs")]
        after: Duration,
        #[serde(default)]
        lights: Vec<String>,
    },
    DimUp {
        step: u8,
        #[serde(default)]
        lights: Vec<String>,
    },
    DimDown {
        step: u8,
        #[serde(default)]
        lights: Vec<String>,
    },
    /// Hand every held light back to the automation.
    Release,
}

impl Verb {
    fn lights(&self) -> &[String] {
        match self {
            Self::Toggle { lights }
            | Self::DimThenOff { lights, .. }
            | Self::LowThenOff { lights, .. }
            | Self::DimUp { lights, .. }
            | Self::DimDown { lights, .. } => lights,
            Self::Release => &[],
        }
    }
}

/// A runtime change from an HA entity.
#[derive(Clone, Copy, Debug)]
pub enum Setting {
    Enabled(bool),
    FollowSunrise(bool),
    FollowSunset(bool),
    Invert(bool),
    Min(u8),
    Max(u8),
    Gamma(f64),
    Threshold(u8),
    ColorTemp(bool),
    WakeAt(NaiveTime),
    WakeMinutes(u32),
    WakeMax(u8),
    WakeGamma(f64),
}

#[derive(Clone, Debug)]
pub enum Event {
    /// A presence or motion sensor report.
    Sensor {
        device: String,
        active: bool,
    },
    Door {
        device: String,
        open: bool,
    },
    /// A button's z2m action.
    Action {
        device: String,
        action: String,
    },
    /// The arbiter's view of a bulb.
    Bulb {
        light: String,
        held: bool,
        state: Target,
    },
    Setting {
        light: String,
        setting: Setting,
    },
    Tick,
}

/// The payload of `lights/<room>/auto` and `lights/<room>/user`.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Request {
    pub bulbs: BTreeMap<String, Target>,
    pub scale: f32,
    /// Seconds.
    pub transition: f32,
}

#[derive(Clone, Debug, PartialEq)]
pub enum Out {
    Auto(Request),
    User(Request),
    Release { transition: f32 },
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Occupancy {
    Occupied,
    Leaving { until: Instant },
    Vacant,
}

/// What one source currently says about the room.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Evidence {
    Idle,
    Active,
    Until(Instant),
}

struct SourceSlot {
    cfg: Source,
    evidence: Evidence,
    /// A door that closed and still has to decide whether to latch.
    closed_at: Option<Instant>,
}

struct LightSlot {
    name: String,
    cfg: Light,
    /// The arbiter's last report.
    shown: Option<Target>,
    /// Someone switched it on: what keep-on lights follow.
    lit: bool,
    /// Last level the sun produced, kept while not following it.
    curve: Option<(bool, u8)>,
    switch_on: Option<bool>,
    off_at: Option<Instant>,
    waking: bool,
}

pub struct Room {
    latitude: f64,
    longitude: f64,
    fade: Duration,
    interaction_hold: Duration,
    fast: Duration,
    curve: Duration,
    controls: BTreeMap<String, BTreeMap<String, Verb>>,
    sources: Vec<SourceSlot>,
    lights: Vec<LightSlot>,
    occupancy: Occupancy,
    interaction_until: Option<Instant>,
    last_auto: Option<(BTreeMap<String, Target>, f32)>,
}

impl Room {
    pub fn new(cfg: Config, now: Instant) -> Result<Self> {
        for (device, actions) in &cfg.controls {
            for (action, verb) in actions {
                if let Some(l) = verb.lights().iter().find(|l| !cfg.lights.contains_key(*l)) {
                    bail!("control {device}/{action} names unknown light {l:?}");
                }
            }
        }
        Ok(Self {
            latitude: cfg.latitude,
            longitude: cfg.longitude,
            fade: cfg.fade,
            interaction_hold: cfg.interaction_hold,
            fast: cfg.fast_transition,
            curve: cfg.curve_transition,
            controls: cfg.controls,
            sources: cfg
                .sources
                .into_iter()
                .map(|cfg| SourceSlot {
                    cfg,
                    evidence: Evidence::Idle,
                    closed_at: None,
                })
                .collect(),
            lights: cfg
                .lights
                .into_iter()
                .map(|(name, cfg)| LightSlot {
                    name,
                    cfg,
                    shown: None,
                    lit: false,
                    curve: None,
                    switch_on: None,
                    off_at: None,
                    waking: false,
                })
                .collect(),
            occupancy: Occupancy::Occupied,
            interaction_until: Some(now + cfg.interaction_hold),
            last_auto: None,
        })
    }

    pub fn occupancy(&self) -> Occupancy {
        self.occupancy
    }

    /// The next moment something changes by itself. The curves move too,
    /// so the caller should also tick periodically.
    pub fn deadline(&self) -> Option<Instant> {
        let sources = self.sources.iter().flat_map(|s| {
            let evidence = match s.evidence {
                Evidence::Until(t) => Some(t),
                _ => None,
            };
            let latch = match s.cfg {
                Source::Door { latch_after, .. } => s.closed_at.map(|c| c + latch_after),
                _ => None,
            };
            [evidence, latch]
        });
        let leaving = match self.occupancy {
            Occupancy::Leaving { until } => Some(until),
            _ => None,
        };
        sources
            .chain(self.lights.iter().map(|l| l.off_at))
            .chain([leaving, self.interaction_until])
            .flatten()
            .min()
    }

    pub fn step(&mut self, event: Event, now: Instant, wall: DateTime<FixedOffset>) -> Vec<Out> {
        let mut out = Vec::new();
        match event {
            Event::Sensor { device, active } => self.sensor(&device, active, now),
            Event::Door { device, open } => self.door(&device, open, now),
            Event::Action { device, action } => {
                out.extend(self.action(&device, &action, now, wall))
            }
            Event::Bulb { light, held, state } => {
                if let Some(l) = self.light_mut(&light) {
                    l.shown = Some(state);
                    // In auto the bulb shows what we asked for; only a hold
                    // tells us what a person wants.
                    if held {
                        l.lit = state.on;
                    }
                }
            }
            Event::Setting { light, setting } => {
                if let Some(l) = self.light_mut(&light) {
                    apply(&mut l.cfg, setting);
                }
            }
            Event::Tick => {}
        }
        out.extend(self.timers(now));
        if self
            .lights
            .iter()
            .any(|l| wake_progress(l.cfg.wake.as_ref(), wall).is_some())
        {
            self.interaction_until = Some(now + self.interaction_hold);
        }
        let before = self.occupancy;
        self.update_occupancy(now);
        out.extend(self.publish(before, wall));
        out
    }

    fn light_mut(&mut self, name: &str) -> Option<&mut LightSlot> {
        self.lights.iter_mut().find(|l| l.name == name)
    }

    fn sensor(&mut self, device: &str, active: bool, now: Instant) {
        for s in self.sources.iter_mut().filter(|s| s.cfg.device() == device) {
            match s.cfg {
                Source::Presence { hold, .. } => {
                    s.evidence = if active {
                        Evidence::Active
                    } else {
                        Evidence::Until(now + hold)
                    };
                }
                Source::Motion { hold, .. } if active => s.evidence = Evidence::Until(now + hold),
                _ => {}
            }
        }
    }

    fn door(&mut self, device: &str, open: bool, now: Instant) {
        for s in self.sources.iter_mut().filter(|s| s.cfg.device() == device) {
            if let Source::Door {
                hold, latch_after, ..
            } = s.cfg
            {
                if open {
                    s.evidence = Evidence::Until(now + hold);
                    s.closed_at = None;
                } else {
                    // Lights stay on while we wait to see who is inside.
                    s.evidence = Evidence::Until(now + latch_after);
                    s.closed_at = Some(now);
                }
            }
        }
    }

    /// Fire `lowThenOff` timers.
    fn timers(&mut self, now: Instant) -> Option<Out> {
        let mut bulbs = BTreeMap::new();
        for l in &mut self.lights {
            if l.off_at.is_some_and(|at| now >= at) {
                l.off_at = None;
                bulbs.insert(l.name.clone(), off());
            }
        }
        (!bulbs.is_empty()).then(|| self.user(bulbs))
    }

    fn update_occupancy(&mut self, now: Instant) {
        let presence_now = self
            .sources
            .iter()
            .any(|s| matches!(s.cfg, Source::Presence { .. }) && s.evidence == Evidence::Active);
        for s in &mut self.sources {
            if let Source::Door { latch_after, .. } = s.cfg {
                if s.closed_at.is_some_and(|c| now >= c + latch_after) {
                    s.closed_at = None;
                    if presence_now {
                        s.evidence = Evidence::Active;
                    }
                }
            }
            // Expired evidence is forgotten, so `deadline` never returns a
            // moment that has already passed.
            if matches!(s.evidence, Evidence::Until(t) if now >= t) {
                s.evidence = Evidence::Idle;
            }
        }
        if self.interaction_until.is_some_and(|t| now >= t) {
            self.interaction_until = None;
        }

        let evidence = self.sources.is_empty()
            || self.interaction_until.is_some()
            || self.sources.iter().any(|s| s.evidence != Evidence::Idle);
        self.occupancy = match self.occupancy {
            _ if evidence => Occupancy::Occupied,
            Occupancy::Occupied if self.fade.is_zero() => Occupancy::Vacant,
            Occupancy::Occupied => Occupancy::Leaving {
                until: now + self.fade,
            },
            Occupancy::Leaving { until } if now >= until => Occupancy::Vacant,
            other => other,
        };
    }

    fn publish(&mut self, before: Occupancy, wall: DateTime<FixedOffset>) -> Vec<Out> {
        let vacated = self.occupancy == Occupancy::Vacant && before != Occupancy::Vacant;
        let mut release = vacated;
        if vacated {
            for l in &mut self.lights {
                l.lit = false;
                l.off_at = None;
            }
        }

        let present = self.occupancy != Occupancy::Vacant;
        let mut bulbs = BTreeMap::new();
        for i in 0..self.lights.len() {
            let level = self.level(i, wall);
            let l = &mut self.lights[i];
            let target = match wake_progress(l.cfg.wake.as_ref(), wall) {
                Some((wake, p)) => {
                    if !l.waking {
                        // A night-time manual off must not block the ramp.
                        release = true;
                        l.waking = true;
                        l.lit = true;
                    }
                    let cap = f64::from(wake.max) / 100.0 * f64::from(Target::FULL);
                    Target {
                        on: true,
                        brightness: (curves::ramp(p, wake.gamma) * cap).round().max(1.0) as u8,
                        ..level
                    }
                }
                None => {
                    l.waking = false;
                    Target {
                        on: level.on && present && (l.cfg.turn_on || l.lit),
                        ..level
                    }
                }
            };
            bulbs.insert(l.name.clone(), target);
        }

        let leaving = matches!(self.occupancy, Occupancy::Leaving { .. });
        let scale = if leaving { 0.0 } else { 1.0 };
        let transition = match (before, self.occupancy) {
            (_, Occupancy::Leaving { .. }) => self.fade,
            (Occupancy::Occupied, Occupancy::Occupied) => self.curve,
            (_, Occupancy::Occupied) => self.fast,
            _ => self.curve,
        };

        let mut out = Vec::new();
        let current = (bulbs, scale);
        if self.last_auto.as_ref() != Some(&current) {
            out.push(Out::Auto(Request {
                bulbs: current.0.clone(),
                scale,
                transition: transition.as_secs_f32(),
            }));
            self.last_auto = Some(current);
        }
        if release {
            out.push(Out::Release {
                transition: self.fast.as_secs_f32(),
            });
        }
        out
    }

    /// What the sun says for light `i` right now, as if it were on.
    fn level(&mut self, i: usize, wall: DateTime<FixedOffset>) -> Target {
        let (lat, lon) = (self.latitude, self.longitude);
        let l = &mut self.lights[i];
        let sun = &l.cfg.sun;
        let noon = sun::solar_noon(lon, wall.date_naive(), *wall.offset());
        let following = sun.enabled
            && if wall < noon {
                sun.follow_sunrise
            } else {
                sun.follow_sunset
            };
        let raw = sun::daylight_fraction(lat, lon, wall);
        let frac = if sun.invert { 1.0 - raw } else { raw };

        let (on, brightness) = match sun.threshold {
            Some(threshold) => {
                if following {
                    let last = l.switch_on;
                    l.switch_on = Some(curves::decide_switch(
                        frac,
                        threshold.into(),
                        DEADBAND,
                        last,
                    ));
                }
                (l.switch_on.unwrap_or(true), Target::FULL)
            }
            None => {
                if following {
                    let shaped = curves::apply_gamma(frac, sun.gamma);
                    l.curve = Some((
                        !curves::wants_off(sun.min, sun.max, shaped),
                        curves::brightness_254(sun.min, sun.max, shaped),
                    ));
                }
                l.curve
                    .unwrap_or_else(|| (true, curves::brightness_254(sun.min, sun.max, 1.0)))
            }
        };
        let color_temp = l
            .cfg
            .color_temp
            .filter(|c| c.enabled)
            .map(|c| curves::color_temp(sun::day_progress(lat, lon, wall), c.warm, c.cool));
        Target {
            on,
            brightness,
            color_temp,
        }
    }

    fn action(
        &mut self,
        device: &str,
        action: &str,
        now: Instant,
        wall: DateTime<FixedOffset>,
    ) -> Vec<Out> {
        let Some(verb) = self
            .controls
            .get(device)
            .and_then(|a| a.get(action))
            .cloned()
        else {
            return Vec::new();
        };
        self.interaction_until = Some(now + self.interaction_hold);
        let targets: Vec<usize> = (0..self.lights.len())
            .filter(|&i| verb.lights().is_empty() || verb.lights().contains(&self.lights[i].name))
            .collect();
        for &i in &targets {
            self.lights[i].off_at = None;
        }
        let shown = |room: &Self, i: usize| room.lights[i].shown.filter(|t| t.on);
        let any_on = targets.iter().any(|&i| shown(self, i).is_some());

        let mut bulbs = BTreeMap::new();
        let mut set = |room: &mut Self, i: usize, t: Target| {
            bulbs.insert(room.lights[i].name.clone(), t);
        };
        match verb {
            Verb::Release => {
                return vec![Out::Release {
                    transition: self.fast.as_secs_f32(),
                }]
            }
            Verb::Toggle { .. } => {
                for &i in &targets {
                    let t = if any_on {
                        off()
                    } else {
                        self.on_at(i, None, wall)
                    };
                    set(self, i, t);
                }
            }
            Verb::DimThenOff { level, .. } => {
                let low = percent(level);
                let all_dim = targets
                    .iter()
                    .filter_map(|&i| shown(self, i))
                    .all(|t| t.brightness <= low.saturating_add(LOW_MARGIN));
                for &i in &targets {
                    let t = match (any_on, all_dim) {
                        (false, _) => self.on_at(i, None, wall),
                        (true, true) => off(),
                        (true, false) => self.on_at(i, Some(low), wall),
                    };
                    set(self, i, t);
                }
            }
            Verb::LowThenOff { level, after, .. } => {
                for &i in &targets {
                    let t = self.on_at(i, Some(percent(level)), wall);
                    set(self, i, t);
                    self.lights[i].off_at = Some(now + after);
                }
            }
            Verb::DimUp { step, .. } => {
                for &i in &targets {
                    let bri = shown(self, i).map_or(0, |t| t.brightness);
                    let t = self.on_at(
                        i,
                        Some(bri.saturating_add(percent(step)).min(Target::FULL)),
                        wall,
                    );
                    set(self, i, t);
                }
            }
            Verb::DimDown { step, .. } => {
                for &i in &targets {
                    if let Some(cur) = shown(self, i) {
                        let t = self.on_at(
                            i,
                            Some(cur.brightness.saturating_sub(percent(step)).max(1)),
                            wall,
                        );
                        set(self, i, t);
                    }
                }
            }
        }
        if bulbs.is_empty() {
            return Vec::new();
        }
        vec![self.user(bulbs)]
    }

    /// Light `i` on, at `brightness` or else the curve, in the curve's colour.
    fn on_at(&mut self, i: usize, brightness: Option<u8>, wall: DateTime<FixedOffset>) -> Target {
        let level = self.level(i, wall);
        Target {
            on: true,
            brightness: brightness.unwrap_or(level.brightness),
            ..level
        }
    }

    fn user(&self, bulbs: BTreeMap<String, Target>) -> Out {
        Out::User(Request {
            bulbs,
            scale: 1.0,
            transition: self.fast.as_secs_f32(),
        })
    }
}

fn apply(cfg: &mut Light, setting: Setting) {
    let sun = &mut cfg.sun;
    let wake = cfg.wake.get_or_insert_with(Wake::default);
    match setting {
        Setting::Enabled(v) => sun.enabled = v,
        Setting::FollowSunrise(v) => sun.follow_sunrise = v,
        Setting::FollowSunset(v) => sun.follow_sunset = v,
        Setting::Invert(v) => sun.invert = v,
        Setting::Min(v) => sun.min = v,
        Setting::Max(v) => sun.max = v,
        Setting::Gamma(v) => sun.gamma = v,
        Setting::Threshold(v) => sun.threshold = Some(v),
        Setting::ColorTemp(v) => {
            cfg.color_temp
                .get_or_insert_with(ColorTemp::default)
                .enabled = v
        }
        Setting::WakeAt(v) => wake.at = v,
        Setting::WakeMinutes(v) => wake.minutes = v,
        Setting::WakeMax(v) => wake.max = v,
        Setting::WakeGamma(v) => wake.gamma = v,
    }
}

/// How far into its window the wake ramp is, if it is running.
fn wake_progress(wake: Option<&Wake>, wall: DateTime<FixedOffset>) -> Option<(Wake, f64)> {
    let wake = *wake?;
    let start = wall.date_naive().and_time(wake.at);
    let elapsed = (wall.naive_local() - start).num_seconds() as f64;
    let total = f64::from(wake.minutes) * 60.0;
    (0.0..total)
        .contains(&elapsed)
        .then(|| (wake, elapsed / total))
}

fn percent(p: u8) -> u8 {
    (f64::from(p.min(100)) / 100.0 * f64::from(Target::FULL))
        .round()
        .max(1.0) as u8
}

fn off() -> Target {
    Target {
        on: false,
        brightness: 1,
        color_temp: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{json, Value};

    /// Around Berlin's solar noon at midsummer: daylight fraction ~1.
    const NOON: &str = "2026-06-21T13:10:00+02:00";
    const NIGHT: &str = "2026-06-21T01:00:00+02:00";
    const GRACE: u64 = 300;

    struct Rig {
        room: Room,
        now: Instant,
        wall: DateTime<FixedOffset>,
    }

    impl Rig {
        fn new(room: Value, wall: &str) -> Self {
            let mut cfg = json!({ "latitude": 52.52, "longitude": 13.405 });
            cfg.as_object_mut()
                .unwrap()
                .extend(room.as_object().unwrap().clone());
            let now = Instant::now();
            Self {
                room: Room::new(serde_json::from_value(cfg).unwrap(), now).unwrap(),
                now,
                wall: DateTime::parse_from_rfc3339(wall).unwrap(),
            }
        }

        /// Past the restart grace, with the room settled vacant.
        fn vacant(room: Value, wall: &str) -> Self {
            let mut rig = Self::new(room, wall);
            rig.send(Event::Tick);
            rig.wait(GRACE + 1);
            rig.wait(3600);
            assert_eq!(rig.room.occupancy(), Occupancy::Vacant);
            rig
        }

        fn send(&mut self, e: Event) -> Vec<Out> {
            self.room.step(e, self.now, self.wall)
        }

        fn wait(&mut self, secs: u64) -> Vec<Out> {
            self.now += Duration::from_secs(secs);
            self.wall += chrono::TimeDelta::seconds(secs as i64);
            self.send(Event::Tick)
        }

        fn motion(&mut self) -> Vec<Out> {
            self.sensor("motion", true)
        }

        fn sensor(&mut self, device: &str, active: bool) -> Vec<Out> {
            self.send(Event::Sensor {
                device: device.into(),
                active,
            })
        }

        fn door(&mut self, open: bool) -> Vec<Out> {
            self.send(Event::Door {
                device: "door".into(),
                open,
            })
        }

        fn press(&mut self, action: &str) -> Vec<Out> {
            self.send(Event::Action {
                device: "button".into(),
                action: action.into(),
            })
        }

        fn shows(&mut self, light: &str, held: bool, state: Target) -> Vec<Out> {
            self.send(Event::Bulb {
                light: light.into(),
                held,
                state,
            })
        }
    }

    fn on(brightness: u8) -> Target {
        Target {
            on: true,
            brightness,
            color_temp: None,
        }
    }

    /// Daytime: on and close to full.
    fn bright(t: Target) -> bool {
        t.on && t.brightness > 200
    }

    fn auto(outs: &[Out]) -> Option<&Request> {
        outs.iter().find_map(|o| match o {
            Out::Auto(r) => Some(r),
            _ => None,
        })
    }

    fn user(outs: &[Out]) -> Option<&Request> {
        outs.iter().find_map(|o| match o {
            Out::User(r) => Some(r),
            _ => None,
        })
    }

    fn released(outs: &[Out]) -> bool {
        outs.iter().any(|o| matches!(o, Out::Release { .. }))
    }

    fn hallway() -> Value {
        json!({
            "sources": [{ "type": "motion", "device": "motion", "hold": 90 }],
            "fade": 180,
            "lights": { "ceiling": { "turnOn": true } },
        })
    }

    fn bathroom() -> Value {
        json!({
            "sources": [
                { "type": "door", "device": "door", "hold": 60, "latchAfter": 20 },
                { "type": "presence", "device": "presence", "hold": 30 },
            ],
            "fade": 20,
            "lights": { "ceiling": { "turnOn": true } },
        })
    }

    fn bedroom() -> Value {
        json!({
            "sources": [{ "type": "motion", "device": "motion", "hold": 7200 }],
            "fade": 60,
            "lights": { "light": {} },
            "controls": { "button": {
                "single": { "action": "dimThenOff", "level": 10 },
                "hold": { "action": "lowThenOff", "level": 10, "after": 300 },
            } },
        })
    }

    #[test]
    fn hallway_turns_on_fast_and_fades_out_slowly() {
        let mut rig = Rig::vacant(hallway(), NOON);
        let outs = rig.motion();
        let req = auto(&outs).expect("turns on");
        assert!(bright(req.bulbs["ceiling"]));
        assert_eq!((req.scale, req.transition), (1.0, 0.4));

        assert!(auto(&rig.wait(60)).is_none(), "still within hold");
        let outs = rig.wait(31);
        let req = auto(&outs).expect("starts fading");
        assert_eq!((req.scale, req.transition), (0.0, 180.0));
        assert!(req.bulbs["ceiling"].on, "the arbiter does the fade");

        let outs = rig.wait(181);
        assert_eq!(rig.room.occupancy(), Occupancy::Vacant);
        assert!(released(&outs), "vacancy ends holds");
        assert!(!auto(&outs).unwrap().bulbs["ceiling"].on);
    }

    #[test]
    fn motion_during_the_fade_brings_the_light_straight_back() {
        let mut rig = Rig::vacant(hallway(), NOON);
        rig.motion();
        rig.wait(91);
        rig.wait(60);
        let outs = rig.motion();
        let req = auto(&outs).expect("back up");
        assert_eq!((req.scale, req.transition), (1.0, 0.4));
        assert!(!released(&outs));
    }

    #[test]
    fn deadline_points_at_the_end_of_the_hold() {
        let mut rig = Rig::vacant(hallway(), NOON);
        rig.motion();
        assert_eq!(rig.room.deadline(), Some(rig.now + Duration::from_secs(90)));
    }

    #[test]
    fn restart_counts_as_presence_for_a_grace_period() {
        let mut rig = Rig::new(hallway(), NOON);
        rig.send(Event::Tick);
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied);
        rig.wait(GRACE + 1);
        assert!(matches!(rig.room.occupancy(), Occupancy::Leaving { .. }));
    }

    #[test]
    fn night_level_is_the_floor() {
        let mut rig = Rig::vacant(hallway(), NIGHT);
        let outs = rig.motion();
        assert_eq!(auto(&outs).unwrap().bulbs["ceiling"], on(3));
    }

    #[test]
    fn shower_latches_the_bathroom_until_the_door_opens() {
        let mut rig = Rig::vacant(bathroom(), NOON);
        assert!(auto(&rig.door(true)).unwrap().bulbs["ceiling"].on);
        rig.sensor("presence", true);
        rig.door(false);
        rig.wait(25);
        // Standing still in the shower: the sensor loses you.
        rig.sensor("presence", false);
        rig.wait(3600);
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied);

        rig.door(true);
        rig.wait(61);
        assert!(matches!(rig.room.occupancy(), Occupancy::Leaving { .. }));
    }

    #[test]
    fn leaving_and_pulling_the_door_shut_does_not_latch() {
        let mut rig = Rig::vacant(bathroom(), NOON);
        rig.door(true);
        rig.sensor("presence", true);
        rig.wait(30);
        // The sensor still sees you for a moment after the door shuts.
        rig.door(false);
        rig.wait(10);
        rig.sensor("presence", false);
        rig.wait(11);
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied, "presence hold");
        rig.wait(20);
        assert!(matches!(rig.room.occupancy(), Occupancy::Leaving { .. }));
    }

    #[test]
    fn opening_the_door_turns_the_light_on_without_presence() {
        let mut rig = Rig::vacant(bathroom(), NOON);
        rig.door(true);
        rig.wait(59);
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied);
        rig.wait(2);
        assert!(matches!(rig.room.occupancy(), Occupancy::Leaving { .. }));
    }

    #[test]
    fn bedroom_motion_never_turns_the_light_on() {
        let mut rig = Rig::vacant(bedroom(), NIGHT);
        let outs = rig.motion();
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied);
        assert!(auto(&outs).is_none_or(|r| !r.bulbs["light"].on));
    }

    #[test]
    fn keep_on_light_follows_what_the_user_switched_on_until_vacancy() {
        let mut rig = Rig::vacant(bedroom(), NOON);
        rig.motion();
        let outs = rig.shows("light", true, on(100));
        assert!(auto(&outs).unwrap().bulbs["light"].on);

        rig.wait(7200);
        rig.wait(61);
        assert_eq!(rig.room.occupancy(), Occupancy::Vacant);
        // Back in the room: still off until someone switches it on.
        let outs = rig.motion();
        assert!(auto(&outs).is_none_or(|r| !r.bulbs["light"].on));
    }

    #[test]
    fn auto_state_reports_do_not_count_as_switching_on() {
        let mut rig = Rig::vacant(bedroom(), NOON);
        rig.motion();
        let outs = rig.shows("light", false, on(100));
        assert!(auto(&outs).is_none_or(|r| !r.bulbs["light"].on));
    }

    #[test]
    fn button_press_counts_as_someone_being_here() {
        let mut rig = Rig::vacant(bedroom(), NIGHT);
        rig.press("single");
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied);
    }

    #[test]
    fn dim_then_off_cycles_on_dim_off() {
        let mut rig = Rig::vacant(bedroom(), NOON);
        let outs = rig.press("single");
        assert!(bright(user(&outs).unwrap().bulbs["light"]));

        rig.shows("light", true, on(254));
        let outs = rig.press("single");
        assert_eq!(user(&outs).unwrap().bulbs["light"], on(25));

        rig.shows("light", true, on(25));
        let outs = rig.press("single");
        assert!(!user(&outs).unwrap().bulbs["light"].on);
    }

    #[test]
    fn low_then_off_switches_off_after_the_delay() {
        let mut rig = Rig::vacant(bedroom(), NIGHT);
        let outs = rig.press("hold");
        assert_eq!(user(&outs).unwrap().bulbs["light"], on(25));
        assert!(user(&rig.wait(299)).is_none());
        let outs = rig.wait(2);
        assert!(!user(&outs).unwrap().bulbs["light"].on);
    }

    #[test]
    fn another_press_cancels_low_then_off() {
        let mut rig = Rig::vacant(bedroom(), NIGHT);
        rig.press("hold");
        rig.shows("light", true, on(25));
        rig.wait(100);
        rig.press("single");
        assert!(user(&rig.wait(300)).is_none());
    }

    #[test]
    fn room_toggle_with_mixed_state_turns_everything_off_first() {
        let room = json!({
            "lights": { "a": {}, "b": {} },
            "controls": { "button": { "double": { "action": "toggle" } } },
        });
        let mut rig = Rig::new(room, NOON);
        rig.shows("a", false, on(254));
        let outs = rig.press("double");
        let req = user(&outs).unwrap();
        assert!(!req.bulbs["a"].on && !req.bulbs["b"].on);

        rig.shows("a", true, Target { on: false, ..on(1) });
        let req = user(&rig.press("double")).cloned().unwrap();
        assert!(req.bulbs["a"].on && req.bulbs["b"].on);
    }

    #[test]
    fn room_without_sources_is_always_occupied() {
        let mut rig = Rig::new(json!({ "lights": { "a": {} } }), NOON);
        rig.wait(86_400);
        assert_eq!(rig.room.occupancy(), Occupancy::Occupied);
        assert_eq!(rig.room.deadline(), None);
    }

    #[test]
    fn plug_threshold_switches_with_daylight() {
        let room = json!({ "lights": { "plug": { "turnOn": true, "sun": { "threshold": 15 } } } });
        let mut rig = Rig::new(room.clone(), NOON);
        assert!(auto(&rig.send(Event::Tick)).unwrap().bulbs["plug"].on);
        let mut rig = Rig::new(room, NIGHT);
        assert!(!auto(&rig.send(Event::Tick)).unwrap().bulbs["plug"].on);
    }

    #[test]
    fn colour_temperature_is_warm_at_night_and_cool_at_noon() {
        let room = json!({ "lights": { "a": { "turnOn": true, "colorTemp": {} } } });
        let ct = |wall| {
            let mut rig = Rig::new(room.clone(), wall);
            auto(&rig.send(Event::Tick)).unwrap().bulbs["a"].color_temp
        };
        assert_eq!(ct(NIGHT), Some(454));
        assert!(ct(NOON).unwrap() < 260);
    }

    #[test]
    fn sun_disabled_freezes_the_level() {
        let room = json!({ "lights": { "a": { "turnOn": true } } });
        let mut rig = Rig::new(room, NOON);
        rig.send(Event::Tick);
        rig.send(Event::Setting {
            light: "a".into(),
            setting: Setting::Enabled(false),
        });
        rig.wall = DateTime::parse_from_rfc3339(NIGHT).unwrap();
        assert!(auto(&rig.send(Event::Tick)).is_none(), "nothing moved");
    }

    #[test]
    fn floor_setting_applies_at_night() {
        let mut rig = Rig::vacant(hallway(), NIGHT);
        rig.send(Event::Setting {
            light: "ceiling".into(),
            setting: Setting::Min(5),
        });
        assert_eq!(auto(&rig.motion()).unwrap().bulbs["ceiling"], on(13));
    }

    #[test]
    fn wake_ramp_releases_holds_turns_on_and_keeps_the_room_occupied() {
        let room = json!({
            "sources": [{ "type": "motion", "device": "motion", "hold": 7200 }],
            "fade": 60,
            "lights": { "light": { "wake": { "at": "06:30:00", "minutes": 45, "max": 30 } } },
        });
        // `vacant` advances the clock by 3901s: this lands on 05:30.
        let mut rig = Rig::vacant(room, "2026-06-21T04:24:59+02:00");
        assert!(!released(&rig.wait(59 * 60)));
        let outs = rig.wait(60);
        assert!(released(&outs), "06:30: holds released");
        let first = auto(&outs).unwrap().bulbs["light"];
        assert!(first.on && first.brightness < 10);

        let later = auto(&rig.wait(30 * 60)).unwrap().bulbs["light"];
        assert!(later.brightness > first.brightness);
        assert!(!released(&rig.wait(60)));

        // Ramp over: the light stays on, now as if switched on by hand.
        let outs = rig.wait(14 * 60);
        assert!(auto(&outs).unwrap().bulbs["light"].on);
        // Nobody stirred, so the room winds down like any other.
        assert!(matches!(rig.room.occupancy(), Occupancy::Leaving { .. }));
    }

    #[test]
    fn identical_ticks_publish_nothing() {
        let mut rig = Rig::new(hallway(), NOON);
        assert!(auto(&rig.send(Event::Tick)).is_some());
        assert!(rig.send(Event::Tick).is_empty());
    }

    #[test]
    fn controls_naming_unknown_lights_are_rejected() {
        let cfg = json!({
            "latitude": 0.0, "longitude": 0.0,
            "lights": { "a": {} },
            "controls": { "button": { "single": { "action": "toggle", "lights": ["nope"] } } },
        });
        assert!(Room::new(serde_json::from_value(cfg).unwrap(), Instant::now()).is_err());
    }

    #[test]
    fn config_rejects_typos() {
        let cfg =
            json!({ "latitude": 0.0, "longitude": 0.0, "lights": { "a": { "turnon": true } } });
        assert!(serde_json::from_value::<Config>(cfg).is_err());
    }
}
