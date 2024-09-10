{ pkgs ? import <nixpkgs> {} }:

let
  avrPkgs = pkgs.pkgsCross.avr.buildPackages;

  arduinoCorePath = "${pkgs.arduino-core-unwrapped}/share/arduino/hardware/arduino/avr/cores/arduino";
  arduinoVariantPath = "${pkgs.arduino-core-unwrapped}/share/arduino/hardware/arduino/avr/variants/standard";
  arduinoLibPath = "${pkgs.arduino-core-unwrapped}/share/arduino/libraries";

  max7219Src = pkgs.fetchFromGitHub {
    owner = "libdriver";
    repo = "max7219";
    rev = "main";
    sha256 = "sha256-icqfV33JlBb0+Z+R3rfCnk39VsMya4vaaIrFNJyUYPs=";
  };

  compile-avr = pkgs.writeShellScriptBin "compile-avr" ''
    set -e
    TMPDIR=$(mktemp -d)
    #trap 'rm -rf "$TMPDIR"' EXIT

    # Compile Arduino core files
    for file in ${arduinoCorePath}/*.cpp ${arduinoCorePath}/*.c; do
      if [ -f "$file" ]; then
        filename=$(basename "$file")
        if [[ "$filename" == *.cpp ]]; then
          ${avrPkgs.gcc}/bin/avr-g++ -c -g -Os -w -std=gnu++11 -fpermissive -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics -Wno-error=narrowing -mmcu=atmega328p -DF_CPU=16000000L -DARDUINO=10813 -I${arduinoCorePath} -I${arduinoVariantPath} -I${arduinoLibPath} "$file" -o "$TMPDIR/$filename.o"
        else
          ${avrPkgs.gcc}/bin/avr-gcc -c -g -Os -w -std=gnu11 -ffunction-sections -fdata-sections -mmcu=atmega328p -DF_CPU=16000000L -DARDUINO=10813 -I${arduinoCorePath} -I${arduinoVariantPath} -I${arduinoLibPath} "$file" -o "$TMPDIR/$filename.o"
        fi
      fi
    done

    # Compile MAX7219 library
    ${avrPkgs.gcc}/bin/avr-g++ -c -g -Os -w -std=gnu++11 -fpermissive -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics -Wno-error=narrowing -mmcu=atmega328p -DF_CPU=16000000L -DARDUINO=10813 -I${arduinoCorePath} -I${arduinoVariantPath} -I${arduinoLibPath} -I${max7219Src}/src -I${max7219Src}/interface ${max7219Src}/src/driver_max7219.c -o "$TMPDIR/driver_max7219.o"

    # Compile user code
    ${avrPkgs.gcc}/bin/avr-g++ -c -g -Os -w -std=gnu++11 -fpermissive -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics -Wno-error=narrowing -mmcu=atmega328p -DF_CPU=16000000L -DARDUINO=10813 -I${arduinoCorePath} -I${arduinoVariantPath} -I${arduinoLibPath} -I${max7219Src}/src -I${max7219Src}/interface "$1" -o "$TMPDIR/sketch.o"

    # Link everything
    ${avrPkgs.gcc}/bin/avr-g++ -w -Os -g -flto -fuse-linker-plugin -Wl,--gc-sections -mmcu=atmega328p -o "$TMPDIR/main.elf" $TMPDIR/*.o -L${arduinoCorePath} -lm

    # Generate hex file
    ${avrPkgs.binutils}/bin/avr-objcopy -O ihex -j .eeprom --set-section-flags=.eeprom=alloc,load --no-change-warnings --change-section-lma .eeprom=0 "$TMPDIR/main.elf" "$TMPDIR/main.eep"
    ${avrPkgs.binutils}/bin/avr-objcopy -O ihex -R .eeprom "$TMPDIR/main.elf" "$TMPDIR/main.hex"

    echo "$TMPDIR/main.hex"
  '';

  upload-avr = pkgs.writeShellScriptBin "upload-avr" ''
    set -e
    if [ ! -f $1 ]; then
      echo "Error: main.hex not found. Compile your code first."
      exit 1
    fi

    ${avrPkgs.avrdude}/bin/avrdude -patmega328p -carduino -P/dev/ttyACM0 -b115200 -D -Uflash:w:$1:i
  '';

in
pkgs.mkShell {
  buildInputs = with avrPkgs; [
    gcc
    binutils
    avrdude
  ] ++ [
    avrPkgs.libcCross
    compile-avr
    upload-avr
  ];

  shellHook = ''
    echo "AVR C++ development environment with Arduino core and MAX7219 library loaded"
    echo "Available commands:"
    echo " - compile-avr <file.cpp>: Compile C++ file for AVR with Arduino core and MAX7219 library"
    echo " - upload-avr: Upload compiled hex file to AVR device"
    echo "Note: These commands use temporary directories and clean up after themselves."

    # Generate a compile_commands.json file
    echo '[
      {
        "directory": "'"$PWD"'",
        "command": "${avrPkgs.gcc}/bin/avr-g++ -c -g -Os -w -std=gnu++11 -fpermissive -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics -Wno-error=narrowing -mmcu=atmega328p -DF_CPU=16000000L -DARDUINO=10813 -I${arduinoCorePath} -I${arduinoVariantPath} -I${arduinoLibPath} -I${max7219Src}/src -I${max7219Src}/interface main.cpp -o main.o",
        "file": "main.cpp"
      }
    ]' > compile_commands.json

    echo "compile_commands.json generated for LSP configuration"
  '';
}

