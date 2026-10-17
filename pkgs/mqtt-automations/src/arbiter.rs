//! Per-bulb ownership for the light arbiter: decides, for one bulb, whether
//! the automation or the user is in charge, and what (if anything) to
//! publish. Pure -- no MQTT, no wall clock; the caller passes `now` and
//! calls back with `Input::Tick` at [`Bulb::deadline`].
//!
//! Generalises sun_follow.rs's ownership machine. Rooms only *ask* for a
//! target; this is the one place that decides whether the bulb listens:
//!   - `Auto`: the bulb follows the automation target.
//!   - `Held`: the user set a value -- via a button (`Input::User`), or in
//!     HA/the app, seen as a z2m report we didn't cause. The automation's
//!     target is ignored until a `Release`, or until it converges onto the
//!     held value.
//!
//! On top of either, the room's `scale` (0..1) dims the output: that is how
//! a leaving room fades out. It applies to held bulbs too, so the warning
//! dim covers user settings, but the held value itself is stored unscaled,
//! so coming back restores it exactly.
//!
//! Because the arbiter is the only writer, override detection reduces to
//! "the bulb reports something other than what we commanded" -- compared
//! against where a running transition should be by now, after a short
//! settle window that absorbs report latency.

use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

/// Also the wire format rooms use for per-bulb targets.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub struct Target {
    pub on: bool,
    /// Z2M scale, 1-254. Meaningless while `on` is false; optional on the
    /// wire because plugs have none.
    #[serde(default = "Target::full")]
    pub brightness: u8,
    /// Mireds. `None` for bulbs/plugs without colour temperature.
    #[serde(default)]
    pub color_temp: Option<u16>,
}

impl Target {
    /// Top of z2m's brightness scale.
    pub const FULL: u8 = 254;

    fn full() -> u8 {
        Self::FULL
    }
}

impl Target {
    /// Whether two states look different to a person, given `tol`.
    /// Brightness and colour temperature don't matter while off; a missing
    /// colour temperature on either side (plug, or a report that omitted it)
    /// is not a difference.
    fn differs(self, other: Target, tol: Tolerance) -> bool {
        if self.on != other.on {
            return true;
        }
        if !self.on {
            return false;
        }
        let ct = match (self.color_temp, other.color_temp) {
            (Some(a), Some(b)) => a.abs_diff(b) > tol.color_temp,
            _ => false,
        };
        self.brightness.abs_diff(other.brightness) > tol.brightness || ct
    }

    /// Perceived level for interpolation: off is brightness zero.
    fn level(self) -> f32 {
        if self.on {
            self.brightness.into()
        } else {
            0.0
        }
    }
}

/// One command for z2m.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Command {
    pub target: Target,
    pub transition: Duration,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Hold {
    pub value: Target,
    /// Set when the user acted while the room was already fading: they
    /// chose that exact output, so the fade stops applying to this bulb
    /// for the rest of the hold instead of fighting them.
    pub ignores_fade: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// Waiting for both a z2m report and an automation target, so startup
    /// can adopt the bulb where it is instead of jumping.
    Unknown,
    Auto,
    Held(Hold),
}

