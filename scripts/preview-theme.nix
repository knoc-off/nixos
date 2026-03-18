# Called by preview-theme.fish — takes { variant } as argument.
# variant: "dark", "light", or "both"
{ variant ? "both" }:
let
  lib = import <nixpkgs/lib>;
  color-lib = import ../lib/color-lib.nix { inherit lib; };
  theme = import ../theme.nix { inherit lib color-lib; };
  c = color-lib;

  # Real ESC byte (0x1B) — terminal interprets these directly.
  esc = builtins.fromJSON ''"\u001b"'';

  hexToRgb = hex: {
    r = lib.fromHexString (builtins.substring 0 2 hex);
    g = lib.fromHexString (builtins.substring 2 2 hex);
    b = lib.fromHexString (builtins.substring 4 2 hex);
  };
  bg = h: let rgb = hexToRgb h; in "${esc}[48;2;${toString rgb.r};${toString rgb.g};${toString rgb.b}m";
  fg = h: let rgb = hexToRgb h; in "${esc}[38;2;${toString rgb.r};${toString rgb.g};${toString rgb.b}m";
  rst = "${esc}[0m";
  bold = "${esc}[1m";
  txtFor = hex: if (c.getOkhslLightness hex) > 0.65 then fg "000000" else fg "FFFFFF";
  swatch = label: hex: "${bg hex}${txtFor hex}  #${hex} ${label}  ${rst}";
  cr = bgHex: hex:
    let v = toString (c.contrastRatio hex bgHex);
    in builtins.substring 0 4 v;
  accent = bgHex: label: hex: "${swatch label hex}  cr=${cr bgHex hex}";

  renderTheme = name: t: builtins.concatStringsSep "\n" [
    ""
    "  ${bold}${name}${rst}  bg=#${t.base00}  fg=#${t.base07}"
    "  ─────────────────────────────────────────────"
    (swatch "base00 bg      " t.base00)
    (swatch "base01 panel   " t.base01)
    (swatch "base02 select  " t.base02)
    (swatch "base03 comment " t.base03)
    (swatch "base04 dim-txt " t.base04)
    (swatch "base05 text    " t.base05)
    (swatch "base06 bright  " t.base06)
    (swatch "base07 fg      " t.base07)
    ""
    (accent t.base00 "base08 red     " t.base08)
    (accent t.base00 "base09 orange  " t.base09)
    (accent t.base00 "base0A yellow  " t.base0A)
    (accent t.base00 "base0B green   " t.base0B)
    (accent t.base00 "base0C cyan    " t.base0C)
    (accent t.base00 "base0D blue    " t.base0D)
    (accent t.base00 "base0E purple  " t.base0E)
    (accent t.base00 "base0F magenta " t.base0F)
    ""
    "  Workspace backgrounds:"
    (builtins.concatStringsSep "" (lib.imap0 (i: hex:
      "${bg hex}  ${toString i} ${rst}"
    ) t.workspaceColors))
    ""
  ];

  sections = {
    dark  = renderTheme "Dark Theme"  theme.dark;
    light = renderTheme "Light Theme" theme.light;
    both  = sections.dark + "\n" + sections.light;
  };
in
  sections.${variant}
