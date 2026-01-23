{
  inputs,
  self,
  pkgs,
  upkgs,
  lib,
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
    {
      nixpkgs.config.allowUnfree = true;
      users.users.${user}.shell = pkgs.zsh;
      environment.variables = {
        EDITOR = "vi";
        VISUAL = "vi";
        ANTHROPIC_API_KEY = "$(cat ${config.sops.secrets.ANTHROPIC_API_KEY.path})";
      };
      programs.zsh = {
        enableFzfHistory = true;
        enableCompletion = true;
        enableSyntaxHighlighting = true;
        interactiveShellInit = ''
          export PATH="$(realpath ~/.cargo/bin):$PATH"

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

    {
      system.keyboard.userKeyMapping = [
        {
          HIDKeyboardModifierMappingSrc = lib.fromHexString "0x700000064";
          HIDKeyboardModifierMappingDst = lib.fromHexString "0x700000035";
        }
      ];
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
    (pkgs.claude-code.overrideAttrs (oldAttrs: rec {
      version = "2.1.7";
      src = pkgs.fetchzip {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-s/XPemwJYPUNFBgWo00VQ6W6eFIy44y9lFoRN0Duk9I=";
      };
    }))

    self.packages.${system}.neovim-nix.default

    taskwarrior3

    pkgs.nerd-fonts.fira-code
    ripgrep
    fd
    fzf
    jq
    gh
    shellcheck

    sops
    age
    cmake

    wireguard-tools
    awscli2

    postgresql

    docker
    docker-compose

    rustup
    cargo-nextest
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

      "utm"
      "crystalfetch"

      "ghostty"

      "rectangle"
      "spotify"
      "tableplus"
      "raycast"
      "slack"
      "zen"
    ];
    brews = [
      "mingw-w64" # For rust cross compilation to windows.
      "colima" # For docker
      "openssl"
      "cliclick"

      "SergioBenitez/osxct/x86_64-unknown-linux-gnu"

      {
        name = "autoraise";
        args = [
          "--with-dexperimental_focus_first"
          "--with-dold_activation_method"
        ];
        start_service = false;
        restart_service = false;
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

    # nonUS.remapTilde = true;
  };
  security.pam.services.sudo_local.touchIdAuth = true;

  # Custom autoraise service with delay 0 to prevent raising
  launchd.user.agents.autoraise = {
    command = "/opt/homebrew/bin/autoraise -delay 0";
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      Label = "org.nixos.autoraise";
    };
  };

  sops = {
    defaultSopsFile = ./secrets/Nicholass-MacBook-Pro/default.yaml;
    age.sshKeyPaths = ["/Users/${user}/.ssh/id_ed25519"];
    secrets."ANTHROPIC_API_KEY" = {
      mode = "0644";
    };
  };
}
