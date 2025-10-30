{
  inputs,
  self,
  pkgs,
  user,
  system,
  color-lib,
  theme,
  config,
  ...
} @ args: let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.8;
  saturate = setOkhslSaturation 0.9;

  sa = hex: lighten (saturate hex);
in {
  imports = [
    (self.darwinModules.home args)
    inputs.sops-nix.darwinModules.sops
    # resistance is futile. zsh it is for now.
    # ./modules/shell/fish.nix
    # {
    #   programs.fish.enable = true;
    # }
    {
      nixpkgs.config.allowUnfree = true; # TODO swap out for my nix-module.
      users.users.${user}.shell = pkgs.zsh;
      environment.variables = {
        EDITOR = "vi";
        VISUAL = "vi";
        ANTHROPIC_API_KEY = "$(cat ${config.sops.secrets.ANTHROPIC_API_KEY.path})";
      };
      programs.zsh = {
        #erableFzfCompletion = true;
        enableFzfHistory = true;
        enableCompletion = true;
        enableSyntaxHighlighting = true;
        #enableAutosuggestions = true;
        interactiveShellInit = ''
          cl() {
              printf '\x1b]1337;SetUserVar=in_claude=MQ==\007'
              command claude "$@"
              local exit_code=$?
              printf '\x1b]1337;SetUserVar=in_claude\007'
              return $exit_code
          }
        '';
      };
    }

    {
      # borked
      services.yabai = {
        enable = false;
        config = {
          focus_follows_mouse = "autoraise";
          mouse_follows_focus = "off";
          window_placement = "second_child";
          window_opacity = "off";
          top_padding = 36;
          bottom_padding = 10;
          left_padding = 10;
          right_padding = 10;
          window_gap = 10;
        };
      };
    }
  ];

  system.primaryUser = user;

  users.users.${user} = {
    home = "/Users/${user}";
  };

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;

  nix.extraOptions = ''
    auto-optimise-store = true
    experimental-features = nix-command flakes
    extra-platforms = x86_64-darwin aarch64-darwin
  '';

  nixpkgs.config.allowUnsupportedSystem = true;

  environment.systemPackages = with pkgs; [
    self.packages.${system}.neovim-nix.default

    taskwarrior3

    pkgs.nerd-fonts.fira-code
    ripgrep
    fd
    fzf
    jq
    gh # required by octo.nvim
    shellcheck # Dont need this?

    # secrets management
    sops
    age

    # company tools
    wireguard-tools
    awscli2

    postgresql

    docker
    docker-compose

    rustup
    cargo-nextest

    # Add these to my nix-vim.
    # # Lua LSP
    # lua-language-server
    # # Nix LSP
    # nil
    # # Terraform LSP
    # terraform-ls
    # # jsonnet LSP from grafana
    # jsonnet-language-server

    # # node-related for LSP
    # # for vscode-eslint-language-server, vscode-json-language-server
    # vscode-langservers-extracted
    # nodePackages_latest.typescript-language-server # typescript-language-server
    # typescript # tsserver is actually here?
    # svelte-language-server
    # emmet-language-server
  ];
  programs.direnv.enable = true;

  programs.direnv.nix-direnv.enable = true;

  homebrew = {
    enable = true;
    taps = [
      "dimentium/autoraise"
    ];
    casks = [
      {
        name = "middleclick";
        args = {
          no_quarantine = true;
        };
      }

      "obs"

      "claude-code"
      "utm"
      "crystalfetch"

      "rectangle"
      "spotify"
      # "alt-tab"
      "tableplus"
      "raycast"
      "slack"
      # "fly"
      "zen"
    ];
    brews = [
      "mingw-w64" # For rust cross compilation to windows.
      "colima" # For docker
      "openssl"

      {
        # focus follows mouse
        name = "autoraise";
        args = [
          "--with-dexperimental_focus_first"
          "--with-dold_activation_method"
        ];
        start_service = false;
      }
    ];
    onActivation.cleanup = "uninstall";
  };

  system.defaults = {
    dock = {
      autohide = true;
      show-recents = false;
      mru-spaces = false;
      orientation = "bottom";
    };
    finder.AppleShowAllExtensions = true;

    dock.autohide-time-modifier = 0.1;
    dock.expose-animation-duration = 0.1;
  };
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };
  security.pam.services.sudo_local.touchIdAuth = true;

  # Custom autoraise service with delay 0 to prevent raising
  launchd.user.agents.autoraise = {
    command = "/opt/homebrew/bin/autoraise -delay 0";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
    };
  };

  # Sops configuration
  sops = {
    defaultSopsFile = ./secrets/Nicholass-MacBook-Pro/default.yaml;
    age.sshKeyPaths = ["/Users/${user}/.ssh/id_ed25519"];
    secrets."ANTHROPIC_API_KEY" = {
      mode = "0644";
    };
  };
}
