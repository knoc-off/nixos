//! Simplified NOAA solar calculations.
//!
//! Accurate to ~1 minute for latitudes below ~65 degrees.
//! Reference: <https://gml.noaa.gov/grad/solcalc/solareqns.PDF>
//!
//! Generic over any [`chrono::TimeZone`] — callers pass `chrono::Local` to get
//! times in the host's configured timezone (`time.timeZone` in NixOS).

use chrono::{DateTime, Datelike, Duration, NaiveDate, TimeZone, Timelike, Utc};

use std::f64::consts::PI;

/// Calculate sunrise time for a given location and date.
pub fn sunrise<Tz: TimeZone>(lat: f64, lon: f64, date: NaiveDate, tz: Tz) -> DateTime<Tz> {
    solar_event(lat, lon, date, tz, true)
}

/// Calculate sunset time for a given location and date.
pub fn sunset<Tz: TimeZone>(lat: f64, lon: f64, date: NaiveDate, tz: Tz) -> DateTime<Tz> {
    solar_event(lat, lon, date, tz, false)
}

/// Solar noon — the moment the sun reaches its highest point.
///
/// Only depends on longitude (not latitude) and the equation of time.
pub fn solar_noon<Tz: TimeZone>(lon: f64, date: NaiveDate, tz: Tz) -> DateTime<Tz> {
    let day_of_year = date.ordinal() as f64;
    let gamma = 2.0 * PI / 365.0 * (day_of_year - 1.0);
    let (eqtime, _) = solar_params(gamma);
    let noon_minutes_utc = 720.0 - 4.0 * lon - eqtime;

    let base = date
        .and_hms_opt(0, 0, 0)
        .expect("valid midnight")
        .and_utc();
    let utc = base + Duration::seconds((noon_minutes_utc * 60.0) as i64);
    utc.with_timezone(&tz)
}

/// Solar elevation angle (degrees above horizon) at a given instant.
///
/// Negative values mean the sun is below the horizon.
/// Key thresholds:
///   -18  astronomical twilight
///   -12  nautical twilight
///    -6  civil twilight (sky noticeably brightening)
///     0  geometric sunrise/sunset
pub fn elevation<Tz: TimeZone>(lat: f64, lon: f64, dt: DateTime<Tz>) -> f64 {
    let utc = dt.with_timezone(&Utc);
    let day_of_year = utc.ordinal() as f64;

    // Fractional year — include hour for intra-day precision.
    let hour = utc.hour() as f64 + utc.minute() as f64 / 60.0 + utc.second() as f64 / 3600.0;
    let gamma = 2.0 * PI / 365.0 * (day_of_year - 1.0 + (hour - 12.0) / 24.0);

    let (eqtime, decl) = solar_params(gamma);
    let lat_rad = lat.to_radians();

    // True solar time (minutes).
    let tst = hour * 60.0 + eqtime + 4.0 * lon;

    // Hour angle (radians). Solar noon = 0.
    let ha = ((tst / 4.0) - 180.0).to_radians();

    let sin_elev = lat_rad.sin() * decl.sin() + lat_rad.cos() * decl.cos() * ha.cos();
    sin_elev.clamp(-1.0, 1.0).asin().to_degrees()
}

/// Fraction of daylight brightness at a given instant, in `0.0..=1.0`.
///
/// Normalized against *today's* peak elevation (at solar noon) rather than a
/// fixed angle, so it reaches 1.0 at local noon year-round -- Berlin's ~14
/// degree winter noon would otherwise never be "bright" relative to a
/// summer-calibrated scale. Civil twilight (-6 degrees) and below is 0.0.
pub fn daylight_fraction<Tz: TimeZone>(lat: f64, lon: f64, dt: DateTime<Tz>) -> f64 {
    const HORIZON: f64 = -6.0;

    let date = dt.with_timezone(&Utc).date_naive();
    let noon = solar_noon(lon, date, Utc);
    let peak = elevation(lat, lon, noon);

    if peak <= HORIZON {
        return 0.0; // polar night -- sun never clears twilight today
    }

    let elev = elevation(lat, lon, dt);
    ((elev - HORIZON) / (peak - HORIZON)).clamp(0.0, 1.0)
}

/// Equation of time (minutes) and solar declination (radians).
fn solar_params(gamma: f64) -> (f64, f64) {
    let eqtime = 229.18
        * (0.000075 + 0.001868 * gamma.cos()
            - 0.032077 * gamma.sin()
            - 0.014615 * (2.0 * gamma).cos()
            - 0.040849 * (2.0 * gamma).sin());

    let decl = 0.006918 - 0.399912 * gamma.cos() + 0.070257 * gamma.sin()
        - 0.006758 * (2.0 * gamma).cos()
        + 0.000907 * (2.0 * gamma).sin()
        - 0.002697 * (3.0 * gamma).cos()
        + 0.00148 * (3.0 * gamma).sin();

    (eqtime, decl)
}

