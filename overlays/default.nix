{ inputs, pkgs, ... }:
{
  modifications = final: prev: {
    steam-scaling = prev.steam.overrideAttrs (old: rec {
      pname = old.pname + "-scaling";
      postInstall = old.postInstall;
      #+ ''sed -i 's/Exec=steam/Exec=steam -forcedesktopscaling 1.0%U/g' $out/share/applications/steam.desktop'';
    });

  };

  #helloBar = pkgs.hello.overrideAttrs (finalAttrs: previousAttrs: {
  #  pname = previousAttrs.pname + "-bar";
  #});
}
