{
  self,
  pkgs,
  upkgs,
  user,
  lib,
  ...
}: {
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

    self.homeModules.niri
    self.homeModules.noctalia
    self.homeModules.stylix

    self.homeModules.lspmux
    {
      services.lspmux.settings = {
        # lots of llm generated stuff. but overall im fairly confident that its correct.
        pass_environment = [
          "*"

          # prompt / shell bookkeeping
          "!STARSHIP_*"
          "!SHLVL"
          "!_"
          "!OLDPWD"
          "!PWD"
          "!SHELLOPTS"
          "!BASHOPTS"
          "!FISH_VERSION"
          "!__fish_*"
          "!__HM_*"
          "!__NIXOS_*"
          "!__ETC_PROFILE_DONE"
          "!IN_NIX_SHELL"

          # direnv (extremely volatile)
          "!DIRENV_*"

          # editor / runtime bookkeeping (often irrelevant + noisy)
          "!NVIM"
          "!NVIM_LOG_FILE"
          "!NVIM_SYSTEM_RPLUGIN_MANIFEST"
          "!VIM"
          "!VIMRUNTIME"
          "!EMACS*"

          # terminal emulator noise
          "!TERM_PROGRAM"
          "!TERM_PROGRAM_VERSION"
          "!COLORTERM"
          "!GHOSTTY_*"
          "!ALACRITTY_*"
          "!KITTY_*"
          "!WEZTERM_*"
          "!RIO_*"
          "!FOOT_*"
          "!KONSOLE_*"

          # session / IPC / sockets / per-login identifiers
          "!DBUS_SESSION_BUS_ADDRESS"
          "!SSH_AUTH_SOCK"
          "!WAYLAND_DISPLAY"
          "!DISPLAY"
          "!XAUTHORITY"
          "!NIRI_SOCKET"

          "!XDG_SESSION_ID"
          "!XDG_SESSION_TYPE"
          "!XDG_SESSION_CLASS"
          "!XDG_SESSION_DESKTOP"
          "!XDG_CURRENT_DESKTOP"
          "!XDG_SEAT"
          "!XDG_VTNR"
          "!XDG_RUNTIME_DIR"

          "!MANAGERPID"
          "!MANAGERPIDFDID"
          "!SYSTEMD_EXEC_PID"
          "!INVOCATION_ID"
          "!JOURNAL_STREAM"

          "!MEMORY_PRESSURE_WATCH"
          "!MEMORY_PRESSURE_WRITE"

          # desktop/launcher/window-manager stuff
          "!WINDOWID"
          "!DESKTOP_STARTUP_ID"
          "!GDK_BACKEND"
          "!QT_QPA_PLATFORM"
          "!QT_QPA_PLATFORMTHEME"
          "!QT_SCALE_FACTOR"
          "!GDK_SCALE"
          "!GDK_DPI_SCALE"

          # macOS-ish vars
          "!LaunchInstanceID"
          "!SECURITYSESSIONID"
          "!XPC_SERVICE_NAME"
          "!XPC_FLAGS"
          "!__CFBundleIdentifier"
          "!OSLogRateLimit"

          # macOS / Apple session + launchd noise
          "!__CFBundleIdentifier"
          "!__CF_USER_TEXT_ENCODING"
          "!__CFPREFERENCES_AVOID_DAEMON"
          "!__OSINSTALL_ENVIRONMENT"
          "!Apple_PubSub_Socket_Render"
          "!SECURITYSESSIONID"
          "!LaunchInstanceID"
          "!XPC_SERVICE_NAME"
          "!XPC_FLAGS"
          "!OSLogRateLimit"
          "!OSLogRateLimitBurst"
          "!MallocNanoZone"
          "!DYLD_SHARED_REGION"
          "!DYLD_SHARED_CACHE_DIR"

          # macOS terminal / GUI app launch context
          "!TERM_PROGRAM"
          "!TERM_PROGRAM_VERSION"
          "!TERM_SESSION_ID"
          "!ITERM_PROFILE"
          "!ITERM_SESSION_ID"
          "!LC_TERMINAL"
          "!LC_TERMINAL_VERSION"

          # macOS keychain / ssh-agent-ish (varies by session)
          "!SSH_ASKPASS"
          "!SSH_AUTH_SOCK" # already on your list, but keep it here for macOS too

          # common Apple toolchain-selection noise (only exclude if you don't need Xcode toolchain selection)
          "!DEVELOPER_DIR"
          "!SDKROOT"

          # Apple per-process runtime noise (rare but shows up)
          "!COMMAND_MODE"
          "!ARGV0"

          # temp / ephemeral
          "!TMPDIR"
          "!TEMP"
          "!TMP"

          # secrets / tokens (don’t let these trigger reloads)
          "!*_API_KEY"
          "!*TOKEN*"
          "!*SECRET*"
          "!*PASSWORD*"

          # locale + pager + terminal capability noise
          "!LANG"
          "!LC_*"
          "!PAGER"
          "!MANPATH"
          "!INFOPATH"
          "!PATH_LOCALE"
          "!TERM"
          "!TERMINAL"
          "!TERMINFO"
          "!TERMINFO_DIRS"

          # user identity / prefs
          "!USER"
          "!LOGNAME"
          "!EDITOR"
          "!VISUAL"
          "!BROWSER"
          "!RIPGREP_CONFIG_PATH"

          # ambient language runtime paths
          "!PYTHONPATH"
          "!PYTHONNOUSERSITE"
          "!PYTHONHASHSEED"
          "!LUA_PATH"
          "!LUA_CPATH"
          "!NODE_PATH"
          "!GEM_HOME"

          # deterministic-build knobs + parallelism
          "!SOURCE_DATE_EPOCH"
          "!DETERMINISTIC_BUILD"
          "!ZERO_AR_DATE"
          "!NIX_BUILD_CORES"

          # nix structured/env bookkeeping that churns
          "!__structuredAttrs"
          "!__impureHostDeps"
          "!__propagatedImpureHostDeps"
          "!__sandboxProfile"
          "!__darwinAllowLocalNetworking"
          "!__NIX_DARWIN_SET_ENVIRONMENT_DONE"

          # AR AS CC CMAKE_INCLUDE_PATH CMAKE_LIBRARY_PATH CONFIG_SHELL CUPS_DATADIR CXX GDK_PIXBUF_MODULE_FILE GIO_EXTRA_MODULES GI_TYPELIB_PATH GTK2_RC_FILES GTK_A11Y GTK_PATH HOME HOST_PATH LD LD_LIBRARY_PATH LESSKEYIN_SYSTEM LIBCLANG_PATH LIBEXEC_PATH LOCALE_ARCHIVE LOCALE_ARCHIVE_2_27 MARONNE NIXPKGS_CMAKE_PREFIX_PATH NIXPKGS_CONFIG NIX_BINTOOLS NIX_BINTOOLS_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu NIX_CC NIX_CC_WRAPPER_TARGET_HOST_x86_64_unknown_linux_gnu NIX_CFLAGS_COMPILE NIX_ENFORCE_NO_NATIVE NIX_HARDENING_ENABLE NIX_LD NIX_LDFLAGS NIX_LD_LIBRARY_PATH NIX_PATH NIX_PKG_CONFIG_WRAPPER_TARGET_TARGET_x86_64_unknown_linux_gnu NIX_PROFILES NIX_STORE NIX_USER_PROFILE_DIR NIX_XDG_DESKTOP_PORTAL_DIR NM NO_AT_BRIDGE OBJCOPY OBJDUMP PATH PKG_CONFIG_FOR_TARGET PKG_CONFIG_PATH_FOR_TARGET QML2_IMPORT_PATH QTWEBKIT_PLUGIN_PATH QT_PLUGIN_PATH QT_STYLE_OVERRIDE RANLIB READELF RUSTFLAGS RUSTUP_TOOLCHAIN SHELL SIZE STRINGS STRIP TZDIR UID XCURSOR_PATH XCURSOR_SIZE XCURSOR_THEME XDG_BIN_HOME XDG_CACHE_HOME XDG_CONFIG_DIRS XDG_CONFIG_HOME XDG_DATA_DIRS XDG_DATA_HOME _PYTHON_HOST_PLATFORM _PYTHON_SYSCONFIGDATA_NAME buildInputs buildPhase builder cmakeFlags configureFlags depsBuildBuild depsBuildBuildPropagated depsBuildTarget depsBuildTargetPropagated depsHostHost depsHostHostPropagated depsTargetTarget depsTargetTargetPropagated doCheck doInstallCheck dontAddDisableDepTrack mesonFlags name nativeBuildInputs out outputs patches phases preferLocalBuild propagatedBuildInputs propagatedNativeBuildInputs shell shellHook stdenv strictDeps system
        ];
        # Allowlist alternative — only pass vars that matter for language servers:
        # pass_environment = ["PATH" "HOME" "RUST_SRC_PATH" "CARGO_HOME" "RUSTUP_HOME"];
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

        rules = [
          {
            class = "com.mitchellh.ghostty";
            layer = "terminal";
          }
          {
            class = "foot";
            layer = "terminal";
          }

          {
            class = "*";
            title = "*";
            layer = "base";
          }
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

          config = let
            # These keys exit super, and send it as if it were control.
            passthroughSuperToCtrlMorph = ["a" "b" "c" "f" "i" "l" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];

            # dumb but eh..
            noctalia = cmd:
              lib.concatStringsSep " " (
                [
                  "noctalia-shell"
                  "ipc"
                  "call"
                ]
                ++ (lib.splitString " " cmd)
              );
          in ''
            (defalias

              launcher (cmd ${noctalia "launcher toggle"})
              dbl  (tap-dance-eager 250 (XX @launcher))

              ;; GUI: Caps = Meta + shortcuts layer
              cap-gui (multi rmet @dbl (layer-while-held shortcuts))

              ;; Terminal: Caps = just Meta
              cap-trm (multi rmet @dbl)

              ;; rofi (cmd ${pkgs.rofi}/bin/rofi -show drun)
              ;; example for a toggle bind. not super clean...
              ;; to-trm (layer-switch terminal)
              ;; to-gui (layer-switch base)
              ;; f12  (tap-dance 300 (@rofi @to-trm))
              ;; f12t (tap-dance 300 (@rofi @to-gui))

              ;; Shortcuts: release meta, send Ctrl+key Press meta again
              ${builtins.concatStringsSep "\n" (map (k: "sc${k} (multi (release-key rmet) C-${k})") passthroughSuperToCtrlMorph)}
            )

            (defsrc caps)
            (deflayer base     @cap-gui )
            (deflayer terminal @cap-trm )
            ;;
            ;; (defsrc caps f12)
            ;; (deflayer base     @cap-gui @f12)
            ;; (deflayer terminal @cap-trm @f12t)

            (deflayermap (shortcuts)
              ${builtins.concatStringsSep "  " (map (k: "${k} @sc${k}") passthroughSuperToCtrlMorph)}
            )
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
