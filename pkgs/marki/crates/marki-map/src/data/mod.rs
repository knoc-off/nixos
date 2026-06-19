//! External data sources:
//!   * geoBoundaries gbOpen — offline admin boundaries (countries,
//!     adm1/2/3, continent/subregion groupings, neighbours), bundled via
//!     the `geoboundaries-data` derivation + `GEOBOUNDARIES_DATA` env.
//!   * Natural Earth — offline `coastline` only, via the
//!     `natural-earth-data` derivation + `NATURAL_EARTH_DATA` env.
//!   * Overpass — online, with content-addressable cache.

pub mod geo_common;
pub mod geoboundaries;
pub mod natural_earth;
pub mod overpass;
