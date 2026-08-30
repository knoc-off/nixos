{
  imports = [
    ./settings/options.nix
    ./settings/keymappings.nix

    ./modules/foldtext.nix
    ./modules/ui.nix
    ./modules/treesitter.nix
    ./modules/markdown.nix
    ./modules/bufferline.nix
    ./modules/statusline.nix
    ./modules/scope.nix
    ./modules/textobjects.nix
    ./modules/mini-pick.nix
    ./modules/pick-scope.nix
    ./modules/mini-visits.nix
    ./modules/completion.nix
    ./modules/mini-files.nix
    ./modules/which-key.nix
    ./modules/which-key-groups.nix
    ./modules/tiny-code-action.nix
    ./modules/trouble.nix
    ./modules/flash.nix
    ./modules/grug-far.nix
    ./modules/ast-grep.nix

    ./modules/git-state.nix
    ./modules/git.nix
    ./modules/diffview.nix
    ./modules/sessions.nix
    ./modules/dap.nix

    ./modules/languages/default.nix
    ./modules/languages/formatters.nix
    ./modules/languages/lint.nix
    ./modules/languages/data.nix
    ./modules/languages/spell.nix
    ./modules/languages/c.nix
    ./modules/languages/rust.nix
    ./modules/languages/nix.nix
    ./modules/languages/typescript.nix
    ./modules/languages/lua.nix
    # ./modules/languages/github-actions.nix

    ./themes

    ./modules/precognition.nix
    ./modules/prompt-reference.nix

    # Custom plugins
    ../plugins/smart-paste/module.nix
    {
      plugins.smart-paste.enable = true;
    }

    ../plugins/rhizome/module.nix
    {
      plugins.rhizome = {
        enable = true;
        url = "https://notes.niko.ink";
        # The token is read from this variable at startup. How it gets into the
        # environment is deliberately not nixvim's concern -- on NixOS hosts a
        # sops secret under `shell_environment/` is exported automatically (see
        # modules/shell.nix).
        tokenEnv = "RHIZOME_TOKEN";
      };
    }
  ];

  viAlias = true;
  vimAlias = true;
  luaLoader.enable = true;
}