#[derive(Clone, Copy, Debug)]
pub enum Input {
    /// What the room's automation wants for this bulb, and how far the
    /// room is faded (1 = full, 0 = off).
    Auto {
        target: Target,
        scale: f32,
        transition: Duration,
    },
    /// A button gesture the room interpreted: apply it and hold.
    User {
        target: Target,
        transition: Duration,
    },
    /// The room hit a reset point (vacancy, wake ramp): back to `Auto`.
    Release { transition: Duration },
    /// A z2m state message for this bulb.
    Report(Target),
    /// The time returned by [`Bulb::deadline`] has come.
    Tick,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Tolerance {
    pub brightness: u8,
    pub color_temp: u16,
}

impl Tolerance {
    const EXACT: Self = Self {
        brightness: 0,
        color_temp: 0,
    };
}

#[derive(Clone, Copy, Debug)]
pub struct Config {
    /// A report further than this from what we commanded is a user change.
    /// Also how close the auto target must come for a hold to converge.
    pub change: Tolerance,
    /// Startup only: a bulb this close to the target is adopted as `Auto`
    /// (the correction is small enough to be invisible), else held as-is.
    pub adopt: Tolerance,
    /// How long after a publish reports are ignored outright: z2m reports
    /// lag the command, so the first ones still show the old state.
    pub settle: Duration,
    /// False for plugs: on/off only, no brightness, no colour temperature,
    /// and a fade can't dim them -- they switch off when it ends.
    pub dimmable: bool,
}

impl Default for Config {
    // Tolerances are the values sun_follow.rs and color_temp_cycle.rs run
    // with today; settle matches sun_follow's default transition + 1s.
    fn default() -> Self {
        Self {
            change: Tolerance {
                brightness: 5,
                color_temp: 15,
            },
            adopt: Tolerance {
                brightness: 25,
                color_temp: 50,
            },
            settle: Duration::from_secs(3),
            dimmable: true,
        }
    }
}

/// Where the bulb should be at any moment of a transition we commanded.
#[derive(Clone, Copy, Debug)]
struct Motion {
    from: Target,
    to: Target,
    start: Instant,
    duration: Duration,
}

impl Motion {
    fn still(t: Target, now: Instant) -> Self {
        Self {
            from: t,
            to: t,
            start: now,
            duration: Duration::ZERO,
        }
    }

    fn progress(&self, now: Instant) -> f32 {
        if self.duration.is_zero() {
            return 1.0;
        }
        let elapsed = now.saturating_duration_since(self.start);
        (elapsed.as_secs_f32() / self.duration.as_secs_f32()).min(1.0)
    }

    fn at(&self, now: Instant) -> Target {
        let p = self.progress(now);
        if p >= 1.0 {
            return self.to;
        }
        let lerp = |a: f32, b: f32| a + (b - a) * p;
        Target {
            // A bulb fading to off stays on until the very end; one fading
            // on is on from the start.
            on: self.from.on || self.to.on,
            brightness: lerp(self.from.level(), self.to.level()).round().max(1.0) as u8,
            color_temp: match (self.from.color_temp, self.to.color_temp) {
                (Some(a), Some(b)) => Some(lerp(a.into(), b.into()).round() as u16),
                (_, b) => b,
            },
        }
    }

    /// Whether report `r` is just this transition playing out. z2m often
    /// reports the commanded end state straight away (optimistic state);
    /// a bulb that reports on its own shows somewhere along the curve, up
    /// to one `settle` period behind.
    ///
    /// During a fade (longer than `settle`), anywhere back to its start
    /// counts: a command z2m had to retry over a weak link starts late, and
    /// a bulb still at the start level is not someone setting it there.
    /// Short transitions keep the tight window, so a quick change right
    /// after a switch-on still reads as the user's.
    fn explains(&self, r: Target, now: Instant, cfg: Config) -> bool {
        let fading = self.duration > cfg.settle && now < self.start + self.duration + cfg.settle;
        let behind = if fading {
            self.from
        } else {
            self.at(now.checked_sub(cfg.settle).unwrap_or(now))
        };
        !self.to.differs(r, cfg.change) || within(r, behind, self.at(now), cfg.change)
    }
}

/// Whether `r` lies between `a` and `b` (give or take `tol`): on or off
/// like one of them, and brightness and colour temperature in their span.
fn within(r: Target, a: Target, b: Target, tol: Tolerance) -> bool {
    if r.on != a.on && r.on != b.on {
        return false;
    }
    if !r.on {
        return true;
    }
    let span = |x: f32, y: f32, v: f32, tol: f32| x.min(y) - tol <= v && v <= x.max(y) + tol;
    let bri = span(
        a.level(),
        b.level(),
        r.brightness.into(),
        tol.brightness.into(),
    );
    let ct = match (r.color_temp, a.color_temp, b.color_temp) {
        (Some(v), Some(x), Some(y)) => span(x.into(), y.into(), v.into(), tol.color_temp.into()),
        _ => true,
    };
    bri && ct
}

#[derive(Debug)]
pub struct Bulb {
    pub mode: Mode,
    cfg: Config,
    auto: Option<Target>,
    prev_auto: Option<Target>,
    auto_transition: Duration,
    scale: f32,
    reported: Option<Target>,
    /// What the bulb should be showing: our last command, or a report we
    /// accepted as the new truth (adoption, user override).
    expected: Option<Motion>,
    settle_until: Option<Instant>,
    /// Plug fade-off: the moment the fade ends and the plug switches off.
    switch_off_at: Option<Instant>,
}

impl Bulb {
    pub fn new(cfg: Config) -> Self {
        Self {
            mode: Mode::Unknown,
            cfg,
            auto: None,
            prev_auto: None,
            auto_transition: Duration::ZERO,
            scale: 1.0,
            reported: None,
            expected: None,
            settle_until: None,
            switch_off_at: None,
        }
    }

