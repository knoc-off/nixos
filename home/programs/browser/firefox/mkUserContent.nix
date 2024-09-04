{ pkgs, theme }:

{ removeFlash ? false
, extraStyles ? ""
}:

let
  removeFlashconfig = import ./userContent/removeFlash.nix { inherit theme; };
in ''
  ${if removeFlash then removeFlashconfig else ""}
  ${extraStyles}
''
