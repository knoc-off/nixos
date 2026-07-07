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
    user = "knoff";
    upkgs = import inputs.nixpkgs-unstable {
      inherit (pkgs) system;
      config = {allowUnfree = true;};
    };

    inherit (self.lib.keyLayers) presets;

    hayleox-flags = pkgs.callPackage ../../pkgs/hayleox-flags {};

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

    # On-demand PA monitor: routes the EasyEffects-processed mic
    # (easyeffects_source, i.e. the pa-voice chain) into the current default
    # sink via pw-loopback. Foreground; Ctrl-C tears it down cleanly. Choose the
    # output with the normal default-sink controls (wpctl / audio applet).
    pa-monitor = pkgs.writeShellApplication {
      name = "pa-monitor";
      runtimeInputs = with pkgs; [pipewire jq];
      text = ''
        src="easyeffects_source"

        if ! pw-cli info "$src" >/dev/null 2>&1; then
          echo "pa-monitor: source '$src' not found -- is easyeffects running?" >&2
          echo "            (start easyeffects and select the mic as its input)" >&2
          exit 1
        fi

        sink=$(pw-dump | jq -r '
          [ .[] | select(.props."metadata.name"=="default")
                | .metadata[]? | select(.key=="default.audio.sink") | .value.name ]
          | first // empty')

        if [ -z "$sink" ]; then
          echo "pa-monitor: no default sink found." >&2
          exit 1
        fi

        echo "pa-monitor: $src -> $sink  (Ctrl-C to stop)"
        exec pw-loopback -n pa-monitor -C "$src" -P "$sink"
      '';
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
          self.homeModules.quickshell-overview
          {programs.quickshell-overview.enable = true;}

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
                # External mic on the C-Media USB adapter gets the live-voice/PA chain.
                # NOTE: the internal analog mic is intentionally left unprocessed. An
                # always-on `mic-denoise` (rnnoise) autoload here keeps the internal mic
                # permanently capturing and makes it the graph clock driver at a 256-frame
                # quantum, which starved the shared speaker-output graph and caused constant
                # playback crackle. rnnoise on the internal mic is not worth that cost.
                "alsa_input.usb-0d8c_Generic_USB_Audio_Device-00.mono-fallback:Microphone" = {
                  preset = "pa-voice";
                  description = "Audio Adapter (Planet UP-100, Genius G-Talk) Mono";
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

          # self.homeModules.markid
          # {
          #   services.markid = {
          #     enable = true;
          #     settings.cards_dir = "/home/knoff/projects/flashcards";
          #     mediaSources = {
          #       circle = "${pkgs.circle-flags}/share/circle-flags-svg";
          #       flags = "${hayleox-flags}/share/hayleox-flags";
          #     };
          #     typstPackage = pkgs.typst.withPackages (p:
          #       with p; [
          #         circuiteria
          #         cetz
          #         cetz_0_3_4
          #         oxifmt_0_2_1
          #         zap
          #       ]);
          #   };
          #   # Anki with AnkiConnect pre-installed — launch as a normal desktop app,
          #   # markid connects via wait_for_anki() once it's open.
          #   home.packages = [
          #     (pkgs.anki.withAddons (with pkgs.ankiAddons; [anki-connect]))
          #   ];
          # }

          self.homeModules.compat-proxy
          {
            services.compat-proxy = {
              enable = true;
              port = 58192;
              sessionLog = true;

              # Pull CC subagent prompts from Piebald repo
              extraSystemPrompts = let
                piebald = "${inputs.claude-code-system-prompts}/system-prompts";
              in {
                "cc-explore.txt" = "${piebald}/agent-prompt-explore.md";
                "cc-general.txt" = "${piebald}/agent-prompt-general-purpose.md";
                "cc-title.txt" = "${piebald}/agent-prompt-coding-session-title-generator.md";
                "cc-summary.txt" = "${piebald}/agent-prompt-conversation-summarization.md";
                "cc-plan.txt" = "${piebald}/agent-prompt-plan-mode-enhanced.md";
              };

              clients.opencode = {
                # Fallback for unmarked requests
                systemPrompt.replaceWithFile = "system-prompts/cc-2.1.97.txt";

                systemPrompt.markers = {
                  build = "system-prompts/cc-2.1.97.txt";
                  plan = "system-prompts/cc-plan.txt";
                  explore = "system-prompts/cc-explore.txt";
                  general = "system-prompts/cc-general.txt";
                  title = "system-prompts/cc-title.txt";
                  summary = "system-prompts/cc-summary.txt";
                };

                # Match real CC's request shape
                maxTokens = 64000;
                injectThinking = true;
                injectContextManagement = true;
                stripToolChoiceAuto = true;
                accountUuid = "eb263d3b-dc7d-4d1d-858d-2b476d9128d7";

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

                # OpenCode-specific top-level fields the Anthropic API doesn't
                # define. Real Claude Code never sends these -- forwarding
                # them is a fingerprint signal.
                unknownFields = [
                  {
                    # output_config: { effort: ... } -- real CC sends this too.
                    name = "output_config";
                    action = "keep";
                  }
                  {
                    # context_management -- real CC sends this on opus/sonnet.
                    name = "context_management";
                    action = "keep";
                  }
                  {
                    # speed: "fast" | "default" -- OpenCode-only field. Strip.
                    name = "speed";
                    action = "strip";
                  }
                ];
              };
            };
          }

          self.homeModules.kanata
          self.homeModules.hyprkan
          self.homeModules.keylayers
          self.homeModules.freecad
          {
            programs.freecad.package = upkgs.freecad;

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

        # Inline lspmux settings (was ./services/lspmux.nix)
        services.lspmux.settings = {
          instance_timeout = 3600; # 1 hour
          pass_environment = [
            # Core identity / basic runtime
            "HOME"
            "PATH"

            # Rust / Cargo
            # (keep even if some aren't currently set; harmless)
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

            self.packages.${pkgs.stdenv.hostPlatform.system}.neovim.default
            self.packages.${pkgs.stdenv.hostPlatform.system}.opencode-bubblewrap

            pa-monitor
            self.packages.${pkgs.stdenv.hostPlatform.system}.pa-sweep

            #inputs.nelly.packages.${pkgs.stdenv.hostPlatform.system}.linear-cli
            spotify

            upkgs.opencode
            upkgs.prismlauncher

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

          stateVersion = "23.05";
        };

        fonts.fontconfig.enable = true;

        systemd.user.startServices = "sd-switch";
      };
    };
  };
}
