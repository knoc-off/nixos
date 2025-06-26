{ pkgs, ... }:

let
  spotify-adblock = pkgs.rustPackages.rustPlatform.buildRustPackage {
    pname = "spotify-adblock";
    version = "0.0.1";

    cargoHash = "sha256-oGpe+kBf6kBboyx/YfbQBt1vvjtXd1n2pOH6FNcbF8M=";

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
      rev = "8e0312d6085a6e4f9afeb7c2457517a75e8b8f9d";
      hash = "sha256-nwiX2wCZBKRTNPhmrurWQWISQdxgomdNwcIKG2kSQsE=";
    };
  };

  spotifyWrapper = pkgs.writeShellScriptBin "spotify" ''
    LD_PRELOAD="${spotify-adblock}/lib/libspotifyadblock.so" ${pkgs.spotify}/bin/spotify "$@"
  '';

in
pkgs.spotify.overrideAttrs (_old: {
  postInstall = ''
    ${_old.postInstall or ""}
    rm $out/bin/spotify
    ln -sf ${spotifyWrapper}/bin/spotify $out/bin/spotify
  '';
})
