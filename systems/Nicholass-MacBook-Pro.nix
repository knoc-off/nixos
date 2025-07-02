{
  inputs,
  self,
  pkgs,
  ...
}: {
  system.primaryUser = "niko";
  users.users.niko = {
    home = "/Users/niko";
  };

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;

  # nix.extraOptions = ''
  #   auto-optimise-store = true
  #   experimental-features = nix-command flakes
  #   extra-platforms = x86_64-darwin aarch64-darwin
  # '';

  # packages.aarch64-darwin.neovim-nix.default
  environment.systemPackages = with pkgs; [
    (self.packages.aarch64-darwin.neovim-nix.default)
    ripgrep
    fd
    fzf
    jq
    gh # required by octo.nvim
    shellcheck

    # company tools
    wireguard-tools
    awscli2

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

  environment.variables = {
    EDITOR = "nvim";
  };

  homebrew = {
    enable = true;
    casks = [
      {
        name = "middleclick";
        args = {no_quarantine = true;};
      }
      "rectangle"
      "alt-tab"
      "tableplus"
      "raycast"
      "slack" # previously directly downloaded from website, check for conflicts
      "fly" # Because we need to have r/w for the binary since it needs to match the version in our concourse instance
    ];
    brews = [
      "mingw-w64" # For rust cross compilation to windows...
      # "nsis" # Broken on darwin nixpkgs :(
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
}
