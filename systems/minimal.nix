{
  lib,
  inputs,
  pkgs,
  self,
  hostname,
  user,
  config,
  ...
}: {
  imports = [
    ./hardware/hardware-configuration.nix
    # ./hardware/boot.nix

    ./modules/shell/fish.nix
    {
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true; # this should likely be changed to false, since ssh keys... but need it for now
          KbdInteractiveAuthentication = true;
          PermitRootLogin = lib.mkDefault "yes";
        };
      };
    }
    {
      system.activationScripts.populateEtcNixos = let
        configSrc = builtins.path {
          path = ../.;
          name = "nixos-config-src";
        };
      in
        lib.stringAfter ["etc"] ''
          set -euo pipefail
          dst=/etc/nixos
          mkdir -p "$dst"

          if [ ! -e "$dst/.image-config-installed" ]; then
            rm -rf "$dst"/*
            cp -aT "${configSrc}" "$dst"
            chmod -R u+rwX,go+rX "$dst" || true
            touch "$dst/.image-config-installed"
          fi
        '';
    }

    {
      services.xserver.xkb.layout = "us";
    }

    {
      console = {
        packages = with pkgs; [terminus_font];
        font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
        useXkbConfig = true;
      };
    }
    {
      fonts = {
        enableDefaultPackages = true;
        packages = with pkgs; [
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          liberation_ttf
          fira-code
          fira-code-symbols
          mplus-outline-fonts.githubRelease
          dina-font
          proggyfonts
          pkgs.nerd-fonts.fira-code
        ];
        fontconfig.defaultFonts = {
          monospace = ["FiraCode Nerd Font Mono"];
        };
      };
    }

    {
      programs = {
        nix-ld = {
          enable = true;
          libraries = with pkgs; [
            stdenv.cc.cc
            SDL2
            SDL2_image
            libz
          ];
        };
        dconf.enable = true;
      };
    }

    {
      nixpkgs.config.allowUnfree = true;
      nix = {
        registry = {
          nixpkgs.flake = inputs.nixpkgs;
          nixos-hardware.flake = inputs.hardware;
        };
        nixPath = ["nixpkgs=${inputs.nixpkgs}"];
      };
    }

    {
      services.greetd = let
        tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
      in {
        enable = true;
        settings = {
          default_session = {
            command = "${tuigreet} --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
            user = "greeter";
          };
        };
      };
    }

    # does this work?
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-cpu-intel

    self.nixosModules.misc
  ];

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # bootloader = {
  #   type = "lanzaboote";
  #   efiSupport = true;
  # };
  networking.hostName = "minimal-nix";

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  users = {
    users.${user} = {
      shell = pkgs.fish;
      isNormalUser = lib.mkDefault true;
      extraGroups =
        [
          "wheel"
          "audio"
          "video"
          "dialout"
          "uinput"
          "input"
          "lp"
        ]
        ++ (
          if config.virtualisation.libvirtd.enable
          then ["libvirtd"]
          else []
        )
        ++ (
          if config.networking.networkmanager.enable
          then ["networkmanager"]
          else []
        );
      initialPassword = "password";
      openssh.authorizedKeys.keys = [];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7HocV04erAJfAT9swZ/PBsrVkwySxkX5b6rGRaTXAh niko@mac" # Delete this tbh

    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  # needed?
  # system.stateVersion = "23.11";
}
