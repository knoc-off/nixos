{ pkgs, config, lib, ... }: {
  programs.nixvim = {
    extraPlugins = with pkgs.vimPlugins; [
      plenary-nvim
      nui-nvim
      nvim-surround

      (pkgs.vimUtils.buildVimPlugin rec {
        pname = "transparent";
        version = "f09966923f7e329ceda9d90fe0b7e8042b6bdf31";
        src = pkgs.fetchFromGitHub {
          owner = "xiyaowong";
          repo = "transparent.nvim";
          rev = version;
          sha256 = "sha256-Z4Icv7c/fK55plk0y/lEsoWDhLc8VixjQyyO6WdTOVw=";
        };
      })

      (pkgs.vimUtils.buildVimPlugin rec {
        pname = "CodeGpt";
        version = "96ec57766c6d2133d1b921daffca651c3c7a3541";
        src = pkgs.fetchFromGitHub {
          owner = "dpayne";
          repo = "CodeGPT.nvim";
          rev = version;
          sha256 = "sha256-stsXKajTDvlFzjDzbssLWulFrAMFQO7FLCZZAg7x4Dg=";
        };
      })

      (pkgs.vimUtils.buildVimPlugin rec {
        pname = "ChatGPT";
        version = "467954fbbdb3188e7e1f021a18b746df3fd611bc";
        src = pkgs.fetchFromGitHub {
          owner = "jackMort";
          repo = "ChatGPT.nvim";
          rev = version;
          sha256 = "sha256-Vma6BxT++NrrHrr+d+YIJZMhAQk3zoAG8KI8r3UYUcs=";
        };
      })

      (pkgs.vimUtils.buildVimPlugin rec {
        pname = "darkplus";
        version = "1826879d9cb14e5d93cd142d19f02b23840408a6";
        src = pkgs.fetchFromGitHub {
          owner = "LunarVim";
          repo = "darkplus.nvim";
          rev = version;
          sha256 = "sha256-/e7PCA931t5j0dlvfZm04dQ7dvcCL/ek+BIe1zQj5p4=";
        };
      })
    ];
    # ++ (with pkgs.vimExtraPlugins; [ nvim-transparent ]);

    extraConfigLuaPre = ''
      require("transparent").setup({
        groups = { -- table: default groups
          'Normal', 'NormalNC', 'Comment', 'Constant', 'Special', 'Identifier',
          'Statement', 'PreProc', 'Type', 'Underlined', 'Todo', 'String', 'Function',
          'Conditional', 'Repeat', 'Operator', 'Structure', 'LineNr', 'NonText',
          'SignColumn', 'CursorLineNr', 'EndOfBuffer',
        },
        extra_groups = {}, -- table: additional groups that should be cleared
        exclude_groups = {}, -- table: groups you don't want to clear
      })

      require('nvim-surround').setup({
        keymaps = {
          insert = "<C-g>s",
          insert_line = "<C-g>S",
          normal = "ys",
          normal_cur = "yss",
          normal_line = "yS",
          normal_cur_line = "ySS",
          visual = "\"",
          visual_line = "gS",
          delete = "ds",
          change = "cs",
        },
      })
    '';

  };
}
