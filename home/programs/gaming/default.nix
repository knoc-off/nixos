{ inputs, pkgs, libs, config, ... }:
{
  imports = [
    #./steam.nix
    ./lutris.nix

  ];
  home.packages = with pkgs; [
    # Minecraft Launcher
    prismlauncher
  ];

}
