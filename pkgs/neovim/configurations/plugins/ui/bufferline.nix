{ lib, helpers, ... }: {
  plugins.bufferline = {
    enable = true;
    diagnostics = "nvim_lsp";
    truncateNames = true;
    offsets = [
      {
        filetype = "undotree";
        text = "Undotree";
        highlight = "PanelHeading";
        padding = 1;
      }
      {
        filetype = "neo-tree";
        text = "Explorer";
        highlight = "PanelHeading";
        padding = 1;
      }
      {
        filetype = "NvimTree";
        text = "Explorer";
        highlight = "PanelHeading";
        padding = 1;
      }
      {
        filetype = "DiffviewFiles";
        text = "Diff View";
        highlight = "PanelHeading";
        padding = 1;
      }
      {
        filetype = "flutterToolsOutline";
        text = "Flutter Outline";
        highlight = "PanelHeading";
      }
    ];
  };

  plugins.which-key.registrations = {
    "<leader>bp" = "BufferLine Pick";
    "<leader>bc" = "Buffer Delete";
    "<leader>bP" = "Buffer Pin";
    "<leader>bd" = "Buffer Sort by dir";
    "<leader>be" = "Buffer Sort by ext";
    "<leader>bt" = "Buffer Sort by Tabs";
    "<leader>bL" = "Buffer close all to right";
    "<leader>bH" = "Buffer close all to left";
  };

  keymaps = let
    normal = lib.mapAttrsToList (key: action: {
      mode = "n";
      inherit action key;
    }) {
      "<leader>bp" = ":BufferLinePick<CR>";
      "<leader>bc" = ":bp | bd #<CR>";
      "<leader>bP" = ":BufferLineTogglePin<CR>";
      "<leader>bd" = ":BufferLineSortByDirectory<CR>";
      "<leader>be" = ":BufferLineSortByExtension<CR>";
      "<leader>bt" = ":BufferLineSortByTabs<CR>";
      "<leader>bL" = ":BufferLineCloseRight<CR>";
      "<leader>bH" = ":BufferLineCloseLeft<CR>";
      "<leader><S-h>" = ":BufferLineMovePrev<CR>";
      "<leader><S-l>" = ":BufferLineMoveNext<CR>";

      "<Tab>" = ":BufferLineCycleNext<CR>";
      "<S-Tab>" = ":BufferLineCyclePrev<CR>";
    };
  in helpers.keymaps.mkKeymaps { options.silent = true; } normal;
}
