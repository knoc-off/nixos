# NixOS, home-manager, system configuration, package installation, program enablement, system options.
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
    ./programs/terminal/kitty
    ./programs/terminal/foot
    ./programs/terminal/programs/pueue.nix

    ./programs/terminal/shell
    ./programs/terminal/shell/fish.nix

    ./programs/media/video/mpv.nix

    ./programs/filemanager/yazi.nix

    ./programs/editor/default.nix

    ./desktop/astal

    # Desktop and widgets
    # ./modules/hyprland

    # Firefox
    ./programs/browser/firefox

    # music
    ./programs/media/audio/spotify.nix
    ./programs/media/audio/framework13-easyeffects.nix

    #./modules/firefox.nix

    ./programs/gaming/lutris.nix
    ./enviroment.nix

    ./desktop/hyprland.nix

    self.homeModules.gtk
    # self.homeModules.hyprland

    self.homeModules.kanata
    self.homeModules.hyprkan
    {
      programs.hyprkan = {
        package = self.packages.${pkgs.system}.hyprkan;
        enable = true;
        service.enable = true;

        service.extraArgs = ["--port" "52545"];

        rules = [
          # Terminal apps use special layer (caps = right meta)
          {
            class = "kitty";
            layer = "special";
          }
          {
            class = "foot";
            layer = "special";
          }

          # Default fallback (caps = control)
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
          extraDefCfg = "danger-enable-cmd yes";
          config = ''
            (deffakekeys
              met lmet
              ctl lctl
            )

            (defalias
              caps-double (tap-dance-eager 250 (XX (cmd ${pkgs.rofi}/bin/rofi -show drun)))
              caps-meta (multi (on-press-fakekey met press) @caps-double (on-release-fakekey met release))
              caps-ctrl (multi (on-press-fakekey ctl press) @caps-double (on-release-fakekey ctl release))
              test-f12 (cmd ${pkgs.rofi}/bin/rofi -show drun)
            )

            (defsrc caps f12)

            (deflayer base @caps-ctrl @test-f12)
            (deflayer special @caps-meta @test-f12)
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

    #./programs
    #./desktop
    #./programs/virtualization/bottles.nix

    {
      # bluetooth
      #       systemd.user.services.mpris-proxy = {
      #         description = "Mpris proxy";
      #         after = [ "network.target" "sound.target" ];
      #         wantedBy = [ "default.target" ];
      #         serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
      #       };
    }

    ./modules/thunderbird.nix

    ./xdg-enviroment.nix
  ];

  services = {
    syncthing.enable = true;
    playerctld.enable = true;
    emailManager = {
      enable = true;
      profile = "${user}";
    };

    # never works reliably
    batsignal.enable = true;
  };

  programs = {
    git = {
      enable = true;
      userName = "${user}";
      userEmail = "selby@niko.ink";
      lfs.enable = true;

      extraConfig = {
        push = {autoSetupRemote = "true";};
        alias = {
          # Corrected slog command: reverse-sorted, last 15 commits, most recent at the bottom, with line numbers
          slog = ''
            !git log --all --reverse --pretty=format:'%C(auto)%h %Cgreen%ad %Creset%s%C(auto)%d %C(bold blue)(%an)' --date=short | tail -n 15 | tac | nl -ba -nln -w2 | tac && printf "\n\n"'';

          # Squash alias: interactive rebase for squashing commits
          rebase = "!f() { git rebase -i HEAD~$1; }; f";
        };
      };
    };
    nix-index = {enable = true;};
    home-manager.enable = true;
  };
  # TODO: move this to someplace more logical

  home = {
    packages = with pkgs; [
      #(pkgs.python3.withPackages
      #(ps: [ ps.llm self.packages.${pkgs.system}.llm-cmd ]))

      #self.packages.${pkgs.system}.ttok
      #self.packages.${pkgs.system}.spider-cli
      #self.packages.${pkgs.system}.tabiew

      upkgs.claude-code
      upkgs.gemini-cli
      upkgs.litellm
      upkgs.prismlauncher
      upkgs.gimp3
      #upkgs.astal.hyprland

      lazysql

      #skypeforlinux # skype phone
      # audio-recorder

      evince # Move this to xdg ...
      slack

      ripcord

      # obsidian # notes

      # koodo-reader # books

      # prismlauncher # Minecraft

      # not sure if i need any of these:
      kdePackages.breeze-icons
      kdePackages.grantleetheme
      libsForQt5.grantleetheme

      # ill make my own calculator soon, with ags.
      gnome-calculator

      # it would be cool to make prusa-slicer declaritive. might work on a module for it. #TODO
      prusa-slicer

      # ai tools
      fabric-ai # Meh. not a fan, but it works well

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
