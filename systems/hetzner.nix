{ modulesPath, inputs, outputs, config, lib, pkgs, ... }: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/hetzner/default.yaml;
        # This will automatically import SSH keys as age keys
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

        secrets = if config.services.nextcloud.enable then {
          "services/nextcloud/admin-pass" = {
            owner = config.users.users.nextcloud.name;
          };
        } else
          { };
      };
    }
    # Disko
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    # nix package settings
    ./modules/nix.nix

    # services
    ./services/nginx.nix

    # mail
    ./services/imapfilter

    # Matrix
    #./services/matrix/dendrite.nix

    # Syncthing
    ./services/syncthing.nix

    # KitchenOwl
    ./services/kitchenowl.nix

  ];

  # trilium notes:
  # override the trilium package to pull from a different source

  nixpkgs.overlays = [
    (final: prev: { # i might just package this myself. and override with my package.
      trilium-server = prev.trilium-server.overrideAttrs (oldAttrs: {
        src = pkgs.fetchFromGitHub {
          owner = "TriliumNext";
          repo = "Notes";
          rev = "v0.90.8";
          sha256 = "sha256-SiU0+BX/CmiiCqve12kglh6Qa2TtTYIYENGFwyGiMsU=";
        };

        #buildInputs = oldAttrs.buildInputs ++ [ pkgs.nodejs ];
        postInstall = ''
          # Link nodejs to the expected location
          mkdir -p $out/share/trilium-server/node/bin
          ln -s ${pkgs.nodejs}/bin/node $out/share/trilium-server/node/bin/node
        '';

        # remove the patches
        patches = [];
      });
    })
  ] ++ builtins.attrValues outputs.overlays;

  # test
  services.trilium-server.enable = true;

  #nixpkgs.overlays = ;

  nix.settings.auto-optimise-store = true;

  networking.hostName = "oink";
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [ pkgs.curl pkgs.gitMinimal ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "23.11";
}
