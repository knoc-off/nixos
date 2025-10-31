# TODO: make all of the special arguments default? its better if it hard fails
{
  config,
  lib,
  theme,
  color-lib,
  pkgs,
  user,
  ...
}: let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.8;
  saturate = setOkhslSaturation 0.9;

  sa = hex: lighten (saturate hex);
in {
  environment.variables = {
    EDITOR = "vi";
    VISUAL = "vi";
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      # printf %b '\e]11;#${theme.dark.base00}\e\\'
      # printf %b '\e]10;#${theme.dark.base06}\e\\'
      # printf %b '\e]12;#${theme.dark.base0D}\e\\'
      # printf %b '\e]P0${theme.dark.base00}'
      # printf %b '\e]P1${theme.dark.base08}'
      # printf %b '\e]P2${theme.dark.base0B}'
      # printf %b '\e]P3${theme.dark.base0A}'
      # printf %b '\e]P4${theme.dark.base0D}'
      # printf %b '\e]P5${theme.dark.base0E}'
      # printf %b '\e]P6${theme.dark.base0C}'
      # printf %b '\e]P7${theme.dark.base06}'
      # printf %b '\e]P8${theme.dark.base03}'
      # printf %b '\e]P9${theme.dark.base09}'
      # printf %b '\e]Pa${sa theme.dark.base0B}'
      # printf %b '\e]Pb${sa theme.dark.base0A}'
      # printf %b '\e]Pc${sa theme.dark.base0D}'
      # printf %b '\e]Pd${sa theme.dark.base0E}'
      # printf %b '\e]Pe${sa theme.dark.base0C}'
      # printf %b '\e]Pf${theme.dark.base07}'

    '';
  };
}
