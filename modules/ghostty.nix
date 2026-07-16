{self, ...}: {
  home = {
    lib,
    pkgs,
    config,
    ...
  }: let
    inherit (self.lib) color-lib theme;
    inherit (self.lib.keyLayers) presets;
    inherit (color-lib) setOkhslLightness setOkhslSaturation adjustOkhslHue;
    inherit (theme) mkTheme;
    inherit (lib.lists) genList;
    inherit (lib) elemAt concatStringsSep;
    lighten = setOkhslLightness 0.7;
    saturate = setOkhslSaturation 0.9;

    sa = hex: lighten (saturate hex);

    # --- Rotating color scheme generation ---
    numSchemes = 16;

    variants =
      genList (
        i: let
          offset = i * 1.0 / numSchemes;
          # Intense bg: boost saturation so hue rotation produces visibly tinted backgrounds
          bgTinted = adjustOkhslHue offset (setOkhslSaturation 0.25 "1b2429");
          # Subtler fg: near-white gets a gentle tint to complement bg
          fgTinted = adjustOkhslHue (offset * 0.3) "ECEFF1";
        in
          mkTheme {
            bg = bgTinted;
            fg = fgTinted;
            hueOffset = offset;
            accentS = 0.95;
            accentStartL = 0.55;
            minContrast = 4.5;
          }
      )
      numSchemes;

    # "AABBCC" → "AA/BB/CC" for OSC rgb: color format
    hexRgb = hex: let
      h = lib.removePrefix "#" hex;
    in "${builtins.substring 0 2 h}/${builtins.substring 2 2 h}/${builtins.substring 4 2 h}";

    # Build the OSC escape sequence block for one theme variant.
    # Sets: fg, bg, cursor, selection bg/fg, and all 16 palette entries.
    mkOscSnippet = v: let
      osc = code: color: "printf '\\e]${code};rgb:${hexRgb color}\\e\\\\'";
    in
      concatStringsSep "\n      " [
        (osc "10" v.base05) # foreground
        (osc "11" v.base00) # background
        (osc "12" v.base09) # cursor
        (osc "17" v.base02) # selection background
        (osc "19" v.base06) # selection foreground
        (osc "4;0" v.base00) # palette 0:  black
        (osc "4;1" (sa v.base08)) # palette 1:  red (saturated/lightened)
        (osc "4;2" (sa v.base0B)) # palette 2:  green
        (osc "4;3" (sa v.base0A)) # palette 3:  yellow
        (osc "4;4" (sa v.base0D)) # palette 4:  blue
        (osc "4;5" (sa v.base0E)) # palette 5:  magenta
        (osc "4;6" (sa v.base0C)) # palette 6:  cyan
        (osc "4;7" v.base06) # palette 7:  white
        (osc "4;8" v.base03) # palette 8:  bright black (gray)
        (osc "4;9" v.base08) # palette 9:  bright red
        (osc "4;10" v.base0B) # palette 10: bright green
        (osc "4;11" v.base0A) # palette 11: bright yellow
        (osc "4;12" v.base0D) # palette 12: bright blue
        (osc "4;13" v.base0E) # palette 13: bright magenta
        (osc "4;14" v.base0C) # palette 14: bright cyan
        (osc "4;15" v.base07) # palette 15: bright white
      ];

    # Case branch for each variant index
    caseBranches = concatStringsSep "\n    " (genList (
        i: "${toString i})\n      ${mkOscSnippet (elemAt variants i)}\n      ;;"
      )
      numSchemes);

    ghostty-theme-rotate = pkgs.writeShellScript "ghostty-theme-rotate" ''
      STATE_FILE="''${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-theme-index"
      mkdir -p "$(dirname "$STATE_FILE")"

      # Atomic read-increment with flock for global cross-process rotation
      exec 9>"$STATE_FILE.lock"
      flock 9
      INDEX=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
      NEXT=$(( (INDEX + 1) % ${toString numSchemes} ))
      echo "$NEXT" > "$STATE_FILE"
      exec 9>&-

      case "$INDEX" in
        ${caseBranches}
      esac
    '';

    # Variant 0 for the base Ghostty config (chrome defaults, initial render)
    base = elemAt variants 0;
  in {
    home.sessionVariables = {
      TERMINAL = "ghostty";
    };

    # caps-held shortcuts when a terminal window is focused. d/u scroll the
    # terminal buffer instead of the accelerated mouse wheel used elsewhere.
    keyLayers.layers.terminal = lib.mkIf config.keyLayers.enable {
      classes = ["com.mitchellh.ghostty" "foot"];
      capsbinds = {
        alt = ["e"];
        shift = [";"];
        keys =
          presets.navKeys
          // {
            d = {raw = "(multi (release-key rmet) (mwheel-down 50 1 ))";};
            u = {raw = "(multi (release-key rmet) (mwheel-up 50 1 ))";};
          };
      };
    };

    home.packages = [
      # ghostty-theme-rotate
    ];

    # Ghostty's progress bar (OSC 9;4) is a GTK widget on Linux/GTK; its default
    # trough/progress is only ~2px tall. Thicken it via GTK4 CSS by bumping the
    # min-height on the progressbar trough/progress nodes.
    gtk.gtk4.extraCss = lib.mkIf pkgs.stdenv.isLinux ''
      progressbar > trough,
      progressbar > trough > progress {
        min-height: 8px;
      }
    '';

    programs.ghostty = {
      enable = true;

      enableZshIntegration = true;

      settings = {
        font-family = "FiraCode Nerd Font Mono";
        font-size = 15;

        window-padding-x = 2;
        window-padding-y = 2;

        # command = "${ghostty-theme-rotate}";

        focus-follows-mouse = true;

        palette = [
          "0=#${base.base00}" # black
          "1=#${sa base.base08}" # red (saturated/lightened)
          "2=#${sa base.base0B}" # green (saturated/lightened)
          "3=#${sa base.base0A}" # yellow (saturated/lightened)
          "4=#${sa base.base0D}" # blue (saturated/lightened)
          "5=#${sa base.base0E}" # magenta (saturated/lightened)
          "6=#${sa base.base0C}" # cyan (saturated/lightened)
          "7=#${base.base06}" # white
          "8=#${base.base03}" # bright black (gray)
          "9=#${base.base08}" # bright red
          "10=#${base.base0B}" # bright green
          "11=#${base.base0A}" # bright yellow
          "12=#${base.base0D}" # bright blue
          "13=#${base.base0E}" # bright magenta
          "14=#${base.base0C}" # bright cyan
          "15=#${base.base07}" # bright white
        ];

        background = "${base.base00}";
        foreground = "${base.base06}";

        cursor-color = "${base.base09}";
        cursor-style = "bar";
        cursor-style-blink = false;
        adjust-cursor-thickness = "200%";

        selection-background = "${base.base02}";
        selection-foreground = "${base.base06}";

        background-opacity = 0.9;
        background-blur = 20;
        background-opacity-cells = true;

        keybind = let
          isLinux = pkgs.stdenv.isLinux;
          isDarwin = pkgs.stdenv.isDarwin;
        in
          [
            "clear"
            "super+c=copy_to_clipboard"
            "super+v=paste_from_clipboard"
            "super+a=select_all" # change: end-of-line or select last cmd output?
            "super+q=quit"
          ]
          ++ lib.optionals isLinux [
            "super+t=new_window"
            "super+shift+t=new_tab"
          ]
          ++ lib.optionals isDarwin [
            "super+t=new_tab"
            "super+shift+t=new_window"
          ]
          ++ [
            "super+w=close_surface"

            "super+one=goto_tab:1"
            "super+two=goto_tab:2"
            "super+three=goto_tab:3"
            "super+four=goto_tab:4"
            "super+five=goto_tab:5"
            "super+six=goto_tab:6"
            "super+seven=goto_tab:7"
            "super+eight=goto_tab:8"
            "super+nine=goto_tab:9"

            "super+equal=increase_font_size:1"
            "super+minus=decrease_font_size:1"
            "super+zero=reset_font_size"

            "super+shift+enter=new_split:right"
            "super+shift+w=close_surface"

            "super+h=goto_split:left"
            "super+j=goto_split:bottom"
            "super+k=goto_split:top"
            "super+l=goto_split:right"

            "super+ctrl+h=resize_split:left,10"
            "super+ctrl+j=resize_split:down,10"
            "super+ctrl+k=resize_split:up,10"
            "super+ctrl+l=resize_split:right,10"
          ];
      };
    };
  };
}
