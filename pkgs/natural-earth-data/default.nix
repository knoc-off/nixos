# Natural Earth 10m vector data — countries, admin-1 regions,
# coastline. Bundled here so `marki-map` can resolve `country/<iso>`,
# `admin1/<iso>/<name>`, and `coastline` references at runtime without
# touching the network.
#
# Data is in the public domain (Natural Earth's terms).
#
# Consumers read NATURAL_EARTH_DATA env, which the markid home-manager
# module sets to the build output of this derivation.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:
stdenvNoCC.mkDerivation {
  pname = "natural-earth-data";
  version = "5.1.2";

  srcs = [
    (fetchurl {
      url = "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip";
      sha256 = "1xm7718x7jma194aiv6j95mgk64s436r7h7v87bfv84rch1wf6nf";
    })
    (fetchurl {
      url = "https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_1_states_provinces.zip";
      sha256 = "019bp9ccna1xxrk3c1af6k6pjcb7jvf0l8a6jj7ha8vk6ck9gigg";
    })
    (fetchurl {
      url = "https://naciscdn.org/naturalearth/10m/physical/ne_10m_coastline.zip";
      sha256 = "05s091ay40wk707xy4x102cs5v32h2san7favy8fy1zgrgdlr85z";
    })
  ];

  nativeBuildInputs = [unzip];

  # No source unpack happens automatically when `srcs` is multiple
  # archives; do it ourselves so each zip lands flat in $out.
  unpackPhase = ''
    runHook preUnpack
    for src in $srcs; do
      unzip -q "$src"
    done
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r ne_10m_* $out/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Natural Earth 10m vector data (countries, admin-1, coastline) for marki-map";
    homepage = "https://www.naturalearthdata.com/";
    license = licenses.publicDomain;
    platforms = platforms.all;
  };
}
