{
  inputs,
  self,
}:
{
  nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      user = "knoff";
      upkgs = import inputs.nixpkgs-unstable {
        inherit (pkgs) system;
        config = {
          allowUnfree = true;
        };
      };

      inherit (self.lib.keyLayers) presets;

      type-date = pkgs.writeShellApplication {
        name = "type-date";
        runtimeInputs = with pkgs; [
          wtype
          wl-clipboard
          coreutils
        ];
        text = ''
          stamp=$(date +%Y-%m-%dT%H:%M:%S)
          wl-copy --trim-newline "$stamp"
          sleep 0.05
          wtype -M ctrl v -m ctrl
        '';
      };
    in
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        backupFileExtension = "bak";
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit self inputs upkgs; };

        users.${user} =
          {
            pkgs,
            lib,
            config,
            ...
          }:
          {
            imports = [
              self.homeModules.cli-tools
              self.homeModules.ghostty
              self.homeModules.pueue

              self.homeModules.shell
              self.homeModules.scripts
              self.homeModules.fish

              self.homeModules.mpv

              self.homeModules.yazi

              self.homeModules.editor

              self.homeModules.firefox
              self.homeModules.zen-browser

              self.homeModules.environment

              self.homeModules.lspmux
              self.homeModules.claude-mem
              { services.claude-mem.enable = true; }

              self.homeModules.hyprland
              self.homeModules.noctalia
              self.homeModules.stylix
              self.homeModules.quickshell-overview
              { programs.quickshell-overview.enable = true; }

              self.homeModules.easyeffects
              {
                services.easyeffects = {
                  enable = true;

                  autoload.output = {
                    # Built-in speakers get Framework 13 measured EQ correction
                    "alsa_output.pci-0000_c1_00.6.analog-stereo:Speakers" = {
                      preset = "framework-speakers";
                      description = "Ryzen HD Audio Controller Analog Stereo";
                    };
                    # Wired headphones -- no processing
                    "alsa_output.pci-0000_c1_00.6.analog-stereo:Headphones" = {
                      preset = "passthrough";
                      description = "Ryzen HD Audio Controller Analog Stereo";
                    };
                    # AirPods Pro 2 (A2DP) -- no processing
                    "bluez_output.F0_04_E1_D9_23_73.1:Headphone" = {
                      preset = "passthrough";
                      description = "AirPods Pro";
                    };
                    # AirPods Pro 2 (HFP/handsfree) -- no processing
                    "bluez_output.F0_04_E1_D9_23_73.1:Handsfree" = {
                      preset = "passthrough";
                      description = "AirPods Pro";
                    };
                  };

                  autoload.input = {
                    # Built-in mic gets noise suppression
                    "alsa_input.pci-0000_c1_00.6.analog-stereo:Internal Microphone" = {
                      preset = "mic-denoise";
                      description = "Ryzen HD Audio Controller Analog Stereo";
                    };
                  };
                };
              }

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

              {
                # Plain Anki, no addons -- marki writes directly into the
                # collection file via SQLite. Anki must be closed while
                # running `marki push`, since it holds an exclusive lock
                # on the collection for its entire runtime.
                home.packages = [ pkgs.anki ];
              }

              self.homeModules.kanata
              self.homeModules.hyprkan
              self.homeModules.keylayers
              {
                keyLayers = {
                  enable = true;
                  layers.base.capsbinds = {
                    ctrl = presets.baseCtrlKeys;
                    keys = presets.navKeys;
                  };
                };
              }
              {
                programs.hyprkan = {
                  package = self.packages.${pkgs.stdenv.hostPlatform.system}.hyprkan;
                  enable = true;
                  service.enable = true;

                  service.extraArgs = [
                    "--port"
                    "52545"
                  ];
                };
              }

              {
                services.kanata = {
                  enable = true;
                  package = upkgs.kanata-with-cmd;

                  keyboards.main = {
                    devices = [ ]; # Auto-detect keyboards
                    excludeDevices = [
                      "Logitech USB Receiver"
                    ];
                    port = 52545;
                    extraDefCfg = "danger-enable-cmd yes process-unmapped-keys yes";
                  };
                };
              }

              self.homeModules.thunderbird

              self.homeModules.xdg

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
              username = user;
              homeDirectory = "/home/${user}";

              packages = with pkgs; [
                upkgs.orca-slicer
                upkgs.foliate
                upkgs.readest

                upkgs.trilium-desktop

                upkgs.notion-app-enhanced

                self.packages.${pkgs.stdenv.hostPlatform.system}.neovim
                self.packages.${pkgs.stdenv.hostPlatform.system}.opencode-bubblewrap

                spotify

                # Must come from nixpkgs, not unstable: the session's Kvantum/qt6ct
                # style plugins are built against nixpkgs' qtbase. An unstable
                # prismlauncher links a newer qtbase, so qt6ct fails to resolve
                # kvantum as its base style and proxies itself instead, recursing
                # in QProxyStyle::standardPalette until the stack overflows.
                prismlauncher

                gnome-calculator

                prusa-slicer

                openscad

                usbutils
                watchexec
                quicksand

                libratbag
                piper

                sops # should maybe source this package somewhere common.
              ];

              stateVersion = "23.05";
            };

            fonts.fontconfig.enable = true;

            systemd.user.startServices = "sd-switch";
          };
      };
    };
}
