{
  inputs,
  self,
  pkgs,
  user,
  system,
  theme,
  color-lib,
  lib,
  config,
  ...
} @ args: let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.8;
  saturate = setOkhslSaturation 0.9;

  sa = hex: lighten (saturate hex);
in {
  imports = [
    (self.nixosModules.home {inherit args;})
    inputs.sops-nix.darwinModules.sops
    # need to use lib.mkIf pkgs.stdenv.isLinux / isDarwin to conditionally add logic.
    # ./modules/shell/fish.nix
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

        '';
      };
    }
  ];

  system.primaryUser = user;
  users.users."${user}" = {
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
  # lib.mkIf pkgs.stdenv.isLinux

  # packages.aarch64-darwin.neovim-nix.default
  environment.systemPackages = with pkgs; [
    (self.packages.${system}.neovim-nix.default)

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

    # Programming deps/LSPs/etc
    ## for Rust
    rustup # accidentally installed from the script, but should use the nix one instead...
    # cargo etc, installed via rustup directly for now
    cargo-nextest # trying it out, useful for running tests quickly

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

  homebrew = {
    enable = true;
    casks = [
      {
        name = "middleclick";
        args = {no_quarantine = true;};
      }
      "claude-code"
      "utm"
      "crystalfetch"

      "rectangle"
      "spotify"
      "alt-tab"
      "tableplus"
      "raycast"
      "slack" # previously directly downloaded from website, check for conflicts
      "fly" # Because we need to have r/w for the binary since it needs to match the version in our concourse instance
    ];
    brews = [
      "mingw-w64" # For rust cross compilation to windows...
      "colima" # For docker
      "openssl"
      #"nsis" # Broken on darwin nixpkgs :(
      # "llvm" # Kept just in case, was used for trying experimental tauri cross compilation to windows (also nsis above)
      # "tunneltodev/tap/tunnelto" # ngrok-like, broken on nixpkgs at the moment
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
  };
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };
  security.pam.services.sudo_local.touchIdAuth = true;

  # Sops configuration
  sops = {
    defaultSopsFile = ./secrets/Nicholass-MacBook-Pro/default.yaml;
    age.sshKeyPaths = ["/Users/${user}/.ssh/id_ed25519"];
    secrets."ANTHROPIC_API_KEY" = {mode = "0644";};
  };
}