    /// The held value, if the user is in charge.
    pub fn held(&self) -> Option<Target> {
        match self.mode {
            Mode::Held(h) => Some(h.value),
            _ => None,
        }
    }

    /// When to call back with `Input::Tick`, if ever.
    pub fn deadline(&self) -> Option<Instant> {
        self.switch_off_at
    }

    /// What the bulb should be showing now (our last command, or the state
    /// we accepted from a report), once anything is known.
    pub fn showing(&self) -> Option<Target> {
        self.expected.map(|m| m.to)
    }

    /// Feed one input; returns the command to publish, if any.
    pub fn step(&mut self, input: Input, now: Instant) -> Option<Command> {
        match input {
            Input::Auto {
                target,
                scale,
                transition,
            } => {
                let target = self.normalize(target);
                self.prev_auto = self.auto.replace(target);
                self.auto_transition = transition;
                self.scale = scale.clamp(0.0, 1.0);
                match self.mode {
                    Mode::Unknown => return self.try_adopt(now),
                    Mode::Held(h) if self.converged(h.value, target) => self.mode = Mode::Auto,
                    _ => {}
                }
                self.apply(transition, now)
            }
            Input::User { target, transition } => {
                let target = self.normalize(target);
                self.hold(target);
                self.apply(transition, now)
            }
            Input::Release { transition } => {
                self.mode = Mode::Auto;
                self.apply(transition, now)
            }
            Input::Report(r) => {
                let r = self.normalize(r);
                self.reported = Some(r);
                if self.settle_until.is_some_and(|until| now < until) {
                    return None;
                }
                if self.mode == Mode::Unknown {
                    return self.try_adopt(now);
                }
                match self.expected {
                    Some(m) if m.explains(r, now, self.cfg) => {}
                    Some(_) => {
                        self.hold(r);
                        self.accept(r, now);
                    }
                    // Released before any target existed: nothing to
                    // override yet, just learn where the bulb is.
                    None => self.accept(r, now),
                }
                None
            }
            Input::Tick => {
                if self.switch_off_at.is_none_or(|at| now < at) {
                    return None;
                }
                self.switch_off_at = None;
                let off = Target {
                    on: false,
                    ..self.expected?.to
                };
                self.send(off, Duration::ZERO, now)
            }
        }
    }

    fn try_adopt(&mut self, now: Instant) -> Option<Command> {
        let (Some(r), Some(t)) = (self.reported, self.auto) else {
            return None;
        };
        self.accept(r, now);
        if r.differs(self.shape(t, self.scale), self.cfg.adopt) {
            // Covers an off bulb the automation wants on (never wake it on a
            // restart) and an on bulb it wants off (never yank it).
            self.hold(r);
            None
        } else {
            self.mode = Mode::Auto;
            self.apply(self.auto_transition, now)
        }
    }

    fn hold(&mut self, value: Target) {
        self.mode = Mode::Held(Hold {
            value,
            ignores_fade: self.scale < 1.0,
        });
    }

    /// Take `r` as what the bulb is now showing, cancelling any transition.
    fn accept(&mut self, r: Target, now: Instant) {
        self.expected = Some(Motion::still(r, now));
        self.switch_off_at = None;
    }

