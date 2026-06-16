{
  inputs,
  self,
}: {
  nixos = {
    pkgs,
    lib,
    config,
    ...
  }: let
    user = "niko";
    upkgs = import inputs.nixpkgs-unstable {
      inherit (pkgs) system;
      config = {allowUnfree = true;};
    };

    inherit (self.lib.keyLayers) presets;

    type-date = pkgs.writeShellApplication {
      name = "type-date";
      runtimeInputs = with pkgs; [wtype wl-clipboard coreutils];
      text = ''
        stamp=$(date +%Y-%m-%dT%H:%M:%S)
        wl-copy --trim-newline "$stamp"
        sleep 0.05
        wtype -M ctrl v -m ctrl
      '';
    };
  in {
    imports = [inputs.home-manager.nixosModules.home-manager];

    home-manager = {
      backupFileExtension = "bak";
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {inherit self inputs upkgs;};

      users.${user} = {
        pkgs,
        lib,
        config,
        ...
      }: {
        imports = [
          self.homeModules.cli-tools
          self.homeModules.ghostty
          self.homeModules.pueue
          self.homeModules.opencode

          self.homeModules.shell
          self.homeModules.scripts
          self.homeModules.fish

          self.homeModules.mpv

          self.homeModules.yazi

          self.homeModules.editor

          self.homeModules.firefox

          self.homeModules.environment

          self.homeModules.lspmux
          self.homeModules.claude-token-refresh
          self.homeModules.claude-mem
          {services.claude-mem.enable = true;}
          self.homeModules.host-query
          {services.host-query.enable = true;}

          self.homeModules.hyprland
          self.homeModules.noctalia
          self.homeModules.stylix

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
                # Wired headphones
                "alsa_output.pci-0000_c1_00.6.analog-stereo:Headphones" = {
                  preset = "passthrough";
                  description = "Ryzen HD Audio Controller Analog Stereo";
                };
                # AirPods Pro 2 (A2DP)
                "bluez_output.F0_04_E1_D9_23_73.1:Headphone" = {
                  preset = "passthrough";
                  description = "AirPods Pro";
                };
                # AirPods Pro 2 (HFP/handsfree)
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

          self.homeModules.compat-proxy
          # Fuck anthropic
          {
            services.compat-proxy = {
              enable = true;
              port = 58192;

              clients.opencode = {
                systemPrompt.replaceWithFile = "system-prompts/cc-2.1.97.txt";

                toolRenames = [
                  {
                    from = "bash";
                    to = "Bash";
                  }
                  {
                    from = "read";
                    to = "Read";
                  }
                  {
                    from = "write";
                    to = "Write";
                  }
                  {
                    from = "edit";
                    to = "Edit";
                  }
                  {
                    from = "glob";
                    to = "Glob";
                  }
                  {
                    from = "grep";
                    to = "Grep";
                  }
                  {
                    from = "webfetch";
                    to = "WebFetch";
                  }
                  {
                    from = "todowrite";
                    to = "TodoWrite";
                  }
                  {
                    from = "task";
                    to = "Task";
                  }
                  {
                    from = "question";
                    to = "AskUser";
                  }
                  {
                    from = "grep_searchGitHub";
                    to = "GithubSearch";
                  }
                  {
                    from = "context7_resolve-library-id";
                    to = "LibrarySearch";
                  }
                  {
                    from = "context7_query-docs";
                    to = "LibraryDocs";
                  }
                ];

                toolDrops = ["skill"];
                unmappedPolicy = "passthrough";
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
          {programs.starshipLinear.enable = true;}

          self.homeModules.kanata
          self.homeModules.hyprkan
          self.homeModules.keylayers
          self.homeModules.slack
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
                devices = []; # Auto-detect keyboards
                excludeDevices = [
                  "Logitech USB Receiver"
                ];
                port = 52545;
                extraDefCfg = "danger-enable-cmd yes process-unmapped-keys yes";
              };
            };
          }

          self.homeModules.xdg
        ];

        home = {
          username = user;
          homeDirectory = "/home/${user}";
        };

        # lspmux settings (inlined from services/lspmux.nix)
        services.lspmux.settings = {
          instance_timeout = 3600; # 1 hour
          pass_environment = [
            #  basic runtime
            "HOME"
            "PATH"

            "RUST_SRC_PATH"
            "RUSTUP_HOME"
            "CARGO_HOME"

            "RUSTFLAGS"
            "CARGO_BUILD_RUSTFLAGS"
            "CARGO_ENCODED_RUSTFLAGS"
            "CARGO_PROFILE"
            "CARGO_TERM_COLOR"

            "CARGO_BUILD_TARGET"
            "RA_TARGET"

            "SQLX_OFFLINE"
            "DATABASE_URL"

            "CC"
            "CXX"
            "AR"
            "AS"
            "LD"
            "RANLIB"
            "NM"
            "OBJCOPY"
            "OBJDUMP"
            "READELF"
            "STRIP"
            "SIZE"
            "STRINGS"

            "CFLAGS"
            "CXXFLAGS"
            "CPPFLAGS"
            "LDFLAGS"
            "CL_FLAGS"

            "PKG_CONFIG"
            "PKG_CONFIG_PATH"
            "PKG_CONFIG_LIBDIR"
            "PKG_CONFIG_SYSROOT_DIR"

            "CMAKE_INCLUDE_PATH"
            "CMAKE_LIBRARY_PATH"
            "NIXPKGS_CMAKE_PREFIX_PATH"

            "LD_LIBRARY_PATH"
            "NIX_LD"
            "NIX_LD_LIBRARY_PATH"

            "NIX_CC"
            "NIX_BINTOOLS"
            "NIX_CFLAGS_COMPILE"
            "NIX_LDFLAGS"

            "NIX_CC_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu"
            "NIX_BINTOOLS_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu"
            "NIX_PKG_CONFIG_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu"

            "NIX_STORE"
            "NIX_SSL_CERT_FILE"
            "NIX_PATH"
            "NIX_PROFILES"
            "NIX_USER_PROFILE_DIR"
            "IN_NIX_SHELL"
          ];
        };

        # linear
        home.sessionVariables = {
          LINEAR_TEAM_ID = "int";
          LINEAR_ISSUE_SORT = "priority";

          # Build Rust artifacts in RAM (tmpfs at /cargo-ram, defined in the
          # thinkpad-work system config) to keep the build write storm off the
          # encrypted btrfs NVMe. rust-analyzer is unaffected: it has its own
          # on-disk targetDir and CARGO_TARGET_DIR isn't in lspmux pass_environment.
          CARGO_TARGET_DIR = "/cargo-ram/target";
        };

        services = {
          playerctld.enable = true;

          batsignal.enable = true;
        };

        programs = {
          nix-index = {
            enable = true;
          };
          home-manager.enable = true;
        };

        home.packages = with pkgs; [
          upkgs.foliate
          upkgs.readest

          self.packages.${pkgs.stdenv.hostPlatform.system}.opencode-bubblewrap
          self.packages.${pkgs.stdenv.hostPlatform.system}.neovim.default

          inputs.nelly.packages.${pkgs.stdenv.hostPlatform.system}.linear-cli
          spotify

          upkgs.opencode

          upkgs.claude-code

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

        home.stateVersion = "23.05";

        fonts.fontconfig.enable = true;

        systemd.user.startServices = "sd-switch";
      };
    };
  };
}
