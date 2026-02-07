{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.noctalia.homeModules.default];

  programs.noctalia-shell = {
    enable = lib.mkDefault true;
    settings = lib.mkDefault {
      bar.position = "left";
    };
  };
}
