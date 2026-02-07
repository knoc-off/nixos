{
  inputs,
  lib,
  ...
}: {
  imports = [inputs.noctalia.homeModules.default];

  programs.noctalia-shell = {
    enable = lib.mkDefault true;
    package = lib.mkDefault null;
    settings = lib.mkDefault {
      bar.position = "left";
    };
  };
}
