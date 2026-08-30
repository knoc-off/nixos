{ self, ... }:
{
  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.tv-files;
      system = pkgs.stdenv.hostPlatform.system;
      qs = lib.getExe cfg.quickshellPackage;
      inherit (self.lib) theme;

      hex = c: "#${c}";

      placesQml = lib.concatMapStringsSep ",\n      " (
        p: ''{ name: "${p.name}", path: "file://${p.path}", icon: "${p.icon}" }''
      ) cfg.places;

      # Deployed as a sibling of the package's static services/State.qml (see
      # xdg.configFile below) -- home-manager's recursive directory copy is
      # per-file, so this coexists in the same directory rather than
      # conflicting with it. Generated rather than shipped in the package
      # because it needs self.lib.theme, which is only available here.
      # QtQuick is imported for the `color` value type: it is not a builtin,
      # so with only Quickshell in scope every `property color` fails to
      # resolve ("color is not a type") and the whole config tree -- Theme,
      # State, Sidebar, Browser, shell -- refuses to load.
      themeQml = pkgs.writeText "tv-files-theme.qml" ''
        pragma Singleton
        import QtQuick
        import Quickshell

        Singleton {
          readonly property color bg: "${hex theme.dark.base00}"
          readonly property color bgAlt: "${hex theme.dark.base01}"
          readonly property color surface: "${hex theme.dark.base02}"
          readonly property color fg: "${hex theme.dark.base05}"
          readonly property color fgMuted: "${hex theme.dark.base04}"
          readonly property color accent: "${hex theme.dark.base0D}"
          readonly property color border: "${hex theme.dark.base03}"

          readonly property var places: [
            ${placesQml}
          ]
        }
      '';
    in
    {
      options.programs.tv-files = {
        enable = lib.mkEnableOption "tv-files, a couch-navigable Quickshell file browser";

        package = lib.mkOption {
          type = lib.types.package;
          default = self.packages.${system}.tv-files;
          description = "The tv-files QML files package.";
        };

        quickshellPackage = lib.mkOption {
          type = lib.types.package;
          default = pkgs.quickshell;
          description = "The Quickshell package providing the qs binary.";
        };

        places = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption {
                  type = lib.types.str;
                  description = "Label shown in the sidebar.";
                };
                path = lib.mkOption {
                  type = lib.types.str;
                  description = "Absolute filesystem path.";
                };
                icon = lib.mkOption {
                  type = lib.types.str;
                  default = "folder";
                  description = "Freedesktop icon name, looked up in the active icon theme.";
                };
              };
            }
          );
          default = [
            {
              name = "Home";
              path = config.home.homeDirectory;
              icon = "user-home";
            }
          ];
          description = "Sidebar shortcuts, in display order.";
        };

        keybind = lib.mkOption {
          type = lib.types.str;
          default = "SUPER, F5";
          description = "Hyprland bind prefix used to toggle the browser.";
        };
      };

      config = lib.mkIf cfg.enable {
        xdg.configFile = {
          "quickshell/tv-files" = {
            source = "${cfg.package}/share/tv-files";
            recursive = true;
          };
          "quickshell/tv-files/services/Theme.qml".source = themeQml;
        };

        systemd.user.services.tv-files = {
          Unit = {
            Description = "Couch-navigable file browser for the TV";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
            # Only meaningful inside a Hyprland session
            ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
            # quickshell allocates a fresh /run/user/$UID/quickshell/by-id
            # instance directory per launch and only cleans it up on a graceful
            # exit, so a crash loop leaks inodes at 1/RestartSec. Unbounded,
            # that exhausts the runtime tmpfs (~814k inodes) in a few days and
            # takes the whole user manager down with it -- generators then fail
            # with ENOSPC and `nixos-rebuild switch` cannot reload the session.
            # Give up after 5 failures instead of degrading the machine.
            StartLimitIntervalSec = 60;
            StartLimitBurst = 5;
          };
          Service = {
            ExecStart = "${qs} -c tv-files";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };

        # Keybind is managed in hyprland.lua via nix-env.lua, same as
        # quickshell-overview.
      };
    };
}
