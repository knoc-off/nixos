# opencode.nvim - thin integration with the opencode AI agent
# Manages an opencode server in a terminal split with context injection
# (@this, @buffer, @diagnostics, @diff). Auto-reloads buffers on edit.
# Config via vim.g.opencode_opts (no setup() call needed).
{
  lib,
  pkgs,
  ...
}: {
  # snacks.nvim provides terminal/window/input backend for opencode.nvim
  plugins.snacks = {
    enable = true;
    settings = {
      terminal.enabled = true;
      input.enabled = true;
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

  keymaps = [
    {
      mode = "n";
      key = "<leader>oo";
      action = lib.nixvim.mkRaw "function() require('opencode').toggle() end";
      options = { silent = true; desc = "Toggle opencode"; };
    }
    {
      mode = ["n" "v"];
      key = "<leader>oa";
      action = lib.nixvim.mkRaw "function() require('opencode').ask() end";
      options = { silent = true; desc = "Ask opencode"; };
    }
    {
      mode = ["n" "v"];
      key = "<leader>oe";
      action = lib.nixvim.mkRaw "function() require('opencode').prompt('Edit @this') end";
      options = { silent = true; desc = "Edit selection with opencode"; };
    }
    {
      mode = "n";
      key = "<leader>of";
      action = lib.nixvim.mkRaw "function() require('opencode').prompt('fix') end";
      options = { silent = true; desc = "Fix diagnostics"; };
    }
    {
      mode = "n";
      key = "<leader>on";
      action = lib.nixvim.mkRaw "function() require('opencode').command('session.new') end";
      options = { silent = true; desc = "New opencode session"; };
    }
    {
      mode = "n";
      key = "<leader>os";
      action = lib.nixvim.mkRaw "function() require('opencode').select() end";
      options = { silent = true; desc = "OpenCode command palette"; };
    }
  ];
}
