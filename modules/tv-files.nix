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
      themeQml = pkgs.writeText "tv-files-theme.qml" ''
        pragma Singleton
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
