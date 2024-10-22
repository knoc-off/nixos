{ stdenv,
  lib,
  fetchurl,
  pam,
  gcc,
  libpam-wrapper,
  systemd,
  pkgs,
}:

stdenv.mkDerivation rec {
  pname = "pam-preload";
  version = "1.0.0";

  src = ./.;

  buildInputs = [ gcc pam libpam-wrapper systemd ];

  buildPhase = ''
    gcc -shared -fPIC -o pam_led_hook.so pam_led_hook.c -ldl -lsystemd
  '';

  installPhase = ''
    mkdir -p $out/lib
    cp pam_led_hook.so $out/lib/
  '';

  meta = with lib; {
    description = "PAM LD_PRELOAD library to blink LED on fingerprint request";
    homepage = "https://example.com";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}

