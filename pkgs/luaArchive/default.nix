{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "luaarchive";
  version = "0.1.0";  # You may want to update this version number

  src = fetchFromGitHub {
    owner = "SteamRE";
    repo = "LuaArchive";
    rev = "master";  # You might want to use a specific commit hash or tag instead
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";  # Replace with the actual hash
  };

  buildPhase = "make";

  installPhase = ''
    mkdir -p $out/bin
    cp LuaArchive $out/bin/
  '';

  meta = with lib; {
    description = "A tool to extract Lua archives used by Tabletop Simulator";
    homepage = "https://github.com/SteamRE/LuaArchive";
    license = licenses.mit;  # Adjust if the license is different
    platforms = platforms.unix;
    maintainers = with maintainers; [ ];  # Add your name if you want
  };
}
