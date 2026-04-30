//! External data sources: Natural Earth (offline, bundled via Nix
//! derivation + `NATURAL_EARTH_DATA` env) and Overpass (online, with
//! content-addressable cache).

pub mod natural_earth;
pub mod overpass;
