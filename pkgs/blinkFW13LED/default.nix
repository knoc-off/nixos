{ stdenv,
  lib,
  fetchurl,
  pam,
  gcc,
  libpam-wrapper,
  pkgs,
  BLINK_SCRIPT ? "${pkgs.writeScriptBin "blink" ''
    echo 0 > /sys/class/leds/chromeos\:white\:power/brightness
    sleep 0.5
    echo 1 > /sys/class/leds/chromeos\:white\:power/brightness
  ''}/bin/blink",
}:

stdenv.mkDerivation rec {
  pname = "pam-preload";
  version = "1.0.0";

  src = ./.;

  buildInputs = [ gcc pam libpam-wrapper ];

  buildPhase = ''
    gcc -fPIC -shared -o pam_blink.so pam_blink.c -ldl -DBLINK_SCRIPT=\"${BLINK_SCRIPT}\"
    gcc -o test_pam_blink test_pam_blink.c -lpam -lpam_misc
  '';

  installPhase = ''
    mkdir -p $out/lib
    mkdir -p $out/bin
    cp pam_blink.so $out/lib/
    cp test_pam_blink $out/bin/
  '';

  meta = with lib; {
    description = "PAM LD_PRELOAD library to blink LED on fingerprint request";
    homepage = "https://example.com";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

