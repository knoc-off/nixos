{
  self,
  pkgs,
  upkgs,
  user,
  lib,
  ...
}: let
  mkCapsLayers = import ./caps-layers.nix {inherit lib;};

  noctalia' = cmd:
    lib.concatStringsSep " " (
      ["noctalia-shell" "ipc" "call"] ++ (lib.splitString " " cmd)
    );

  navKeys = {
    h = {key = "left";};
    j = {key = "down";};
    k = {key = "up";};
    l = {key = "right";};
    d = {raw = "(multi (release-key rmet) (mwheel-accel-down 50 150 1.05 0.80))";};
    u = {raw = "(multi (release-key rmet) (mwheel-accel-up 50 150 1.05 0.80))";};
  };

  caps = mkCapsLayers {
    base = {
      ctrl = ["a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
      keys = navKeys;
    };
    browser = {
      classes = ["firefox" "chromium-browser"];
      ctrl = ["a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
      keys = navKeys;
    };
    terminal = {
      classes = ["com.mitchellh.ghostty" "foot"];
      alt = ["e"];
      keys =
        navKeys
        // {
          d = {raw = "(multi (release-key rmet) (mwheel-down 50 1 ))";};
          u = {raw = "(multi (release-key rmet) (mwheel-up 50 1 ))";};
        };
    };
  };
in {
  imports = [
    ./programs/terminal # default
    ./programs/terminal/ghostty
    ./programs/terminal/foot
    ./programs/terminal/programs/pueue.nix
    ./programs/terminal/programs/opencode.nix

    ./programs/terminal/shell
    ./programs/terminal/shell/fish.nix

    ./programs/media/video/mpv.nix

    ./programs/filemanager/yazi.nix

    ./programs/editor/default.nix

    ./programs/browser/firefox

    ./enviroment.nix

    ./services/lspmux.nix

    self.homeModules.hyprland
    self.homeModules.noctalia
    self.homeModules.stylix

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

        rules = caps.hyprkanRules;
      };
    }

    {
      services.kanata = {
        enable = true;
        package = upkgs.kanata-with-cmd;

        keyboards.main = {
          devices = []; # Auto-detect keyboards
          excludeDevices = [
            "Logitech USB Receiver"
          ];
          port = 52545;
          extraDefCfg = "danger-enable-cmd yes process-unmapped-keys yes";

          config = caps.kanataConfig ''
            launcher (cmd ${noctalia' "launcher toggle"})
            dbl (tap-dance-eager 250 (XX @launcher))
          '';
        };
      };
    }

    ./modules/thunderbird.nix
    # ./services/rclone.nix

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
      upkgs.foliate
      upkgs.readest

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
