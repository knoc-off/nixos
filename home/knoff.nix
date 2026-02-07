{
  outputs,
  self,
  pkgs,
  upkgs,
  user,
  inputs,
  system,
  color-lib,
  theme,
  ...
}: {
  imports = [
    ./programs/terminal # default
    ./programs/terminal/ghostty
    ./programs/terminal/foot
    ./programs/terminal/programs/pueue.nix
    ./programs/terminal/programs/opencode.nix

    ./desktop/dunst.nix

    ./programs/terminal/shell
    ./programs/terminal/shell/fish.nix

    ./programs/media/video/mpv.nix

    ./programs/filemanager/yazi.nix

    ./programs/editor/default.nix

    ./programs/browser/firefox

    ./enviroment.nix


    self.homeModules.niri
    self.homeModules.noctalia

    self.homeModules.gtk
    self.homeModules.git
    {
      programs.git = {
        enable = true;
        settings.user = {
          name = "${user}";
          email = "selby@niko.ink";
        };
      };
    }
    self.homeModules.starship

    self.homeModules.kanata
    self.homeModules.hyprkan
    {
      programs.hyprkan = {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.hyprkan;
        enable = true;
        service.enable = true;

        service.extraArgs = [
          "--port"
          "52545"
        ];

        rules = [
          {
            class = "com.mitchellh.ghostty";
            layer = "terminal";
          }
          {
            class = "foot";
            layer = "terminal";
          }

          {
            class = "*";
            title = "*";
            layer = "base";
          }
        ];
      };
    }

    {
      services.kanata = {
        enable = true;
        package = pkgs.kanata-with-cmd;

        keyboards.main = {
          devices = []; # Auto-detect keyboards
          excludeDevices = [
            "Logitech USB Receiver"
          ];
          port = 52545;
          extraDefCfg = "danger-enable-cmd yes process-unmapped-keys yes";

          config = let
            # These keys exit super, and send it as if it were control.
            passthroughSuperToCtrlMorph = ["a" "b" "c" "f" "i" "l" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
          in ''
            (defalias
              rofi (cmd ${pkgs.rofi}/bin/rofi -show drun)
              dbl  (tap-dance-eager 250 (XX @rofi))

              ;; GUI: Caps = Meta + shortcuts layer
              cap-gui (multi lmet @dbl (layer-while-held shortcuts))

              ;; Terminal: Caps = just Meta
              cap-trm (multi lmet @dbl)

              ;; example for a toggle bind. not super clean...
              to-trm (layer-switch terminal)
              to-gui (layer-switch base)
              f12  (tap-dance 300 (@rofi @to-trm))
              f12t (tap-dance 300 (@rofi @to-gui))

              ;; Shortcuts: release meta, send Ctrl+key Press meta again
              ${builtins.concatStringsSep "\n" (map (k: "sc${k} (multi (release-key lmet) C-${k})") passthroughSuperToCtrlMorph)}
            )

            (defsrc caps f12)
            (deflayer base     @cap-gui @f12)
            (deflayer terminal @cap-trm @f12t)

            (deflayermap (shortcuts)
              ${builtins.concatStringsSep "  " (map (k: "${k} @sc${k}") passthroughSuperToCtrlMorph)}
            )
          '';
        };
      };
    }

    ./modules/thunderbird.nix
    ./services/rclone.nix

    ./xdg-enviroment.nix
  ];

  services = {
    playerctld.enable = true;
    emailManager = {
      enable = true;
      profile = "${user}";
    };

    batsignal.enable = true;
  };

  programs = {
    nix-index = {
      enable = true;
    };
    home-manager.enable = true;
  };

  home = {
    packages = with pkgs; [
      self.packages.${pkgs.stdenv.hostPlatform.system}.neovim-nix.default
      spotify

      upkgs.opencode

      upkgs.claude-code
      fabric-ai
      upkgs.gemini-cli

      gnome-calculator

      prusa-slicer

      openscad

      usbutils
      watchexec
      quicksand

      libratbag
      piper
    ];

    stateVersion = "23.05";
  };

  fonts.fontconfig.enable = true;

  systemd.user.startServices = "sd-switch";
}
