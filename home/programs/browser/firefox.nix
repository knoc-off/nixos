# NixOS, Firefox, web browser configuration, extensions, custom configuration options, CSS styles
{ nix-colors, config, pkgs, inputs, ... }:
let

  firefoxPath = ".mozilla/firefox";

  # Edge modifications, drawer, style, etc.
  #  Edge-Mimicry = pkgs.fetchFromGitHub {
  #    owner = "UnlimitedAvailableUsername";
  #    repo = "Edge-Mimicry-Tree-Style-Tab-For-Firefox";
  #    rev = "f9c59082c4803aace8c07fe9888b0216e9e680a7";
  #    sha256 = "sha256-dEaWqwbui70kCzBeNjJIttKSSgi4rAncc8tGcpGvpl4=";
  #  };
in
{

  #  home.file = {
  #    "themes" = {
  #      source = "${Edge-Mimicry}";
  #      target = "${firefoxPath}/themes";
  #    };
  #  };

  imports = [
    ./profiles/main
    ./profiles/minimal
  ];

  programs.firefox = {
    enable = true;
  };
}
