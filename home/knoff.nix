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

  caps = mkCapsLayers {
    base = {
      ctrl = ["a" "b" "c" "f" "h" "i" "j" "k" "l" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
    };
    browser = {
      classes = ["firefox" "chromium-browser"];
      ctrl = ["a" "b" "c" "f" "h" "i" "j" "k" "l" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
      #keys.t = {raw = "(tap-dance 300 (C-c C-S-c))";};
    };
    terminal = {
      classes = ["com.mitchellh.ghostty" "foot"];
      ctrl = ["h" "j" "k" "l"];
      alt = ["e"];
      keys.d = {
        mod = "shift";
        key = "z";
      };

      # keys = {
      #   # String shorthand: "ctrl" / "shift" / "alt"
      #   # Same as putting the key in the bulk list above.
      #   # d = "ctrl";                           # caps+d → Ctrl+D
      #
      #   # Modifier + same key (explicit form of the shorthand):
      #   # d = { mod = "ctrl"; };                # caps+d → Ctrl+D
      #
      #   # Modifier + DIFFERENT key:
      #   # d = { mod = "shift"; key = "z"; };    # caps+d → Shift+Z
      #
      #   # Bare key, no modifier:
      #   # d = { key = "esc"; };                 # caps+d → Escape
      #
      #   # Run a command:
      #   # e = {cmd = "${pkgs.libnotify}/bin/notify-send hi";};
      #
      #   # Raw kanata:
      #   # F6 = { raw = "(tap-hold 200 200 C-z C-S-z)"; };
      #   #
      #   # F7 = { raw = "(tap-dance 300 (C-c C-S-c))"; };
      #   #    caps+F7: single tap → Ctrl+C, double tap → Ctrl+Shift+C
      # };
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
