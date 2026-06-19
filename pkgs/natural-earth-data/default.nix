# Natural Earth 10m physical coastline vector data. Bundled here so
# `marki-map` can resolve the `coastline` reference at runtime without
# touching the network. (Country / admin boundaries now come from the
# `geoboundaries-data` derivation; Natural Earth is kept for coastline
# only, which geoBoundaries does not provide.)
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
    description = "Natural Earth 10m coastline vector data for marki-map";
    homepage = "https://www.naturalearthdata.com/";
    license = licenses.publicDomain;
    platforms = platforms.all;
  };
}
