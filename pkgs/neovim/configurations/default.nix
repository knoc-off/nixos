{
  imports = [
    # settings
    ./settings/highlights.nix
    ./settings/options.nix
    ./settings/autocommands.nix
    ./settings/keymappings.nix

    # Plugins
    ./plugins/completions.nix
    ./plugins/productivity/telescope.nix
    ./plugins/ui/bufferline.nix
    # custom plugin allowing (messy) integration with hyprland.
    ./plugins/misc/window-manager.nix
    ./plugins/ui/colorizer.nix


    #./plugins/ui/precognition.nix
    #./plugins/productivity/vim-ai.nix
    #./plugins/ui/vim-zoom.nix
    #./plugins/productivity/copilot.nix
    #./plugins/productivity/codecompanion.nix

    ## lsp
    ./plugins/ls/treesitter.nix

    ./plugins/ls/lsp.nix
    ./plugins/ls/cmp.nix

    ./plugins/ls/languages/nix.nix
    ./plugins/ls/languages/python.nix

    # Theme
    ./themes
  ];


  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}
