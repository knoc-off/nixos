{ pkgs
, config
, theme
, lib
, ...
}:
let
  isValidColor = thing:
    if builtins.isString thing
    then (builtins.match "^[0-9a-fA-F]{6}" thing) != null
    else false;
  withHashtag =
    theme
    // (builtins.mapAttrs
      (_: value:
        if isValidColor value
        then "#" + value
        else value)
      theme);
in
{

  programs.foot = {
    enable = true;
    settings = {
      main = {
        term = "xterm-256color";
        font = "Fira Code:size=11";
        dpi-aware = "yes";
      };
      mouse = {
        hide-when-typing = "yes";
      };
    };
  };
}
