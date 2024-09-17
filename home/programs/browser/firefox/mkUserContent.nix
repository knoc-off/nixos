{ pkgs, theme, firefox-csshacks }:

{ removeFlash ? false
, extraStyles ? ""
}:

let
  #removeFlashconfig = import ./userContent/removeFlash.nix { inherit theme; };
  #${if removeFlash then removeFlashconfig else ""}
in ''
  ${extraStyles}
''
