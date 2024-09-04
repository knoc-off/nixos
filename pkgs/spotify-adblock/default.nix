{ pkgs, ... }:

let
  spotify-adblock = pkgs.rustPackages.rustPlatform.buildRustPackage {
    pname = "spotify-adblock";
    version = "0.0.1";

    cargoHash = "sha256-HpOxoHe7jbmgU2Im0JKSGISmj4im6fwFIuyJTueLmM0=";

    postPatch = ''
      substituteInPlace src/lib.rs \
        --replace 'PathBuf::from("config.toml"),' 'PathBuf::from("'"$out"'/etc/spotify-adblock/config.toml"),'
    '';

    postInstall = ''
      mkdir -p $out/etc/spotify-adblock
      cp ./config.toml $out/etc/spotify-adblock/
    '';

    src = pkgs.fetchFromGitHub {
      owner = "abba23";
      repo = "spotify-adblock";
      rev = "5a3281dee9f889afdeea7263558e7a715dcf5aab";
      hash = "sha256-UzpHAHpQx2MlmBNKm2turjeVmgp5zXKWm3nZbEo0mYE=";
    };
  };

  spotifyWrapper = pkgs.writeShellScriptBin "spotify" ''
    LD_PRELOAD="${spotify-adblock}/lib/libspotifyadblock.so" ${pkgs.spotify}/bin/spotify "$@"
  '';

in
pkgs.spotify.overrideAttrs (_old: {

  postInstall = ''
    # Update .desktop files
    for f in $out/share/applications/spotify.desktop $out/share/spotify/spotify.desktop; do
      if [ -f "$f" ]; then
        substituteInPlace "$f" \
          --replace "Exec=spotify" "Exec=${spotifyWrapper}/bin/spotify" \
          --replace "TryExec=spotify" "TryExec=${spotifyWrapper}/bin/spotify"
      fi
    done
  '';

    #postInstall = ''
    #  ExecMe="env LD_PRELOAD=${spotify-adblock}/lib/libspotifyadblock.so spotify"
    #  sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/applications/spotify.desktop
    #  sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/applications/spotify.desktop

    #  sed -i "s|^TryExec=.*|TryExec=$ExecMe %U|" $out/share/spotify/spotify.desktop
    #  sed -i "s|^Exec=.*|Exec=$ExecMe %U|" $out/share/spotify/spotify.desktop
    #'';
})
