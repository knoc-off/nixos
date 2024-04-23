{
  config,
  ...
}: {
  programs.eww = {
    enable = true;
    config = {
      bar.enable = true;
      side = "top";
    };

    #package = pkgs.eww-wayland;

    #  configDir = ./eww;
  };

  #  home.file =
  #    let
  #      dir = "eww";
  #    in
  #    {
  #      "${dir}/eww.yuck" = {
  #        text = ''
  #
  #      '';
  #      };
  #      "${dir}/eww.scss" = {
  #        text = ''
  #          @import "eww";
  #
  #          @include eww;
  #        '';
  #      };
  #
  #    };
}