fn solar_event<Tz: TimeZone>(
    lat: f64,
    lon: f64,
    date: NaiveDate,
    tz: Tz,
    is_rise: bool,
) -> DateTime<Tz> {
    let day_of_year = date.ordinal() as f64;
    let gamma = 2.0 * PI / 365.0 * (day_of_year - 1.0);

    let (eqtime, decl) = solar_params(gamma);
    let lat_rad = lat.to_radians();

    let cos_ha = (90.833f64.to_radians().cos()) / (lat_rad.cos() * decl.cos())
        - lat_rad.tan() * decl.tan();
    let ha = cos_ha.clamp(-1.0, 1.0).acos().to_degrees();

    let solar_noon = 720.0 - 4.0 * lon - eqtime;

    let minutes_utc = if is_rise {
        solar_noon - ha * 4.0
    } else {
        solar_noon + ha * 4.0
    };

    let base = date
        .and_hms_opt(0, 0, 0)
        .expect("valid midnight")
        .and_utc();
    let utc = base + Duration::seconds((minutes_utc * 60.0) as i64);
    utc.with_timezone(&tz)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{NaiveDate, Utc};

    // Tests use UTC directly rather than a named timezone (no chrono-tz
    // dependency) — Berlin is UTC+1/+2, so expected hours are shifted
    // accordingly relative to local-time intuition.
    const BERLIN_LAT: f64 = 52.52;
    const BERLIN_LON: f64 = 13.405;

    #[test]
    fn berlin_summer_sunrise_is_reasonable() {
        // Local sunrise ~04:45 CEST (UTC+2) => ~02:45 UTC.
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, Utc);
        assert!(rise.hour() >= 2 && rise.hour() <= 3, "got {rise}");
    }

    #[test]
    fn berlin_winter_sunrise_is_reasonable() {
        // Local sunrise ~08:15 CET (UTC+1) => ~07:15 UTC.
        let date = NaiveDate::from_ymd_opt(2025, 12, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, Utc);
        assert!(rise.hour() >= 6 && rise.hour() <= 8, "got {rise}");
    }

    #[test]
    fn elevation_near_zero_at_sunrise() {
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, Utc);
        let elev = elevation(BERLIN_LAT, BERLIN_LON, rise);
        assert!(
            elev.abs() < 2.0,
            "elevation at sunrise should be near 0, got {elev:.2}"
        );
    }

    #[test]
    fn elevation_negative_at_midnight() {
        let dt = NaiveDate::from_ymd_opt(2025, 6, 21)
            .unwrap()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc();
        let elev = elevation(BERLIN_LAT, BERLIN_LON, dt);
        assert!(elev < -5.0, "should be well below horizon at midnight, got {elev:.2}");
    }

    #[test]
    fn elevation_peaks_at_solar_noon_summer() {
        // Solar noon in Berlin summer solstice is ~13:15 CEST = 11:15 UTC.
        let dt = NaiveDate::from_ymd_opt(2025, 6, 21)
            .unwrap()
            .and_hms_opt(11, 15, 0)
            .unwrap()
            .and_utc();
        let elev = elevation(BERLIN_LAT, BERLIN_LON, dt);
        assert!(
            elev > 55.0 && elev < 65.0,
            "summer noon elevation should be ~61, got {elev:.2}"
        );
    }

    #[test]
    fn solar_noon_is_reasonable() {
        // Berlin solar noon is ~13:15 CEST in summer = ~11:15 UTC.
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let noon = solar_noon(BERLIN_LON, date, Utc);
        assert!(noon.hour() >= 11 && noon.hour() <= 12, "got {noon}");
    }

    #[test]
    fn elevation_increases_during_morning() {
        let early = NaiveDate::from_ymd_opt(2025, 3, 21)
            .unwrap()
            .and_hms_opt(5, 0, 0)
            .unwrap()
            .and_utc();
        let later = NaiveDate::from_ymd_opt(2025, 3, 21)
            .unwrap()
            .and_hms_opt(8, 0, 0)
            .unwrap()
            .and_utc();
        let e1 = elevation(BERLIN_LAT, BERLIN_LON, early);
        let e2 = elevation(BERLIN_LAT, BERLIN_LON, later);
        assert!(e2 > e1, "elevation should increase during morning: {e1:.2} -> {e2:.2}");
    }

    #[test]
    fn daylight_fraction_zero_at_midnight() {
        let dt = NaiveDate::from_ymd_opt(2025, 6, 21)
            .unwrap()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc();
        let f = daylight_fraction(BERLIN_LAT, BERLIN_LON, dt);
        assert_eq!(f, 0.0, "got {f}");
    }

    #[test]
    fn daylight_fraction_peaks_at_solar_noon() {
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let noon = solar_noon(BERLIN_LON, date, Utc);
        let f = daylight_fraction(BERLIN_LAT, BERLIN_LON, noon);
        assert!((f - 1.0).abs() < 0.01, "got {f}");
    }

    #[test]
    fn daylight_fraction_near_zero_at_sunrise() {
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, Utc);
        let f = daylight_fraction(BERLIN_LAT, BERLIN_LON, rise);
        assert!(f < 0.1, "got {f}");
    }

    #[test]
    fn daylight_fraction_monotonic_through_morning() {
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let noon = solar_noon(BERLIN_LON, date, Utc);
        let mut prev = -1.0;
        let mut t = noon - Duration::hours(6);
        while t <= noon {
            let f = daylight_fraction(BERLIN_LAT, BERLIN_LON, t);
            assert!(f >= prev, "not monotonic at {t}: {prev} -> {f}");
            prev = f;
            t += Duration::minutes(30);
        }
    }

    #[test]
    fn daylight_fraction_nonzero_at_winter_noon() {
        // The whole point of normalizing against today's peak: Berlin's ~14
        // degree winter noon must still read as "full brightness" locally.
        let date = NaiveDate::from_ymd_opt(2025, 12, 21).unwrap();
        let noon = solar_noon(BERLIN_LON, date, Utc);
        let f = daylight_fraction(BERLIN_LAT, BERLIN_LON, noon);
        assert!((f - 1.0).abs() < 0.01, "winter noon should still be 1.0, got {f}");
    }
}
