# opencode.nvim - thin wrapper around the opencode TUI
# Opens opencode in a terminal split with context injection (@selection, @file,
# @cursor, @diagnostics). Auto-reloads buffers when opencode edits them.
# All AI logic lives in opencode -- neovim is just the UI surface.
{
  lib,
  pkgs,
  ...
}: {
  # snacks.nvim provides the terminal/window backend for opencode.nvim
  plugins.snacks = {
    enable = true;
    settings = {
      terminal.enabled = true;
    };
  };

  extraPlugins = [
    (pkgs.vimUtils.buildVimPlugin {
      pname = "opencode-nvim";
      version = "unstable-2026-03-31";
      src = pkgs.fetchFromGitHub {
        owner = "NickvanDyke";
        repo = "opencode.nvim";
        rev = "df533d6da724109bf08446392db860fdceddbd0c";
        hash = "sha256-Lm0/59MWndrpU6D4+Gdpgnel7B3Q6jR3z6cgSUF2XuQ=";
      };
      meta.description = "Neovim integration for the opencode AI assistant";
    })
  ];

  extraConfigLua = ''
    require('opencode').setup({
      auto_reload = true,
      auto_focus = false,
      command = "opencode",
      win = {
        position = "right",
        enter = false,
      },
    })
  '';

  keymaps = [
    {
      mode = "n";
      key = "<leader>oo";
      action = lib.nixvim.mkRaw "function() require('opencode').toggle() end";
      options = {
        silent = true;
        desc = "Toggle opencode";
      };
    }
    {
      mode = ["n" "v"];
      key = "<leader>oa";
      action = lib.nixvim.mkRaw "function() require('opencode').ask() end";
      options = {
        silent = true;
        desc = "Ask opencode";
      };
    }
    {
      mode = "v";
      key = "<leader>oe";
      action = lib.nixvim.mkRaw ''
        function()
          require('opencode').prompt('Edit @selection according to the following instructions: ')
        end
      '';
      options = {
        silent = true;
        desc = "Edit selection with opencode";
      };
    }
    {
      mode = "n";
      key = "<leader>of";
      action = lib.nixvim.mkRaw "function() require('opencode').prompt('Fix these @diagnostics') end";
      options = {
        silent = true;
        desc = "Fix diagnostics";
      };
    }
    {
      mode = "n";
      key = "<leader>on";
      action = lib.nixvim.mkRaw "function() require('opencode').command('/new') end";
      options = {
        silent = true;
        desc = "New opencode session";
      };
    }
  ];
}
