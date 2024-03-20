{
  inputs,
  ...
}: {
  # Prism launcher is better
  #poly = inputs.polymc.overlay;
  #nuenv = inputs.nuenv.overlays.default;

  # Backlink
  additions = final: _prev: import ../pkgs {pkgs = final;};

  modifications = final: prev: {
    #steam-scaling = prev.steamPackages.steam-fhsenv.overrideAttrs (old: rec {
    #pname = old.pname + "-scaling";
    #  extraArgs = old.extraArgs ++ [ "-forcedesktopscaling 1.0" ];
    #postInstall =  ''
    #sed -i 's/Exec=steam/Exec=steam -forcedesktopscaling 1.0/g' $out/share/applications/steam.desktop
    #'';
    #old.postInstall;
    #+ ''sed -i 's/Exec=steam/Exec=steam -forcedesktopscaling 1.0%U/g' $out/share/applications/steam.desktop'';
    #});

    steam-scaling = prev.steamPackages.steam-fhsenv.override (old: rec {
      #pname = prev.steamPackages.steam-fhsenv.pname + "-scaling";
      extraArgs = (old.extraArgs or "") + " -forcedesktopscaling 1.0 ";
      #postInstall = ''
      #  sed -i 's/Exec=steam/Exec=steam -forcedesktopscaling 1.0/g' $out/share/applications/steam.desktop
      #'';
    });


    #spotify-adblock = pkgs.callPackage ./spotify-adblock.nix;

    #pname = old.pname + "-scaling";
    #extraArgs = old.extraArgs ++ [ "-forcedesktopscaling 1.0" ];
  };

  #helloBar = pkgs.hello.overrideAttrs (finalAttrs: previousAttrs: {
  #  pname = previousAttrs.pname + "-bar";
  #});
}
