{
  plugins = {
    mini = {
      enable = true;
      mockDevIcons = true;
      modules.icons = {

      };
    };

    which-key = {
      enable = true;
      settings = {
        plugins = {
          registers = true;
          spelling = {
            enabled = true;
            suggestions = 20;
          };
          presets = {
            operators = true;
            motions = true;
            text_objects = true;
            windows = true;
            nav = true;
            z = true;
            g = true;
          };
        };

        replace = {
          "<space>" = "SPC";
          "<cr>" = "RET";
          "<tab>" = "TAB";
        };

        icons = {
          breadcrumb = "»";
          separator = "➜";
          group = "+";
        };

        keys = {
          scrollDown = "<c-d>";
          scrollUp = "<c-u>";
        };

        layout = {
          height = {
            min = 4;
            max = 25;
          };
          width = {
            min = 20;
            max = 50;
          };
          spacing = 3;
          align = "left";
        };

        win = {
          border = "single";
          # padding takes a list of [vertical horizontal] integers
          padding = [ 1 2 ];
          winblend = 0;
          title_pos = "bottom";
          footer_pos = "bottom";
        };

        # Replacing ignore_missing, which expected a boolean,
        # with filter. However, the new type is either null or a Lua
        # function string. Setting it to null turns off filtering.
        filter = null;

        show_help = true;
        show_keys = true;

        triggers = {
          __raw = "auto";
          blacklist = {
            i = [ "j" "k" ];
            v = [ "j" "k" ];
          };
        };

        # Instead of triggers_nowait, we now use a numerical delay.
        delay = 300;

        disable = {
          ft = [ ]; # filetypes
          bt = [ ]; # buftypes
        };
      };
    };
  };
}

#   plugins.which-key.settings.spec = [
#     {
#       __unkeyed-1 = "<leader>";
#       group = "+leader";
#       icon = "󰌗 ";
#       __unkeyed-2 = [
#         {
#           __unkeyed-1 = "c";
#           group = "+code";
#           icon = "󰞷 ";
#           __unkeyed-2 = [
#             {
#               __unkeyed-1 = "c";
#               __unkeyed-2 = "<cmd>CodeCompanionChat toggle<CR>";
#               desc = "Toggle CodeCompanionChat";
#             }
#             {
#               __unkeyed-1 = "o";
#               __unkeyed-2 = "<cmd>CodeCompanionChat copilot_o1<CR>";
#               desc = "Copilot Chat";
#             }
#           ];
#         }
#         {
#           __unkeyed-1 = "f";
#           __unkeyed-2 = "<cmd>lua vim.lsp.buf.format()<CR>";
#           desc = "Format buffer";
#         }
#         {
#           __unkeyed-1 = "w";
#           __unkeyed-2 = "<cmd>lua vim.lsp.buf.format()<CR><cmd>w<CR>";
#           desc = "Format and save";
#         }
#         {
#           __unkeyed-1 = "a";
#           __unkeyed-2 = "<cmd>lua vim.lsp.buf.code_action()<CR>";
#           desc = "Code action";
#         }
#         {
#           __unkeyed-1 = "h";
#           __unkeyed-2 = "<C-w>h";
#           desc = "Move to left window";
#         }
#         {
#           __unkeyed-1 = "l";
#           __unkeyed-2 = "<C-w>l";
#           desc = "Move to right window";
#         }
#       ];
#     }
#     {
#       __unkeyed-1 = "<C-Up>";
#       __unkeyed-2 = "<cmd>resize -2<CR>";
#       desc = "Resize window up";
#     }
#     {
#       __unkeyed-1 = "<C-Down>";
#       __unkeyed-2 = "<cmd>resize +2<CR>";
#       desc = "Resize window down";
#     }
#     {
#       __unkeyed-1 = "<C-Left>";
#       __unkeyed-2 = "<cmd>vertical resize +2<CR>";
#       desc = "Resize window left";
#     }
#     {
#       __unkeyed-1 = "<C-Right>";
#       __unkeyed-2 = "<cmd>vertical resize -2<CR>";
#       desc = "Resize window right";
#     }
#     {
#       __unkeyed-1 = "<M-k>";
#       __unkeyed-2 = "<cmd>move-2<CR>";
#       desc = "Move line up";
#     }
#     {
#       __unkeyed-1 = "<M-j>";
#       __unkeyed-2 = "<cmd>move+<CR>";
#       desc = "Move line down";
#     }
#     {
#       __unkeyed-1 = "<S-Up>";
#       __unkeyed-2 = "<cmd>execute \"normal! \" . v:count1 * 5 . \"k\"<CR>";
#       desc = "Scroll up 5 lines";
#     }
#     {
#       __unkeyed-1 = "<S-Down>";
#       __unkeyed-2 = "<cmd>execute \"normal! \" . v:count1 * 5 . \"j\"<CR>";
#       desc = "Scroll down 5 lines";
#     }
#     {
#       __unkeyed-1 = "<C-c>";
#       __unkeyed-2 = "<cmd>b#<CR>";
#       desc = "Switch to last buffer";
#     }
#     {
#       __unkeyed-1 = "<C-x>";
#       __unkeyed-2 = "<cmd>close<CR>";
#       desc = "Close window";
#     }
#     {
#       __unkeyed-1 = "<C-e>";
#       __unkeyed-2 = "<End>";
#     }
#     {
#       __unkeyed-1 = "<C-a>";
#       __unkeyed-2 = "<Home>";
#     }
#     {
#       __unkeyed-1 = "L";
#       __unkeyed-2 = "$";
#     }
#     {
#       __unkeyed-1 = "H";
#       __unkeyed-2 = "^";
#     }
#     {
#       __unkeyed-1 = ",";
#       __unkeyed-2 = "@@";
#     }
#     {
#       __unkeyed-1 = "Y";
#       __unkeyed-2 = "y$";
#     }
#     {
#       __unkeyed-1 = "<esc>";
#       __unkeyed-2 = "<cmd>noh<CR>";
#     }
#   ];
