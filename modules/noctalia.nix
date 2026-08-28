# Noctalia v5. This is a deliberately minimal integration -- a fresh start
# rather than a port of the v4 config.
#
# v5 is a native rewrite (meson/C++, OpenGL ES); the quickshell/QML era is
# over. Nothing from the v4 setup survives contact with it:
#
#   - the package no longer takes `calendarSupport` (or any of the old
#     feature flags); optional deps are resolved by the upstream package
#   - plugins are Luau with a versioned API, not QML, so the three local
#     QML plugins could only be rewritten, not ported. Dropped.
#   - settings are TOML with snake_case keys, not camelCase JSON, and the
#     module now takes an attrset it converts via tomlFormat
#   - `colors` and `pluginSettings` are gone; theming is `customPalettes`
#   - the binary and the HM option are `noctalia`, not `noctalia-shell`
#
# Settings are kept to the few things that are genuinely ours (theme colors,
# bar position). Everything else is left at upstream defaults and tuned at
# runtime through the settings UI, which v5 persists itself -- re-encoding the
# whole schema in Nix is what made the v4 module 700 lines and what made every
# upstream bump a breaking change.
{ inputs, self }:
let
  inherit (self.lib) theme;

  # v5's custom-palette loader (src/theme/cli.cpp: parseFixedPaletteJson)
  # only recognises this exact camelCase, "m"-prefixed key set nested under
  # `dark`/`light` -- verified by reading the parser directly, since it isn't
  # documented anywhere the schema is spelled out completely. Getting a key
  # wrong doesn't error, it just falls back to magenta for that role.
  mkPaletteMode =
    t: {
      mPrimary = "#${t.base0C}";
      mOnPrimary = "#${t.base00}";
      mSecondary = "#${t.base0D}";
      mOnSecondary = "#${t.base00}";
      mTertiary = "#${t.base0E}";
      mOnTertiary = "#${t.base00}";
      mError = "#${t.base08}";
      mOnError = "#${t.base00}";
      mSurface = "#${t.base00}";
      mOnSurface = "#${t.base05}";
      mSurfaceVariant = "#${t.base01}";
      mOnSurfaceVariant = "#${t.base04}";
      mOutline = "#${t.base03}";
      mShadow = "#000000";
    };

  base16Palette = {
    dark = mkPaletteMode theme.dark;
    light = mkPaletteMode theme.light;
  };
in
{
  nixos =
    { lib, ... }:
    {
      # No imports of inputs.noctalia.nixosModules here: v5 ships both an
      # upstream module and one in nixpkgs, and enabling both collides. The
      # home-manager module below is the one that owns the config.
      services.gnome.evolution-data-server.enable = lib.mkDefault true;
    };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.noctalia.homeModules.default ];

      # Double-tap caps -> toggle the launcher. The `dbl` alias is consumed by
      # the keyLayers-generated kanata config (cap-<layer>), so this is the
      # canonical home for the noctalia caps keybind. v5's CLI is `msg
      # panel-toggle <id>`, replacing v4's `ipc call launcher toggle`.
      keyLayers.extraAliases = lib.mkIf config.keyLayers.enable ''
        launcher (cmd noctalia msg panel-toggle launcher)
        dbl (tap-dance-eager 250 (XX @launcher))
      '';


      home.packages = with pkgs; [
        hicolor-icon-theme
        papirus-icon-theme
        wl-clipboard
        grim
        slurp
      ];

      services.cliphist.enable = true;

      # Fallback icon for the window widget when nothing is focused.
      xdg.dataFile."icons/hicolor/scalable/apps/user-desktop.svg".text = ''
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <rect x="3" y="4" width="18" height="16" rx="2" ry="2" />
          <line x1="3" y1="8" x2="21" y2="8" />
          <line x1="7" y1="6" x2="7.01" y2="6" />
          <line x1="11" y1="6" x2="11.01" y2="6" />
        </svg>
      '';

      programs.noctalia = {
        enable = lib.mkDefault true;

        customPalettes.base16 = base16Palette;

        # v5 manages its own user service. The v4 module hand-rolled one
        # because upstream's was unreliable; that is no longer true, and a
        # second unit would just fight it.
        systemd.enable = lib.mkDefault true;

        # Deliberately small. Anything not here is an upstream default, which
        # is the point of the rewrite. config.toml only seeds initial state --
        # settings.toml (unmanaged, in $XDG_STATE_HOME) layers on top and is
        # where the settings UI actually persists runtime changes, so this
        # isn't clobbered by using the in-app theme picker afterward.
        #
        # `bar.default` rather than `bars = [...]`: v5 keys bars by name in a
        # `[bar.<name>]` table (config_service.cpp reads `merged["bar"]` as a
        # table-of-tables), not an array -- verified by reading the TOML
        # loader directly, since v5's own schema validator treats `position`
        # as a special case emitted outside the normal field list.
        settings = {
          bar.default.position = "left";
          theme = {
            source = "custom";
            custom_palette = "base16";
          };
        };
      };
    };
}
