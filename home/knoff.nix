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

    # Firefox
    ./programs/browser/firefox

    # ./programs/gaming/lutris.nix
    ./enviroment.nix

    ./desktop/hyprland.nix

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
    # self.homeModules.hyprland

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
          # Terminal apps use special layer (caps = right meta)
          {
            class = "com.mitchellh.ghostty";
            layer = "terminal";
          }
          {
            class = "foot";
            layer = "terminal";
          }

          # Default fallback provides mappings for common ctrl shortcuts
          {
            class = "*";
            title = "*";
            layer = "base";
          }
        ];
      };
    }

    # Kanata keyboard remapping via home module
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

        # keyboards.mx-master = {
        #   devices = ["/dev/input/by-id/usb-Logitech_USB_Receiver-if01-event-mouse"];
        #   extraDefCfg = "danger-enable-cmd yes";
        #   config = ''
        #     (defalias
        #       rofi-launch (cmd ${pkgs.rofi}/bin/rofi -show drun)
        #       scroll-slow (cmd ${pkgs.libratbag}/bin/ratbagctl wheel set multiplier 0.3)
        #       scroll-fast (cmd ${pkgs.libratbag}/bin/ratbagctl wheel set multiplier 2.0)
        #       wheel-smooth (cmd ${pkgs.libratbag}/bin/ratbagctl wheel set mode smooth)
        #       wheel-ratchet (cmd ${pkgs.libratbag}/bin/ratbagctl wheel set mode ratchet)
        #     )

        #     (defsrc
        #       mbck mfwd mwu mwd)

        #     (deflayer base
        #       @rofi-launch mmid mwu mwd)
        #   '';
        # };
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

    # never works reliably
    batsignal.enable = true;
  };

  programs = {
    nix-index = {
      enable = true;
    };
    home-manager.enable = true;
  };
  # TODO: move this to someplace more logical

  home = {
    packages = with pkgs; [
      self.packages.${pkgs.stdenv.hostPlatform.system}.neovim-nix.default
      spotify

      #(pkgs.python3.withPackages
      #(ps: [ ps.llm self.packages.${pkgs.stdenv.hostPlatform.system}.llm-cmd ]))

      #self.packages.${pkgs.stdenv.hostPlatform.system}.ttok
      #self.packages.${pkgs.stdenv.hostPlatform.system}.spider-cli
      #self.packages.${pkgs.stdenv.hostPlatform.system}.tabiew

      upkgs.opencode

      upkgs.claude-code
      # (upkgs.claude-code.overrideAttrs (oldAttrs: rec {
      #   version = "2.0.52";
      #   src = pkgs.fetchzip {
      #     url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      #     hash = "sha256-lYVuWP9ekI+xeUXNCXVqcq8OIzZwfdgBpk0PhSIStFs=";
      #   };
      # }))
      # ai tools
      fabric-ai # Meh. not a fan, but it works well
      upkgs.gemini-cli
      upkgs.litellm
      upkgs.prismlauncher
      upkgs.gimp3
      #upkgs.astal.hyprland

      lazysql

      evince # Move this to xdg ...
      # slack

      ripcord

      upkgs.obsidian

      # koodo-reader # books

      # prismlauncher # Minecraft

      # not sure if i need any of these:
      # kdePackages.breeze-icons

      # ill make my own calculator soon, with ags.
      gnome-calculator

      # it would be cool to make prusa-slicer declaritive. might work on a module for it. #TODO
      prusa-slicer

      openscad

      usbutils
      watchexec
      quicksand

      # Mouse configuration tools
      libratbag
      piper
    ];

    stateVersion = "23.05";
  };

  fonts.fontconfig.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
