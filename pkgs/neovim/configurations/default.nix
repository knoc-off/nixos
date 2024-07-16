{
  imports = [
    # settings
    ./settings/highlights.nix
    ./settings/options.nix
    ./settings/autocommands.nix
    ./settings/keymappings.nix

    # Plugins
    ./plugins/compleations.nix
    ./plugins/productivity/telescope.nix
    ./plugins/ui/bufferline.nix
    ./plugins/ui/which-key.nix
    ## lsp
    ./plugins/ls

    # Theme
    ./themes
  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}
