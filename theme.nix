# Theme generator -- research-grounded Base16 palette from bg/fg + accent parameters.
#
# Design principles:
#   1. Okhsl (Björn Ottosson) for perceptual uniformity -- equal lightness values
#      look equally bright across hues.
#   2. Grayscale: linear Okhsl lightness ramp between bg and fg.  Color is
#      smoothly interpolated via mixColors (Oklab) so grays inherit the
#      warm/cool tint of both endpoints.
#   3. Accents: fixed semantic hue targets matching Base16 roles (red = errors,
#      green = strings, blue = functions, ...).  A `hueOffset` rotates the whole
#      palette uniformly for personality.
#   4. Per-hue contrast: each accent starts vivid (high S, moderate L), then
#      ensureTextContrast pushes lightness up/down just enough to meet the
#      target contrast ratio.  This keeps colors as saturated and true-to-hue
#      as possible -- yellow stays punchy, blue gets lifted only as much as
#      needed.
#   5. No "neutral mixing" -- cohesion comes from consistent S across accents
#      and the shared bg/fg tint in the grayscale.
#
# References:
#   - Oklab/Okhsl: https://bottosson.github.io/posts/colorpicker/
#   - WCAG 2.2 contrast: https://www.w3.org/TR/WCAG22/#contrast-minimum
#   - Base16 styling guidelines: https://github.com/tinted-theming/home
{ lib, color-lib, ... }:
let
  inherit (lib) elemAt;
  inherit (lib.lists) genList;
  inherit (color-lib)
    setOkhslLightness
    setOkhslSaturation
    setOkhslHue
    getOkhslLightness
    mixColors
    ensureTextContrast;

  # Hue Offset
  # Rotates all accent + workspace hues uniformly (0.0-1.0, wraps).
  # 0.0 = canonical red/orange/yellow/green/cyan/blue/purple/magenta.
  hueOffset = 0.0;

  # Float modulo 1.0 -- wraps hue values into [0, 1).
  mod1 = x: x - builtins.floor x;

  # Semantic Hue Targets (Okhsl 0.0-1.0)
  # Measured from canonical sRGB primaries via color-lib.getOkhslHue.
  # These map directly to Base16 accent roles.
  hueTargets = {
    red     = 0.08;  # base08 -- errors, deletion, variables
    orange  = 0.13;  # base09 -- numbers, booleans, constants
    yellow  = 0.19;  # base0A -- types, classes, search highlight
    green   = 0.40;  # base0B -- strings, addition, success
    cyan    = 0.55;  # base0C -- escape chars, regex, info
    blue    = 0.72;  # base0D -- functions, methods, links
    purple  = 0.83;  # base0E -- keywords, tags, control flow
    magenta = 0.95;  # base0F -- deprecated, special, embedded
  };

  # mkTheme -- the core generator
  mkTheme = {
    bg,            # background hex (with or without '#')
    fg,            # foreground hex
    accentS,       # Okhsl saturation for accents (0.0-1.0)
    accentStartL,  # starting lightness before contrast adjustment
    minContrast,   # minimum WCAG 2.1 contrast ratio (e.g. 4.5 for AA text)
  }: let

    l_bg = getOkhslLightness bg;
    l_fg = getOkhslLightness fg;

    # Grayscale (base00-base07)
    # Linear lightness ramp in Okhsl between bg and fg.
    # mixColors interpolates hue/chroma in Oklab so the tint transitions
    # smoothly; setOkhslLightness then pins each step to the exact target.
    numGrays = 8;

    baseColors = genList (n: let
      t = n * 1.0 / (numGrays - 1);
      targetL = l_bg + t * (l_fg - l_bg);
      mixed = mixColors bg fg t;
    in
      setOkhslLightness targetL mixed
    ) numGrays;

    # Accents (base08-base0F)
    # Build each accent at the target hue, high saturation, and a moderate
    # starting lightness.  Then ensureTextContrast adjusts lightness per-hue
    # to meet the minimum contrast ratio.  This keeps each color as vivid
    # and true-to-hue as possible -- the binary search in ensureTextContrast
    # only changes Okhsl lightness, preserving hue and saturation.
    mkAccent = hue: let
      raw = setOkhslLightness accentStartL
        (setOkhslHue (mod1 (hue + hueOffset))
          (setOkhslSaturation accentS "FF0000"));
    in
      ensureTextContrast raw bg minContrast;

    # Workspace background colors (12 evenly-spaced hues)
    # Subtle, muted colors near bg lightness -- distinguishable but not
    # distracting.  On dark themes, slightly brighter than bg; on light
    # themes, slightly darker.
    isDark = l_bg < l_fg;
    numWS = 12;
    wsL = if isDark then l_bg + 0.04 else l_bg - 0.10;
    wsS = if isDark then 0.35 else 0.45;

    workspaceColors = genList (n: let
      hue = mod1 (n * 1.0 / numWS + hueOffset);
    in
      setOkhslLightness wsL
        (setOkhslHue hue
          (setOkhslSaturation wsS "FF0000"))
    ) numWS;

  in {
    # Grayscale -- Base16 convention: base00 = bg, base07 = fg
    base00 = elemAt baseColors 0; # Default Background
    base01 = elemAt baseColors 1; # Lighter Background (UI panels)
    base02 = elemAt baseColors 2; # Selection Background
    base03 = elemAt baseColors 3; # Comments, Line Highlighting
    base04 = elemAt baseColors 4; # Dark Foreground (status bars)
    base05 = elemAt baseColors 5; # Default Foreground (body text)
    base06 = elemAt baseColors 6; # Light Foreground
    base07 = elemAt baseColors 7; # Lightest (inverse bg)

    # Accents -- semantic color roles
    base08 = mkAccent hueTargets.red;     # Red
    base09 = mkAccent hueTargets.orange;  # Orange
    base0A = mkAccent hueTargets.yellow;  # Yellow
    base0B = mkAccent hueTargets.green;   # Green
    base0C = mkAccent hueTargets.cyan;    # Cyan
    base0D = mkAccent hueTargets.blue;    # Blue
    base0E = mkAccent hueTargets.purple;  # Purple
    base0F = mkAccent hueTargets.magenta; # Magenta

    inherit workspaceColors;
  };

in {
  # Dark theme -- vivid accents, per-hue lightness for WCAG AA (4.5:1)
  dark = mkTheme {
    bg = "1b2429";
    fg = "ECEFF1";
    accentS = 0.95;       # Near-maximum saturation for vivid, true hues
    accentStartL = 0.55;  # Moderate starting lightness (in-gamut for all hues)
    minContrast = 4.5;    # WCAG AA normal text
  };

  # Light theme -- darker accents for contrast on light bg
  light = mkTheme {
    bg = "ECEFF1";
    fg = "1b2429";
    accentS = 0.90;
    accentStartL = 0.55;  # Start moderate, ensureTextContrast pushes down
    minContrast = 4.5;
  };
}
