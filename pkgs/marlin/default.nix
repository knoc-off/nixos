{ lib
, stdenv
, fetchFromGitHub
, cmake
, ninja
, platformio
, platformio-core
}:

stdenv.mkDerivation rec {
  pname = "marlin";
  version = "2.1.2.4";

  src = fetchFromGitHub {
    owner = "MarlinFirmware";
    repo = "Marlin";
    rev = "fff0d70";
    sha256 = "sha256-OQ7bUvc2W54UqzsoxgATQg3yl1v9e+8duJI7bL2fvII=";
  };

  patches = [
    ./patches/platformio.patch # Change Board to ender
  ];

  nativeBuildInputs = [
    platformio # needs to be configured, and set to offline
    platformio-core
  ];

  configurePhase = ''
    mkdir coredir
    cp -r ${./libraries/coredir}/* ./coredir
    cp ${./config/Configuration.h} ./Marlin/Configuration.h
    cp ${./config/Configuration_adv.h} Marlin/Configuration_adv.h

    # Give write permissions to the build user
    chmod -R u+w .

    ls -l
  '';

  buildPhase = ''
    # Build Marlin using PlatformIO
    platformio run
  '';

  installPhase = ''
    # Install the compiled firmware
    mkdir -p $out/firmware
    #cp .pio/build/*/firmware.bin $out/firmware/firmware.bin
    cp .pio/build/*/firmware*.* -r "$out/firmware"
  '';

}
