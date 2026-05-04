# Sub-national and country flag SVGs from fonttools/region-flags.
#
# Provides ~3,400 SVG flag files using ISO 3166-1 (country) and
# ISO 3166-2 (subdivision) codes: DE.svg, DE-BY.svg, US-CA.svg, etc.
#
# Data is public domain (sourced from Wikimedia Commons).
#
# Consumers read MARKID_MEDIA_DIR env, which the markid home-manager
# module sets to the build output of this derivation (or a merged
# directory that also includes iso-flags).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "region-flags";
  version = "1.2.1";

  src = fetchFromGitHub {
    owner = "fonttools";
    repo = "region-flags";
    rev = "1.2.1";
    hash = "sha256-q4MkOf11vSBRYMFfjnDQN/U3ZZTJKa3K9P5qzvn45mQ=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/region-flags
    cp svg/*.svg $out/share/region-flags/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Country and sub-national flag SVGs (ISO 3166-1 + ISO 3166-2) for marki-media";
    homepage = "https://github.com/fonttools/region-flags";
    license = licenses.publicDomain;
    platforms = platforms.all;
  };
}
