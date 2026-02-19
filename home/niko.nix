{
  pkgs,
  upkgs,
  self,
  theme,
  config,
  color-lib,
  lib,
  ...
}: {
  # test
  imports = [
    {programs.ghostty.package = lib.mkForce null;}
    ./programs/terminal/ghostty
    # ./programs/terminal/kitty
    ./programs/terminal
    ./programs/browser/firefox/default.nix

    self.homeModules.git
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
        ];
        # Allowlist alternative — only pass vars that matter for language servers:
        # pass_environment = ["PATH" "HOME" "RUST_SRC_PATH" "CARGO_HOME" "RUSTUP_HOME"];
      };
    }
    self.homeModules.starship

    ./programs/terminal/shell
    {
      targets.darwin.defaults."com.apple.finder".ShowPathBar = true; # ? what does this do?

      home.packages = with pkgs; [
        gum

        skim

        watchexec

        upkgs.tsx
      ];
      programs.zsh = {
        enable = true;
        initContent = ''
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^[[101;9u' edit-command-line

          export SQLX_OFFLINE=true
        '';
        shellAliases = {
          g = "git";
          nxrb = "sudo darwin-rebuild switch --flake /Users/niko/projects/nixos/";
        };
      };
      programs.bash.enable = true;
    }

    ./programs/terminal/programs/opencode.nix
    ./programs/filemanager/yazi.nix
  ];

  home.stateVersion = "25.05";
}
