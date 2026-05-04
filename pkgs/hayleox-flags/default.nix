# Country and sub-national flag SVGs from hayleox/flags.
#
# Hierarchical directory structure: de.svg (country), de/by.svg
# (state), us/ca/juneau.svg (county). 611 SVGs with the deepest
# sub-national coverage of any free flag collection.
#
# No explicit license file; flags are sourced from public domain /
# freely usable government emblems.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "hayleox-flags";
  version = "unstable-2017-11-17";

  src = fetchFromGitHub {
    owner = "hayleox";
    repo = "flags";
    rev = "5dba8401a30e63c693c80bf5bf1e3ed0625b0009";
    hash = "sha256-KCMNJuri6IxeQstrenjrOogppMKea36Ls+hTMe8QiOo=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/hayleox-flags
    cp -r svg/* $out/share/hayleox-flags/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Country and sub-national flag SVGs (hierarchical) for marki-media";
    homepage = "https://github.com/hayleox/flags";
    license = licenses.free;
    platforms = platforms.all;
  };
}
