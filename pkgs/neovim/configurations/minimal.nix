{
  imports = [
    ./settings/options.nix
    ./settings/keymappings.nix

    ./modules/treesitter.nix
    ./modules/bufferline.nix
    ./modules/focus.nix
    ./modules/scope.nix
    ./modules/textobjects.nix
    ./modules/telescope.nix
    ./modules/completion.nix
    ./modules/mini-files.nix
    # ./modules/dashboard.nix # disabled: snacks dashboard requires lazy.nvim

    ./modules/trainingwheels.nix
    ./modules/git.nix
    ./modules/sessions.nix

    ./modules/languages/default.nix # shared LSP base
    ./modules/languages/formatters.nix # biome + prettier
    ./modules/languages/rust.nix
    ./modules/languages/nix.nix
    ./modules/languages/typescript.nix
    ./modules/languages/github-actions.nix

    ./themes

    # Custom plugins
    ../plugins/smart-paste/module.nix
    {
      # Smart paste: auto-indent pasted code
      plugins.smart-paste = {
        enable = true;
      };
    }
  ];

  viAlias = true;
  vimAlias = true;

  # plugin manager, that loads plugin with lua code
  luaLoader.enable = true;
}
