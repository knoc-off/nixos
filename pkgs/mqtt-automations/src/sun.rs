//! Simplified NOAA solar calculations.
//!
//! Accurate to ~1 minute for latitudes below ~65 degrees.
//! Reference: <https://gml.noaa.gov/grad/solcalc/solareqns.PDF>

use chrono::{DateTime, Datelike, Duration, NaiveDate, Timelike, Utc};
use chrono_tz::Tz;

use std::f64::consts::PI;

/// Calculate sunrise time for a given location and date.
pub fn sunrise(lat: f64, lon: f64, date: NaiveDate, tz: &Tz) -> DateTime<Tz> {
    solar_event(lat, lon, date, tz, true)
}

/// Calculate sunset time for a given location and date.
pub fn sunset(lat: f64, lon: f64, date: NaiveDate, tz: &Tz) -> DateTime<Tz> {
    solar_event(lat, lon, date, tz, false)
}

/// Solar elevation angle (degrees above horizon) at a given instant.
///
/// Negative values mean the sun is below the horizon.
/// Key thresholds:
///   -18  astronomical twilight
///   -12  nautical twilight
///    -6  civil twilight (sky noticeably brightening)
///     0  geometric sunrise/sunset
pub fn elevation(lat: f64, lon: f64, dt: DateTime<Tz>) -> f64 {
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

fn solar_event(lat: f64, lon: f64, date: NaiveDate, tz: &Tz, is_rise: bool) -> DateTime<Tz> {
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
    utc.with_timezone(tz)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    const BERLIN_LAT: f64 = 52.52;
    const BERLIN_LON: f64 = 13.405;

    fn berlin() -> Tz {
        "Europe/Berlin".parse().unwrap()
    }

    #[test]
    fn berlin_summer_sunrise_is_reasonable() {
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, &berlin());
        assert!(rise.hour() >= 4 && rise.hour() <= 5, "got {rise}");
    }

    #[test]
    fn berlin_winter_sunrise_is_reasonable() {
        let date = NaiveDate::from_ymd_opt(2025, 12, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, &berlin());
        assert!(rise.hour() >= 7 && rise.hour() <= 9, "got {rise}");
    }

    #[test]
    fn elevation_near_zero_at_sunrise() {
        let tz = berlin();
        let date = NaiveDate::from_ymd_opt(2025, 6, 21).unwrap();
        let rise = sunrise(BERLIN_LAT, BERLIN_LON, date, &tz);
        let elev = elevation(BERLIN_LAT, BERLIN_LON, rise);
        assert!(
            elev.abs() < 2.0,
            "elevation at sunrise should be near 0, got {elev:.2}"
        );
    }

    #[test]
    fn elevation_negative_at_midnight() {
        let tz = berlin();
        let dt = NaiveDate::from_ymd_opt(2025, 6, 21)
            .unwrap()
            .and_hms_opt(0, 0, 0)
            .unwrap()
            .and_utc()
            .with_timezone(&tz);
        let elev = elevation(BERLIN_LAT, BERLIN_LON, dt);
        assert!(elev < -5.0, "should be well below horizon at midnight, got {elev:.2}");
    }

    #[test]
    fn elevation_peaks_at_solar_noon_summer() {
        let tz = berlin();
        // Solar noon in Berlin summer solstice is ~13:15 CEST = 11:15 UTC.
        let dt = NaiveDate::from_ymd_opt(2025, 6, 21)
            .unwrap()
            .and_hms_opt(11, 15, 0)
            .unwrap()
            .and_utc()
            .with_timezone(&tz);
        let elev = elevation(BERLIN_LAT, BERLIN_LON, dt);
        assert!(
            elev > 55.0 && elev < 65.0,
            "summer noon elevation should be ~61, got {elev:.2}"
        );
    }

    #[test]
    fn print_elevation_at_8am() {
        let tz = berlin();
        // April 1 (tomorrow-ish)
        for (label, month, day) in [
            ("Apr 1 ", 4, 1),
            ("Jun 21", 6, 21),
            ("Sep 21", 9, 21),
            ("Dec 21", 12, 21),
        ] {
            let dt = NaiveDate::from_ymd_opt(2026, month, day)
                .unwrap()
                .and_hms_opt(6, 0, 0) // 08:00 CEST/CET = 06:00 UTC
                .unwrap()
                .and_utc()
                .with_timezone(&tz);
            let elev = elevation(BERLIN_LAT, BERLIN_LON, dt);
            let rise = sunrise(BERLIN_LAT, BERLIN_LON,
                NaiveDate::from_ymd_opt(2026, month, day).unwrap(), &tz);
            eprintln!("{label}: sunrise={} elev@08:00={:.1}°", rise.format("%H:%M"), elev);
        }
    }

    #[test]
    fn elevation_increases_during_morning() {
        let tz = berlin();
        let early = NaiveDate::from_ymd_opt(2025, 3, 21)
            .unwrap()
            .and_hms_opt(5, 0, 0)
            .unwrap()
            .and_utc()
            .with_timezone(&tz);
        let later = NaiveDate::from_ymd_opt(2025, 3, 21)
            .unwrap()
            .and_hms_opt(8, 0, 0)
            .unwrap()
            .and_utc()
            .with_timezone(&tz);
        let e1 = elevation(BERLIN_LAT, BERLIN_LON, early);
        let e2 = elevation(BERLIN_LAT, BERLIN_LON, later);
        assert!(e2 > e1, "elevation should increase during morning: {e1:.2} -> {e2:.2}");
    }
}
