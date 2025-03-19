{ lib, helpers, ... }: {
  plugins.bufferline = {
    enable = true;
    settings.options = {
      truncateNames = true;
      diagnostics = "nvim_lsp";
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
