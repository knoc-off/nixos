{
  imports = [
    ./settings/options.nix
    ./settings/keymappings.nix

    ./modules/ui.nix
    ./modules/treesitter.nix
    ./modules/bufferline.nix
    ./modules/statusline.nix
    ./modules/scope.nix
    ./modules/textobjects.nix
    ./modules/telescope.nix
    ./modules/completion.nix
    ./modules/mini-files.nix
    ./modules/which-key.nix

    ./modules/git-state.nix
    ./modules/git.nix
    ./modules/sessions.nix

    ./modules/languages/default.nix
    ./modules/languages/formatters.nix
    ./modules/languages/c.nix
    ./modules/languages/rust.nix
    ./modules/languages/nix.nix
    ./modules/languages/typescript.nix
    # ./modules/languages/github-actions.nix

    ./modules/opencode.nix

    ./themes

    # Custom plugins
    ../plugins/smart-paste/module.nix
    {
      plugins.smart-paste.enable = true;
    }
  ];

  viAlias = true;
  vimAlias = true;
  luaLoader.enable = true;
}
