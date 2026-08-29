{
  ...
}:
{
  home =
    {
      config,
      lib,
      pkgs,
      upkgs,
      ...
    }:
    let
      system = pkgs.stdenv.hostPlatform.system;
      noctaliaCmd = lib.getExe config.programs.noctalia.package;

      mainMod = "SUPER";

      displayScale = 2;

      # Same self-contained plugin fragments as the laptop config. kinetic-scroll
      # is kept for the couch touchpad; scroll-overview is the primary "remote"
      # navigation surface.
      hyprPlugins = [
        (import ../hyprland/plugins/kinetic-scroll.nix { inherit pkgs upkgs lib; })
        (import ../hyprland/plugins/scroll-overview.nix {
          inherit
            pkgs
            upkgs
            lib
            mainMod
            ;
        })
      ];

      pluginsLua = pkgs.writeText "plugins.lua" (lib.concatMapStringsSep "\n" (p: p.lua) hyprPlugins);

      nixEnvLua = pkgs.writeText "nix-env.lua" ''
        local M = {}
        M.noctalia = "${noctaliaCmd}"
        M.wpctl = "${pkgs.wireplumber}/bin/wpctl"
        M.playerctl = "${lib.getExe pkgs.playerctl}"
        M.display_scale = ${toString displayScale}
        M.qs = "${lib.getExe config.programs.tv-files.quickshellPackage}"
        return M
      '';
    in
    {
      # Idle policy (screen blanking + service teardown) lives in the tv-away
      # module, which owns hypridle so both fire off a single timeout.
      wayland.windowManager.hyprland = {
        enable = true;
        package = upkgs.hyprland;
        systemd.enable = false; # UWSM handles session/systemd integration

        # Enabling the module otherwise turns on home-manager's own xdg.portal
        # layer, which sets NIX_XDG_DESKTOP_PORTAL_DIR to the user profile and
        # so hides every portal declared at the system level -- including the
        # RemoteDesktop backend KDE Connect needs. Portals live in the NixOS
        # config (modules/users/tv.nix).
        portalPackage = null;

        configType = "lua";
      };

      xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;
      xdg.configFile."hypr/nix-env.lua".source = nixEnvLua;
      xdg.configFile."hypr/plugins.lua".source = pluginsLua;

      home.activation.seedHyprUserConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.config/hypr/user.lua"
        if [ ! -f "$target" ]; then
          install -Dm644 ${../hyprland/user-default.lua} "$target"
        fi
      '';
    };
}