    /// A hold ends by itself once the automation comes back to the user's
    /// value: within tolerance, or the curve crossed it since the last
    /// target. Crossing matters because a slow curve stepping past the held
    /// value can skip the tolerance band entirely. Nearness alone (as in
    /// adoption) would snap a deliberate setting back to the curve.
    /// Off never converges -- a manual off only ends at a real release.
    fn converged(&self, held: Target, t: Target) -> bool {
        if !held.on || !t.on {
            return false;
        }
        let prev = self.prev_auto.filter(|p| p.on);
        let tol = self.cfg.change;
        let bri = reached(
            prev.map(|p| p.brightness.into()),
            t.brightness.into(),
            held.brightness.into(),
            tol.brightness.into(),
        );
        let ct = match (held.color_temp, t.color_temp) {
            (Some(h), Some(c)) => reached(
                prev.and_then(|p| p.color_temp).map(Into::into),
                c.into(),
                h.into(),
                tol.color_temp.into(),
            ),
            _ => true,
        };
        bri && ct
    }

    /// Plugs have one channel; dropping the rest at every entry point means
    /// nothing downstream compares a brightness the plug never had.
    fn normalize(&self, t: Target) -> Target {
        if self.cfg.dimmable {
            t
        } else {
            Target {
                brightness: Target::FULL,
                color_temp: None,
                ..t
            }
        }
    }

    /// `t` dimmed by the room's fade. A plug stays on until the fade is
    /// complete.
    fn shape(&self, t: Target, scale: f32) -> Target {
        let on = t.on && scale > 0.0;
        if !self.cfg.dimmable {
            return Target { on, ..t };
        }
        let brightness = (f32::from(t.brightness) * scale).round().max(1.0) as u8;
        Target {
            on,
            brightness,
            ..t
        }
    }

    /// Publish whatever the current mode and fade call for.
    fn apply(&mut self, transition: Duration, now: Instant) -> Option<Command> {
        let (value, scale) = match self.mode {
            Mode::Unknown => return None,
            Mode::Auto => (self.auto?, self.scale),
            Mode::Held(h) if h.ignores_fade => (h.value, 1.0),
            Mode::Held(h) => (h.value, self.scale),
        };
        let t = self.shape(value, scale);
        if self.cfg.dimmable {
            return self.send(t, transition, now);
        }
        // A plug can't dim, so a room fading out is a delayed off: the plug
        // stays on for the length of the fade, then switches (see
        // `Input::Tick`). Rooms resend their target on every tick, which
        // must not postpone the deadline.
        let fading_out = value.on && !t.on && !transition.is_zero();
        if fading_out && self.expected.is_some_and(|m| m.to.on) {
            self.switch_off_at.get_or_insert(now + transition);
            return None;
        }
        self.switch_off_at = None;
        self.send(t, Duration::ZERO, now)
    }

