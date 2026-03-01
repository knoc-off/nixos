{ inputs, pkgs, lib, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  hyprlandPlugins = pkgs.hyprlandPlugins.override {
    hyprland = inputs.hyprnix.packages.${system}.hyprland;
  };

  hyprglass = hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "hyprglass";
    version = "0.2.1-unstable";

    src = pkgs.fetchFromGitHub {
      owner = "hyprnux";
      repo = "hyprglass";
      rev = "fc65c63f04f96f7ec2c1e54acee50f460d543cd1";
      hash = "sha256-cO7p7jJpHRMaWs2XCLkvU3kPhEaM2N+bs6APvwiWamA=";
    };

    dontUseCmakeConfigure = true;

    buildPhase = "make all";

    installPhase = ''
      mkdir -p $out/lib
      cp hyprglass.so $out/lib/
    '';

    meta = {
      homepage = "https://github.com/hyprnux/hyprglass";
      description = "Liquid Glass inspired blur/refraction effects for Hyprland";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  });
in {
  wayland.windowManager.hyprland.plugins = [ hyprglass ];
}
