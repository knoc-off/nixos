{ pkgs ? import <nixpkgs> {} }:

let
  avrPkgs = pkgs.pkgsCross.avr.buildPackages;

  micronucleus = pkgs.micronucleus;

    compile-attiny85 = pkgs.writeShellScriptBin "compile-attiny85" ''
    set -e
    TMPDIR=$(mktemp -d)

    # Compile user code
    ${avrPkgs.gcc}/bin/avr-g++ -c -g -Os -w -std=gnu++11 -fpermissive -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics -Wno-error=narrowing -mmcu=attiny85 -DF_CPU=16500000L "$1" -o "$TMPDIR/sketch.o"

    # Link everything
    ${avrPkgs.gcc}/bin/avr-g++ -w -Os -g -flto -fuse-linker-plugin -Wl,--gc-sections -mmcu=attiny85 -o "$TMPDIR/main.elf" $TMPDIR/*.o

    # Generate hex file
    ${avrPkgs.binutils}/bin/avr-objcopy -O ihex -j .eeprom --set-section-flags=.eeprom=alloc,load --no-change-warnings --change-section-lma .eeprom=0 "$TMPDIR/main.elf" "$TMPDIR/main.eep"
    ${avrPkgs.binutils}/bin/avr-objcopy -O ihex -R .eeprom "$TMPDIR/main.elf" "$TMPDIR/main.hex"

    echo "$TMPDIR/main.hex"
  '';


  upload-attiny85 = pkgs.writeShellScriptBin "upload-attiny85" ''
    set -e
    if [ ! -f $1 ]; then
      echo "Error: main.hex not found. Compile your code first."
      exit 1
    fi

    echo "Please plug in your Digispark board now..."
    ${micronucleus}/bin/micronucleus --run $1
  '';

in
pkgs.mkShell {
  buildInputs = with avrPkgs; [
    gcc
    binutils
  ] ++ [
    compile-attiny85
    upload-attiny85
    micronucleus
  ];

  shellHook = ''
    echo "ATtiny85 development environment loaded for Digispark"
    echo "Available commands:"
    echo " - compile-attiny85 <file.cpp>: Compile C++ file for ATtiny85"
    echo " - upload-attiny85 <hex_file>: Upload compiled hex file to Digispark"
    echo "Note: These commands use temporary directories and clean up after themselves."

    # Generate a compile_commands.json file
    echo '[
      {
        "directory": "'"$PWD"'",
        "command": "${avrPkgs.gcc}/bin/avr-g++ -c -g -Os -w -std=gnu++11 -fpermissive -fno-exceptions -ffunction-sections -fdata-sections -fno-threadsafe-statics -Wno-error=narrowing -mmcu=attiny85 -DF_CPU=16500000L main.cpp -o main.o",
        "file": "main.cpp"
      }
    ]' > compile_commands.json

    echo "compile_commands.json generated for LSP configuration"
  '';
}