    fn send(&mut self, t: Target, transition: Duration, now: Instant) -> Option<Command> {
        if self
            .expected
            .is_some_and(|m| !m.to.differs(t, Tolerance::EXACT))
        {
            return None;
        }
        let from = self
            .expected
            .map(|m| m.at(now))
            .or(self.reported)
            .unwrap_or(t);
        self.expected = Some(Motion {
            from,
            to: t,
            start: now,
            duration: transition,
        });
        self.settle_until = Some(now + self.cfg.settle);
        Some(Command {
            target: t,
            transition,
        })
    }
}

/// Whether a curve moving from `prev` to `now` has reached `goal`: it is
/// within `tol`, or it stepped from one side of `goal` to the other.
fn reached(prev: Option<i32>, now: i32, goal: i32, tol: i32) -> bool {
    let side = |v: i32| (v - goal).signum();
    (now - goal).abs() <= tol || prev.is_some_and(|p| side(p) * side(now) < 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    const SETTLE: Duration = Duration::from_secs(3);
    const FAST: Duration = Duration::from_millis(400);
    const FADE: Duration = Duration::from_secs(180);
    const OFF: Target = Target {
        on: false,
        brightness: 1,
        color_temp: None,
    };

    fn on(brightness: u8) -> Target {
        Target {
            on: true,
            brightness,
            color_temp: None,
        }
    }

    fn on_ct(brightness: u8, ct: u16) -> Target {
        Target {
            on: true,
            brightness,
            color_temp: Some(ct),
        }
    }

    fn auto(target: Target) -> Input {
        Input::Auto {
            target,
            scale: 1.0,
            transition: FAST,
        }
    }

    fn fade(target: Target, scale: f32) -> Input {
        Input::Auto {
            target,
            scale,
            transition: FADE,
        }
    }

    fn user(target: Target) -> Input {
        Input::User {
            target,
            transition: FAST,
        }
    }

    const RELEASE: Input = Input::Release { transition: FAST };

    fn secs(s: u64) -> Duration {
        Duration::from_secs(s)
    }

    struct Rig {
        bulb: Bulb,
        now: Instant,
    }

    impl Rig {
        fn new(cfg: Config) -> Self {
            Self {
                bulb: Bulb::new(cfg),
                now: Instant::now(),
            }
        }

        /// Adopted into `Auto` at `t`, clock past settle.
        fn auto_at(cfg: Config, t: Target) -> Self {
            let mut rig = Self::new(cfg);
            rig.send(Input::Report(t));
            rig.send(auto(t));
            assert_eq!(rig.bulb.mode, Mode::Auto);
            rig.wait(SETTLE * 2);
            rig
        }

        fn light(t: Target) -> Self {
            Self::auto_at(Config::default(), t)
        }

        fn plug(t: Target) -> Self {
            Self::auto_at(
                Config {
                    dimmable: false,
                    ..Config::default()
                },
                t,
            )
        }

        fn send(&mut self, input: Input) -> Option<Target> {
            self.bulb.step(input, self.now).map(|c| c.target)
        }

        fn wait(&mut self, d: Duration) {
            self.now += d;
        }
    }

    #[test]
    fn adopts_near_target_as_auto() {
        let mut rig = Rig::new(Config::default());
        assert_eq!(rig.send(Input::Report(on(100))), None);
        assert_eq!(rig.send(auto(on(110))), Some(on(110)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn adoption_waits_for_report_and_target_in_either_order() {
        let mut rig = Rig::new(Config::default());
        assert_eq!(rig.send(auto(on(110))), None);
        assert_eq!(rig.bulb.mode, Mode::Unknown);
        assert_eq!(rig.send(Input::Report(on(100))), Some(on(110)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn adopts_far_bulb_as_held_without_jumping() {
        let mut rig = Rig::new(Config::default());
        rig.send(Input::Report(on(30)));
        assert_eq!(rig.send(auto(on(200))), None);
        assert_eq!(rig.bulb.held(), Some(on(30)));
    }

    #[test]
    fn restart_never_wakes_an_off_bulb_or_yanks_an_on_one() {
        let mut rig = Rig::new(Config::default());
        rig.send(Input::Report(OFF));
        assert_eq!(rig.send(auto(on(100))), None);
        assert_eq!(rig.bulb.held(), Some(OFF));

        let mut rig = Rig::new(Config::default());
        rig.send(Input::Report(on(100)));
        assert_eq!(rig.send(auto(OFF)), None);
        assert_eq!(rig.bulb.held(), Some(on(100)));
    }

    #[test]
    fn auto_follows_target_and_skips_duplicates() {
        let mut rig = Rig::light(on(100));
        assert_eq!(rig.send(auto(on(120))), Some(on(120)));
        assert_eq!(rig.send(auto(on(120))), None);
    }

    #[test]
    fn off_targets_differing_only_in_brightness_are_not_republished() {
        let mut rig = Rig::light(OFF);
        let dim_off = Target {
            brightness: 80,
            ..OFF
        };
        assert_eq!(rig.send(auto(dim_off)), None);
    }

    #[test]
    fn own_echo_during_settle_is_not_an_override() {
        let mut rig = Rig::light(on(100));
        rig.send(auto(on(200)));
        rig.wait(secs(1));
        rig.send(Input::Report(on(150)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn app_change_outside_settle_holds_and_ignores_automation() {
        let mut rig = Rig::light(on(100));
        rig.send(Input::Report(on(40)));
        assert_eq!(rig.bulb.held(), Some(on(40)));
        assert_eq!(rig.send(auto(on(130))), None);
    }

    #[test]
    fn app_off_holds_off() {
        let mut rig = Rig::light(on(100));
        rig.send(Input::Report(OFF));
        assert_eq!(rig.bulb.held(), Some(OFF));
    }

    #[test]
    fn bulb_rounding_is_neither_override_nor_republish() {
        let mut rig = Rig::light(on(100));
        rig.send(Input::Report(on(102)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
        assert_eq!(rig.send(auto(on(100))), None);
    }

    #[test]
    fn colour_temperature_only_change_holds() {
        let mut rig = Rig::light(on_ct(100, 300));
        rig.send(Input::Report(on_ct(100, 454)));
        assert_eq!(rig.bulb.held(), Some(on_ct(100, 454)));
    }

    #[test]
    fn user_holds_and_release_returns_to_current_target() {
        let mut rig = Rig::light(on(100));
        assert_eq!(rig.send(user(on(20))), Some(on(20)));
        assert_eq!(rig.send(auto(on(140))), None);
        assert_eq!(rig.send(RELEASE), Some(on(140)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn hold_converges_when_curve_reaches_the_held_value() {
        let mut rig = Rig::light(on(100));
        rig.send(user(on(60)));
        assert_eq!(rig.send(auto(on(80))), None);
        assert_eq!(rig.send(auto(on(63))), Some(on(63)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn hold_converges_when_curve_steps_across_the_held_value() {
        let mut rig = Rig::light(on(100));
        rig.send(user(on(60)));
        rig.send(auto(on(70)));
        assert_eq!(rig.send(auto(on(50))), Some(on(50)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn hold_does_not_snap_back_when_merely_nearby() {
        // Within the startup adoption band, but a deliberate setting.
        let mut rig = Rig::light(on(100));
        rig.send(user(on(100)));
        assert_eq!(rig.send(auto(on(120))), None);
        assert_eq!(rig.send(auto(on(119))), None);
        assert_eq!(rig.bulb.held(), Some(on(100)));
    }

    #[test]
    fn held_off_never_converges() {
        let mut rig = Rig::light(on(100));
        rig.send(user(OFF));
        rig.send(auto(OFF));
        assert_eq!(rig.send(auto(on(50))), None);
        assert_eq!(rig.bulb.held(), Some(OFF));
    }

    #[test]
    fn held_colour_survives_brightness_convergence() {
        let mut rig = Rig::light(on_ct(100, 300));
        rig.send(user(on_ct(60, 454)));
        rig.send(auto(on_ct(70, 300)));
        assert_eq!(rig.send(auto(on_ct(50, 300))), None);
        assert_eq!(rig.bulb.held(), Some(on_ct(60, 454)));
    }

    #[test]
    fn fade_dims_auto_output_over_the_fade_and_restores_on_return() {
        let mut rig = Rig::light(on(200));
        let cmd = rig.bulb.step(fade(on(200), 0.5), rig.now);
        assert_eq!(
            cmd,
            Some(Command {
                target: on(100),
                transition: FADE
            })
        );
        assert_eq!(rig.send(auto(on(200))), Some(on(200)));
    }

    #[test]
    fn fade_to_zero_turns_a_light_off() {
        let mut rig = Rig::light(on(200));
        assert_eq!(rig.send(fade(on(200), 0.0)).map(|t| t.on), Some(false));
    }

    #[test]
    fn fade_dims_held_bulbs_but_keeps_the_held_value() {
        let mut rig = Rig::light(on(200));
        rig.send(user(on(80)));
        assert_eq!(rig.send(fade(on(200), 0.5)), Some(on(40)));
        assert_eq!(rig.bulb.held(), Some(on(80)));
        assert_eq!(rig.send(auto(on(200))), Some(on(80)));
    }

    #[test]
    fn reports_tracking_a_long_fade_are_not_overrides() {
        // Halfway through a 180s fade from 200 to off, reported a few
        // seconds behind the curve.
        let mut rig = Rig::light(on(200));
        rig.send(fade(OFF, 1.0));
        rig.wait(secs(90));
        rig.send(Input::Report(on(104)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn late_starting_fade_is_not_an_override() {
        // Seen live: a 30s fade-out whose command z2m delivered late, so the
        // bulb still reported its start level 13s in, then off.
        let mut rig = Rig::light(on(247));
        rig.send(Input::Auto {
            target: on(247),
            scale: 0.0,
            transition: secs(30),
        });
        rig.wait(secs(13));
        rig.send(Input::Report(on(247)));
        rig.send(Input::Report(OFF));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn optimistic_end_state_report_during_a_fade_is_not_an_override() {
        let mut rig = Rig::light(on(200));
        rig.send(fade(OFF, 1.0));
        rig.wait(secs(10));
        rig.send(Input::Report(OFF));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn plug_already_off_schedules_nothing() {
        let mut rig = Rig::plug(on(254));
        rig.send(user(OFF));
        rig.send(fade(on(254), 0.0));
        assert_eq!(rig.bulb.deadline(), None);
    }

    #[test]
    fn app_change_during_a_long_fade_is_an_override() {
        let mut rig = Rig::light(on(200));
        rig.send(fade(OFF, 1.0));
        rig.wait(secs(90));
        rig.send(Input::Report(on(220)));
        assert_eq!(rig.bulb.held(), Some(on(220)));
    }

    #[test]
    fn app_change_after_a_finished_short_transition_is_an_override() {
        // A 0.4s turn-on from off spans every level from 0 to 254; once it
        // has finished, a dim report must not pass for it playing out.
        let mut rig = Rig::light(OFF);
        rig.send(auto(on(254)));
        rig.wait(secs(5));
        rig.send(Input::Report(on(20)));
        assert_eq!(rig.bulb.held(), Some(on(20)));
    }

    #[test]
    fn override_during_a_fade_stops_the_fade_for_that_bulb() {
        let mut rig = Rig::light(on(200));
        rig.send(fade(on(200), 0.5));
        rig.wait(secs(90));
        rig.send(Input::Report(on(220)));
        // The room keeps fading; the bulb stays where the user put it.
        assert_eq!(rig.send(fade(on(200), 0.2)), None);
        assert_eq!(rig.send(fade(on(200), 0.0)), None);
        // Release (vacancy) ends the hold and the exemption with it.
        assert_eq!(
            rig.send(Input::Release { transition: FADE }).map(|t| t.on),
            Some(false)
        );
    }

    #[test]
    fn plug_ignores_brightness_and_colour() {
        let mut rig = Rig::plug(on(254));
        assert_eq!(rig.send(auto(on_ct(30, 454))), None);
        rig.send(Input::Report(on(1)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
    }

    #[test]
    fn plug_stays_on_through_a_fade_and_switches_off_at_the_end() {
        let mut rig = Rig::plug(on(254));
        assert_eq!(rig.send(fade(on(254), 0.3)), None);
        assert_eq!(rig.send(fade(on(254), 0.0)), None);
        let at = rig.bulb.deadline().expect("off scheduled");
        assert_eq!(at, rig.now + FADE);
        rig.wait(secs(90));
        rig.send(Input::Report(on(254)));
        assert_eq!(rig.bulb.mode, Mode::Auto);
        assert_eq!(rig.send(Input::Tick), None);
        rig.now = at;
        let cmd = rig.bulb.step(Input::Tick, rig.now).expect("switch off");
        assert!(!cmd.target.on);
        assert_eq!(cmd.transition, Duration::ZERO);
        assert_eq!(rig.bulb.deadline(), None);
    }

    #[test]
    fn plug_fade_off_deadline_is_not_postponed_by_resends() {
        let mut rig = Rig::plug(on(254));
        rig.send(fade(on(254), 0.0));
        let at = rig.bulb.deadline();
        rig.wait(secs(60));
        rig.send(fade(on(254), 0.0));
        assert_eq!(rig.bulb.deadline(), at);
    }

    #[test]
    fn plug_fade_off_is_cancelled_by_coming_back() {
        let mut rig = Rig::plug(on(254));
        rig.send(fade(on(254), 0.0));
        rig.wait(secs(60));
        // Still on, so nothing to publish -- just the off is called off.
        assert_eq!(rig.send(auto(on(254))), None);
        assert_eq!(rig.bulb.deadline(), None);
    }

    #[test]
    fn plug_turned_off_in_app_during_fade_is_held_off() {
        let mut rig = Rig::plug(on(254));
        rig.send(fade(on(254), 0.0));
        rig.wait(secs(60));
        rig.send(Input::Report(OFF));
        assert_eq!(rig.bulb.held().map(|t| t.on), Some(false));
        assert_eq!(rig.bulb.deadline(), None);
    }
}
