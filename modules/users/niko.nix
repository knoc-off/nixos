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

    mkKeyLayers = import ../../lib/key-layers.nix {inherit lib;};

    noctalia' = cmd:
      lib.concatStringsSep " " (
        ["noctalia-shell" "ipc" "call"] ++ (lib.splitString " " cmd)
      );

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

    # Not ideal with how its handled because it will act like caps is being clicked, and not held.
    navKeys = {
      h = {key = "left";};
      j = {key = "down";};
      k = {key = "up";};
      l = {key = "right";};
      d = {raw = "(multi (release-key rmet) (mwheel-accel-down 50 150 1.05 0.80))";};
      u = {raw = "(multi (release-key rmet) (mwheel-accel-up 50 150 1.05 0.80))";};
    };

    keyLayers = mkKeyLayers {
      base = {
        capsbinds = {
          ctrl = ["a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
          keys = navKeys;
        };
      };
      slack = {
        classes = ["Slack"];
        capsbinds = {
          ctrl = ["enter" "tab" "a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
          keys =
            navKeys
            // {
              g = {raw = "(tap-dance 200 ((multi (release-key rmet) C-end) (multi (release-key rmet) C-home)))";};
            };
        };
      };
      browser = {
        classes = ["firefox" "chromium-browser"];
        capsbinds = {
          ctrl = ["enter" "tab" "a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
          keys =
            navKeys
            // {
              g = {raw = "(tap-dance 200 ((multi (release-key rmet) C-end) (multi (release-key rmet) C-home)))";};
            };
        };
      };
      freecadExprEditor = {
        matchers = [
          {
            class = "org.freecad.FreeCAD";
            title = "Expression editor";
          }
        ];
        capsbinds = {
          ctrl = ["enter" "tab" "a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
          keys =
            navKeys
            // {
              g = {raw = "(tap-dance 200 ((multi (release-key rmet) C-end) (multi (release-key rmet) C-home)))";};
            };
        };
        binds = {
          tab = {
            default = "down";
            shift = "up";
          };
        };
      };
      terminal = {
        classes = ["com.mitchellh.ghostty" "foot"];
        capsbinds = {
          alt = ["e"];
          shift = [";"];
          keys =
            navKeys
            // {
              d = {raw = "(multi (release-key rmet) (mwheel-down 50 1 ))";};
              u = {raw = "(multi (release-key rmet) (mwheel-up 50 1 ))";};
            };
        };
      };
    };
  in {
    imports = [inputs.home-manager.nixosModules.home-manager];

    home-manager = {
      backupFileExtension = "bak";
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = {inherit self inputs;};

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
                # Wired headphones — no processing
                "alsa_output.pci-0000_c1_00.6.analog-stereo:Headphones" = {
                  preset = "passthrough";
                  description = "Ryzen HD Audio Controller Analog Stereo";
                };
                # AirPods Pro 2 (A2DP) — no processing
                "bluez_output.F0_04_E1_D9_23_73.1:Headphone" = {
                  preset = "passthrough";
                  description = "AirPods Pro";
                };
                # AirPods Pro 2 (HFP/handsfree) — no processing
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

              rules = keyLayers.hyprkanRules;
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

                config = keyLayers.kanataConfig ''
                  launcher (cmd ${noctalia' "launcher toggle"})
                  dbl (tap-dance-eager 250 (XX @launcher))
                '';
              };
            };
          }

          self.homeModules.thunderbird

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
        };

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

        home.packages = with pkgs; [
          upkgs.foliate
          upkgs.readest

          upkgs.slack

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

          upkgs.freecad-wayland
        ];

        home.stateVersion = "23.05";

        fonts.fontconfig.enable = true;

        systemd.user.startServices = "sd-switch";
      };
    };
  };
}
