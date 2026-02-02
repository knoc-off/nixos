{ pkgs }:

let
  avrTools = with pkgs.pkgsCross.avr; [
    buildPackages.gcc
    buildPackages.binutils
  ];

  arduinoTools = with pkgs; [
    arduino-core
    arduino-mk
    arduino-cli
    avrdude
  ];

in
pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    gcc
    gdb
    valgrind
    clang-tools
    bear
    sccache
    pkg-config
    cmake
    ninja
    meson
  ] ++ avrTools ++ arduinoTools;

  buildInputs = with pkgs; [
    libusb-compat-0_1
  ];

  ARDUINO_DIR = "${pkgs.arduino-core}/share/arduino";
  ARDMK_DIR = "${pkgs.arduino-mk}";
  BOARD_TAG = "uno";
  MONITOR_PORT = "/dev/ttyACM0";

  shellHook = ''
    export PATH="$ARDUINO_DIR:$ARDMK_DIR:$PATH"
    echo "Arduino development environment ready!"
    echo "ARDUINO_DIR: $ARDUINO_DIR"
    echo "ARDMK_DIR: $ARDMK_DIR"
    echo "BOARD_TAG: $BOARD_TAG"
    echo "MONITOR_PORT: $MONITOR_PORT"
  '';
}

