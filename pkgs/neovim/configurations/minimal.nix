{
  imports = [
    ./settings/options.nix
    ./settings/keymappings.nix

    ./modules/core.nix
    ./modules/bufferline.nix
    ./modules/focus.nix
    ./modules/scope.nix
    ./modules/telescope.nix

    # Languages (explicit opt-in)
    ./modules/languages/default.nix # shared LSP base
    ./modules/languages/rust.nix
    ./modules/languages/nix.nix

    ./themes
  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}
