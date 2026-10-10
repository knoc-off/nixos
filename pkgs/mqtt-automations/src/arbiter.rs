//! Per-bulb ownership for the light arbiter: decides, for one bulb, whether
//! the automation or the user is in charge, and what (if anything) to
//! publish. Pure -- no MQTT, no wall clock; the caller passes `now`.
//!
//! Generalises sun_follow.rs's ownership machine. Rooms only *ask* for a
//! target; this is the one place that decides whether the bulb listens:
//!   - `Auto`: the bulb follows the automation target.
//!   - `Held(v)`: the user set `v` -- via a button (`Input::User`), or in
//!     HA/the app, seen as a z2m report we didn't cause. The automation is
//!     ignored until a `Release`, or until its target converges onto `v`.
//!
//! Because the arbiter is the only writer, override detection reduces to
//! "the bulb reports something other than what we last commanded, outside
//! the settle window after our own publish".

use std::time::{Duration, Instant};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Target {
    pub on: bool,
    /// Z2M scale, 1-254. Meaningless while `on` is false.
    pub brightness: u8,
    /// Mireds. `None` for bulbs/plugs without colour temperature.
    pub color_temp: Option<u16>,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Mode {
    /// Waiting for both a z2m report and an automation target, so startup
    /// can adopt the bulb where it is instead of jumping.
    Unknown,
    Auto,
    Held(Target),
}

#[derive(Clone, Copy, Debug)]
pub enum Input {
    /// What the room's automation wants for this bulb.
    Auto(Target),
    /// A button gesture the room interpreted: apply it and hold.
    User(Target),
    /// The room hit a reset point (vacancy, wake ramp): back to `Auto`.
    Release,
    /// A z2m state message for this bulb.
    Report(Target),
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
}

#[derive(Clone, Copy, Debug)]
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
pub struct Tolerances {
    /// A report further than this from what we commanded is a user change.
    /// Also how close the auto target must come for a hold to converge.
    pub change: Tolerance,
    /// Startup only: a bulb this close to the target is adopted as `Auto`
    /// (the correction is small enough to be invisible), else held as-is.
    pub adopt: Tolerance,
}

impl Default for Tolerances {
    // Same values sun_follow.rs and color_temp_cycle.rs run with today.
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
        }
    }
}

#[derive(Debug)]
pub struct Bulb {
    pub mode: Mode,
    tol: Tolerances,
    settle: Duration,
    auto: Option<Target>,
    prev_auto: Option<Target>,
    reported: Option<Target>,
    /// What the bulb should be showing: our last command, or a report we
    /// accepted as the new truth (adoption, user override).
    expected: Option<Target>,
    settle_until: Option<Instant>,
}

impl Bulb {
    /// `settle`: how long after a publish reports are ignored, so the tail
    /// of our own transition isn't mistaken for a user change.
    pub fn new(tol: Tolerances, settle: Duration) -> Self {
        Self {
            mode: Mode::Unknown,
            tol,
            settle,
            auto: None,
            prev_auto: None,
            reported: None,
            expected: None,
            settle_until: None,
        }
    }

    /// Feed one input; returns the command to publish, if any.
    pub fn step(&mut self, input: Input, now: Instant) -> Option<Target> {
        match input {
            Input::Auto(t) => {
                self.prev_auto = self.auto.replace(t);
                match self.mode {
                    Mode::Unknown => self.try_adopt(now),
                    Mode::Auto => self.publish(t, now),
                    Mode::Held(h) if self.converged(h, t) => {
                        self.mode = Mode::Auto;
                        self.publish(t, now)
                    }
                    Mode::Held(_) => None,
                }
            }
            Input::User(t) => {
                self.mode = Mode::Held(t);
                self.publish(t, now)
            }
            Input::Release => {
                self.mode = Mode::Auto;
                self.publish(self.auto?, now)
            }
            Input::Report(r) => {
                self.reported = Some(r);
                if self.settle_until.is_some_and(|until| now < until) {
                    return None;
                }
                if self.mode == Mode::Unknown {
                    return self.try_adopt(now);
                }
                match self.expected {
                    Some(e) if e.differs(r, self.tol.change) => {
                        self.mode = Mode::Held(r);
                        self.expected = Some(r);
                    }
                    Some(_) => {}
                    // Released before any target existed: nothing to
                    // override yet, just learn where the bulb is.
                    None => self.expected = Some(r),
                }
                None
            }
        }
    }

