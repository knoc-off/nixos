# NixOS, home-manager, system configuration, package installation, program enablement, system options.
{ outputs, self, pkgs, upkgs, user, inputs, system, ... }: {
  imports = [
    ./programs/terminal # default
    ./programs/terminal/programs/pueue.nix

    ./programs/terminal/shell
    ./programs/terminal/shell/fish.nix

    ./programs/media/video/mpv.nix

    ./programs/filemanager/yazi.nix

    ./programs/editor/default.nix

    # Desktop and widgets
    ./modules/hyprland

    # Firefox
    ./programs/browser/firefox

    # music
    ./programs/media/audio/spotify.nix
    ./programs/media/audio/framework13-easyeffects.nix

    #./modules/firefox.nix

    ./programs/gaming/lutris.nix
    ./enviroment.nix

    self.homeModules.gtk

    #./programs
    #./desktop
    #./programs/virtualization/bottles.nix

    { # bluetooth
      #       systemd.user.services.mpris-proxy = {
      #         description = "Mpris proxy";
      #         after = [ "network.target" "sound.target" ];
      #         wantedBy = [ "default.target" ];
      #         serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
      #       };

    }

    ./modules/thunderbird.nix

    ./xdg-enviroment.nix

    {
      imports = [ inputs.ags.homeManagerModules.default ];

      programs.ags = {
        enable = true;

        # null or path, leave as null if you don't want hm to manage the config
        #configDir = ./configs;
        configDir = null;

        # additional packages to add to gjs's runtime
        extraPackages = with pkgs; [
          gtksourceview
          # webkitgtk
          webkitgtk_6_0
          accountsservice
          inputs.astal.packages.${system}.default

          inputs.astal.packages.${system}.io
          #inputs.astal.packages.${system}.astal3
          #inputs.astal.packages.${system}.astal4
          inputs.astal.packages.${system}.apps
          inputs.astal.packages.${system}.auth
          inputs.astal.packages.${system}.battery
          inputs.astal.packages.${system}.bluetooth
          inputs.astal.packages.${system}.cava
          inputs.astal.packages.${system}.greet
          inputs.astal.packages.${system}.hyprland
          inputs.astal.packages.${system}.mpris
          inputs.astal.packages.${system}.network
          inputs.astal.packages.${system}.notifd
          inputs.astal.packages.${system}.powerprofiles
          inputs.astal.packages.${system}.river
          inputs.astal.packages.${system}.tray
          inputs.astal.packages.${system}.wireplumber

        ];
      };
      #home.packages = [
      #];

    }

  ];

  services = {
    syncthing.enable = true;
    playerctld.enable = true;
    emailManager = {
      enable = true;
      profile = "${user}";
    };
    batsignal.enable = true;

  };

  wayland.windowManager.hyprlandCustom = { enable = true; };

  programs = {
    git = {
      enable = true;
      userName = "${user}";
      userEmail = "selby@niko.ink";
      lfs.enable = true;

      extraConfig = {
        push = { autoSetupRemote = "true"; };
        alias = {
          # Corrected slog command: reverse-sorted, last 15 commits, most recent at the bottom, with line numbers
          slog = ''
            !git log --all --reverse --pretty=format:'%C(auto)%h %Cgreen%ad %Creset%s%C(auto)%d %C(bold blue)(%an)' --date=short | tail -n 15 | tac | nl -ba -nln -w2 | tac && printf "\n\n"'';

          # Squash alias: interactive rebase for squashing commits
          rebase = "!f() { git rebase -i HEAD~$1; }; f";
        };
      };
    };
    nix-index = { enable = true; };
    home-manager.enable = true;
  };
  # TODO: move this to someplace more logical
  home = {

    packages = with pkgs; [
      (pkgs.python3.withPackages
        (ps: [ ps.llm self.packages.${pkgs.system}.llm-cmd ]))

      self.packages.${pkgs.system}.ttok
      self.packages.${pkgs.system}.spider-cli
      self.packages.${pkgs.system}.tabiew

      upkgs.aider-chat
      #upkgs.claude-code
      #upkgs.astal.hyprland

      lazysql

      #skypeforlinux # skype phone
      audio-recorder

      evince
      slack

      ripcord

      obsidian # notes

      koodo-reader # books

      prismlauncher

      kdePackages.breeze-icons
      kdePackages.grantleetheme
      libsForQt5.grantleetheme

      gnome-calculator

      telegram-desktop

      prusa-slicer

      # ai tools
      fabric-ai
      self.packages.${pkgs.system}.yek

      self.packages.${pkgs.system}.wrap

    ];

    # ~ Battery
    # Battery status, and notifications
    username = "${user}";
    homeDirectory = "/home/${user}";
    # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
    stateVersion = "23.05";

  };

  fonts.fontconfig.enable = true;

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;

    config = {
      allowUnfree = true;
      allowUnfreePredicate = _pkg: true;
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
