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

    #./plugins/ui/colorizer.nix
    ./plugins/ui/highlight-colors.nix

    #./plugins/ui/precognition.nix
    #./plugins/productivity/vim-ai.nix
    #./plugins/ui/vim-zoom.nix
    #./plugins/productivity/copilot.nix
    #./plugins/productivity/codecompanion.nix

    ## lsp
    ./plugins/ls/treesitter.nix

    ./plugins/ls/lsp.nix
    ./plugins/ls/none-ls.nix
    ./plugins/ls/cmp.nix

    ## Languages to enable. these add configurations to the above ls items.
    ./plugins/ls/languages/nix.nix
    ./plugins/ls/languages/python.nix
    ./plugins/ls/languages/typescript.nix

    # Theme
    ./themes/default.nix
  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}