    fn try_adopt(&mut self, now: Instant) -> Option<Target> {
        let (Some(r), Some(t)) = (self.reported, self.auto) else {
            return None;
        };
        self.expected = Some(r);
        if r.differs(t, self.tol.adopt) {
            // Covers an off bulb the automation wants on (never wake it on a
            // restart) and an on bulb it wants off (never yank it).
            self.mode = Mode::Held(r);
            None
        } else {
            self.mode = Mode::Auto;
            self.publish(t, now)
        }
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
        let tol = self.tol.change;
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

    fn publish(&mut self, t: Target, now: Instant) -> Option<Target> {
        if self
            .expected
            .is_some_and(|e| !e.differs(t, Tolerance::EXACT))
        {
            return None;
        }
        self.expected = Some(t);
        self.settle_until = Some(now + self.settle);
        Some(t)
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

    fn bulb() -> Bulb {
        Bulb::new(Tolerances::default(), SETTLE)
    }

    /// A bulb already adopted into `Auto` at `t`, plus a clock past settle.
    fn auto_bulb(t: Target) -> (Bulb, Instant) {
        let now = Instant::now();
        let mut b = bulb();
        b.step(Input::Report(t), now);
        b.step(Input::Auto(t), now);
        assert_eq!(b.mode, Mode::Auto);
        (b, now + SETTLE * 2)
    }

    #[test]
    fn adopts_near_target_as_auto() {
        let now = Instant::now();
        let mut b = bulb();
        assert_eq!(b.step(Input::Report(on(100)), now), None);
        assert_eq!(b.step(Input::Auto(on(110)), now), Some(on(110)));
        assert_eq!(b.mode, Mode::Auto);
    }

    #[test]
    fn adoption_waits_for_report_and_target_in_either_order() {
        let now = Instant::now();
        let mut b = bulb();
        assert_eq!(b.step(Input::Auto(on(110)), now), None);
        assert_eq!(b.mode, Mode::Unknown);
        assert_eq!(b.step(Input::Report(on(100)), now), Some(on(110)));
        assert_eq!(b.mode, Mode::Auto);
    }

    #[test]
    fn adopts_far_bulb_as_held_without_jumping() {
        let now = Instant::now();
        let mut b = bulb();
        b.step(Input::Report(on(30)), now);
        assert_eq!(b.step(Input::Auto(on(200)), now), None);
        assert_eq!(b.mode, Mode::Held(on(30)));
    }

    #[test]
    fn restart_never_wakes_an_off_bulb_or_yanks_an_on_one() {
        let now = Instant::now();
        let mut b = bulb();
        b.step(Input::Report(OFF), now);
        assert_eq!(b.step(Input::Auto(on(100)), now), None);
        assert_eq!(b.mode, Mode::Held(OFF));

        let mut b = bulb();
        b.step(Input::Report(on(100)), now);
        assert_eq!(b.step(Input::Auto(OFF), now), None);
        assert_eq!(b.mode, Mode::Held(on(100)));
    }

    #[test]
    fn auto_follows_target_and_skips_duplicates() {
        let (mut b, now) = auto_bulb(on(100));
        assert_eq!(b.step(Input::Auto(on(120)), now), Some(on(120)));
        assert_eq!(b.step(Input::Auto(on(120)), now), None);
    }

    #[test]
    fn off_targets_differing_only_in_brightness_are_not_republished() {
        let (mut b, now) = auto_bulb(OFF);
        assert_eq!(
            b.step(
                Input::Auto(Target {
                    brightness: 80,
                    ..OFF
                }),
                now
            ),
            None
        );
    }

    #[test]
    fn own_echo_during_settle_is_not_an_override() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::Auto(on(200)), now);
        // Mid-transition report, still inside the settle window.
        b.step(Input::Report(on(150)), now + Duration::from_secs(1));
        assert_eq!(b.mode, Mode::Auto);
    }

    #[test]
    fn app_change_outside_settle_holds_and_ignores_automation() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::Report(on(40)), now);
        assert_eq!(b.mode, Mode::Held(on(40)));
        assert_eq!(b.step(Input::Auto(on(130)), now), None);
    }

    #[test]
    fn app_off_holds_off() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::Report(OFF), now);
        assert_eq!(b.mode, Mode::Held(OFF));
    }

    #[test]
    fn bulb_rounding_is_neither_override_nor_republish() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::Report(on(102)), now);
        assert_eq!(b.mode, Mode::Auto);
        assert_eq!(b.step(Input::Auto(on(100)), now), None);
    }

    #[test]
    fn colour_temperature_only_change_holds() {
        let (mut b, now) = auto_bulb(on_ct(100, 300));
        b.step(Input::Report(on_ct(100, 454)), now);
        assert_eq!(b.mode, Mode::Held(on_ct(100, 454)));
    }

    #[test]
    fn user_holds_and_release_returns_to_current_target() {
        let (mut b, now) = auto_bulb(on(100));
        assert_eq!(b.step(Input::User(on(20)), now), Some(on(20)));
        assert_eq!(b.step(Input::Auto(on(140)), now), None);
        assert_eq!(b.step(Input::Release, now), Some(on(140)));
        assert_eq!(b.mode, Mode::Auto);
    }

    #[test]
    fn hold_converges_when_curve_reaches_the_held_value() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::User(on(60)), now);
        assert_eq!(b.step(Input::Auto(on(80)), now), None);
        assert_eq!(b.step(Input::Auto(on(63)), now), Some(on(63)));
        assert_eq!(b.mode, Mode::Auto);
    }

    #[test]
    fn hold_converges_when_curve_steps_across_the_held_value() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::User(on(60)), now);
        b.step(Input::Auto(on(70)), now);
        assert_eq!(b.step(Input::Auto(on(50)), now), Some(on(50)));
        assert_eq!(b.mode, Mode::Auto);
    }

    #[test]
    fn hold_does_not_snap_back_when_merely_nearby() {
        // Within the startup adoption band, but a deliberate setting.
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::User(on(100)), now);
        assert_eq!(b.step(Input::Auto(on(120)), now), None);
        assert_eq!(b.step(Input::Auto(on(119)), now), None);
        assert_eq!(b.mode, Mode::Held(on(100)));
    }

    #[test]
    fn held_off_never_converges() {
        let (mut b, now) = auto_bulb(on(100));
        b.step(Input::User(OFF), now);
        b.step(Input::Auto(OFF), now);
        assert_eq!(b.step(Input::Auto(on(50)), now), None);
        assert_eq!(b.mode, Mode::Held(OFF));
    }

    #[test]
    fn held_colour_survives_brightness_convergence() {
        let (mut b, now) = auto_bulb(on_ct(100, 300));
        b.step(Input::User(on_ct(60, 454)), now);
        b.step(Input::Auto(on_ct(70, 300)), now);
        assert_eq!(b.step(Input::Auto(on_ct(50, 300)), now), None);
        assert_eq!(b.mode, Mode::Held(on_ct(60, 454)));
    }
}
