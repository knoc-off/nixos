{ self, inputs, ... }: {
  home =
    { pkgs, lib, ... }:
    let
      inherit (self.lib) color-lib theme;
      system = pkgs.stdenv.hostPlatform.system;
      upkgs = import inputs.nixpkgs-unstable {
        inherit (pkgs) system;
        config = pkgs.config;
      };

    in
    {
      # Native LLM runtime: routes requests through packages/llm instead of
      # the AI SDK, which is the code path the Claude-Code tool-name aliasing
      # patch (pkgs/opencode postPatch) actually runs on. Without this, that
      # patch sits dead and every request still goes out with opencode's own
      # lowercase tool names.
      home.sessionVariables.OPENCODE_EXPERIMENTAL_NATIVE_LLM = "1";

      programs.opencode =
        let
          inherit (color-lib) setOkhslLightness setOkhslSaturation;
          lighten = setOkhslLightness 0.7;
          saturate = setOkhslSaturation 0.9;

          sa = hex: lighten (saturate hex);
        in
        {
          enable = true;
          # Patched build (pkgs/opencode): opencode's own prompts no longer say
          # "opencode" anywhere a request body would carry them, so the
          # compat-proxy's Claude Code identity spoofing isn't undermined by
          # opencode's own system prompt admitting what it actually is.
          package = self.packages.${system}.opencode;
          themes.customtheme = {
            "$schema" = "https://opencode.ai/theme.json";
            defs = {
              base00 = "#${theme.dark.base00}";
              base00-1 = "#${color-lib.adjustOkhslLightness 0.03 theme.dark.base00}";
              base00-2 = "#${color-lib.adjustOkhslLightness 0.06 theme.dark.base00}";
              base00-3 = "#${color-lib.adjustOkhslLightness 0.09 theme.dark.base00}";
              base01 = "#${theme.dark.base01}";
              base02 = "#${theme.dark.base02}";
              base03 = "#${theme.dark.base03}";
              base04 = "#${theme.dark.base04}";
              base05 = "#${theme.dark.base05}";
              base06 = "#${theme.dark.base06}";
              base07 = "#${theme.dark.base07}";
              base08 = "#${sa theme.dark.base08}";
              diffremoved = "#${
                color-lib.mixColors (color-lib.setOkhslLightness 0.2 theme.dark.base08) theme.dark.base00 0.1
              }";
              #diffremoved = "#${color-lib.mixColors (color-lib.adjustOkhslLightness 0.03 theme.dark.base00) theme.dark.base08 0.3}";
              base09 = "#${sa theme.dark.base09}";
              base0A = "#${sa theme.dark.base0A}";
              base0B = "#${sa theme.dark.base0B}";
              #diffadded = "#${color-lib.mixColors (color-lib.adjustOkhslLightness 0.03 theme.dark.base00) theme.dark.base0B 0.3}";
              #diffadded = "#${color-lib.setOkhslLightness 0.2 theme.dark.base0B}";
              diffadded = "#${
                color-lib.mixColors (color-lib.setOkhslLightness 0.2 theme.dark.base0B) theme.dark.base00 0.1
              }";
              base0C = "#${sa theme.dark.base0C}";
              base0D = "#${sa theme.dark.base0D}";
              base0E = "#${sa theme.dark.base0E}";
              base0F = "#${theme.dark.base0F}";
            };
            theme = {
              primary = {
                dark = "base0D";
                light = "base0D";
              };
              secondary = {
                dark = "base0E";
                light = "base0E";
              };
              accent = {
                dark = "base0C";
                light = "base0C";
              };
              error = {
                dark = "base08";
                light = "base08";
              };
              warning = {
                dark = "base09";
                light = "base09";
              };
              success = {
                dark = "base0B";
                light = "base0B";
              };
              info = {
                dark = "base0D";
                light = "base0D";
              };

              text = {
                dark = "base06";
                light = "base00";
              };
              textMuted = {
                dark = "base05";
                light = "base03";
              };
              background = {
                dark = "base00";
                light = "base07";
              };
              backgroundPanel = {
                dark = "base00-1";
                light = "base06";
              };
              backgroundElement = {
                dark = "base00-2";
                light = "base05";
              };

              border = {
                dark = "base01";
                light = "base04";
              };
              borderActive = {
                dark = "base02";
                light = "base03";
              };
              borderSubtle = {
                dark = "base00-3";
                light = "base04";
              };

              diffAdded = {
                dark = "base0B";
                light = "base0B";
              };
              diffRemoved = {
                dark = "base08";
                light = "base08";
              };
              diffContext = {
                dark = "base07";
                light = "base03";
              };
              diffHunkHeader = {
                dark = "base0C"; # !!!
                light = "base03";
              };
              diffHighlightAdded = {
                dark = "base0B";
                light = "base0B";
              };
              diffHighlightRemoved = {
                dark = "base08";
                light = "base08";
              };
              diffAddedBg = {
                dark = "diffadded";
                light = "base06";
              };
              diffRemovedBg = {
                dark = "diffremoved";
                light = "base06";
              };
              diffContextBg = {
                dark = "base00-2";
                light = "base06";
              };
              diffLineNumber = {
                dark = "base02";
                light = "base05";
              };
              diffAddedLineNumberBg = {
                dark = "diffadded";
                light = "base06";
              };
              diffRemovedLineNumberBg = {
                dark = "diffremoved";
                light = "base06";
              };

              markdownText = {
                dark = "base05";
                light = "base00";
              };
              markdownHeading = {
                dark = "base0D";
                light = "base0D";
              };
              markdownLink = {
                dark = "base0E";
                light = "base0E";
              };
              markdownLinkText = {
                dark = "base0C";
                light = "base0C";
              };
              markdownCode = {
                dark = "base0B";
                light = "base0B";
              };
              markdownBlockQuote = {
                dark = "base04";
                light = "base03";
              };
              markdownEmph = {
                dark = "base09";
                light = "base09";
              };
              markdownStrong = {
                dark = "base0A";
                light = "base0A";
              };
              markdownHorizontalRule = {
                dark = "base0D";
                light = "base03";
              };
              markdownListItem = {
                dark = "base0D";
                light = "base0D";
              };
              markdownListEnumeration = {
                dark = "base0C";
                light = "base0C";
              };
              markdownImage = {
                dark = "base0E";
                light = "base0E";
              };
              markdownImageText = {
                dark = "base0C";
                light = "base0C";
              };
              markdownCodeBlock = {
                dark = "base05";
                light = "base00";
              };

              syntaxComment = {
                dark = "base0E"; # !!!
                light = "base03";
              };
              syntaxKeyword = {
                dark = "base0E";
                light = "base0E";
              };
              syntaxFunction = {
                dark = "base0D";
                light = "base0D";
              };
              syntaxVariable = {
                dark = "base0C";
                light = "base0C";
              };
              syntaxString = {
                dark = "base0B";
                light = "base0B";
              };
              syntaxNumber = {
                dark = "base0F";
                light = "base0F";
              };
              syntaxType = {
                dark = "base0C";
                light = "base0C";
              };
              syntaxOperator = {
                dark = "base0E";
                light = "base0E";
              };
              syntaxPunctuation = {
                dark = "base05";
                light = "base00";
              };
            };
          };
        };

      # opencode v1.14+ reads opencode.json, not config.json.
      # The HM module still writes config.json, so we bypass it.
      xdg.configFile."opencode/opencode.json".text = builtins.toJSON {

        "$schema" = "https://opencode.ai/config.json";
        autoupdate = false;
        provider = {
          anthropic = {
            options = {
              baseURL = "{env:OPENCODE_PROXY_URL}";
              apiKey = "not-needed";
            };
          };
        };
        # No agent.*.prompt overrides: packages/opencode/src/session/prompt/anthropic.txt
        # is patched at the source (pkgs/opencode) to be the real system
        # prompt, so build/plan/general/explore/title/summary/compaction all
        # fall through to opencode's own (now Claude-Code-branded) defaults
        # instead of needing a `{file:...}` override here.

        permission = {
          edit = "ask";
          bash = "ask";
        };
        mcp = {
          context7 = {
            type = "remote";
            url = "https://mcp.context7.com/mcp";
            headers = {
              CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
            };
            enabled = true;
          };
          ddog = {
            type = "remote";
            url = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
            oauth = {
              scope = "openid";
            };
          };

          # need to generate the figma auth vars seperatly
          # curl -s -X POST "https://api.figma.com/v1/oauth/mcp/register" \
          #   -H "Content-Type: application/json" \
          #   -d '{
          # "client_name": "Claude Code (figma)",
          # "redirect_uris": ["http://127.0.0.1:19876/mcp/oauth/callback"],
          # "grant_types": ["authorization_code", "refresh_token"],
          # "response_types": ["code"],
          # "token_endpoint_auth_method": "none"
          # }'
          figma = {
            type = "remote";
            url = "https://mcp.figma.com/mcp";
            enabled = true;
            oauth = {
              clientId = "{env:FIGMA_CLIENTID}";
              clientSecret = "{env:FIGMA_CLIENTSECRET}";
            };
          };

          grep = {
            type = "remote";
            url = "https://mcp.grep.app";
          };
          nixos = {
            type = "local";
            command = [ "${upkgs.mcp-nixos}/bin/mcp-nixos" ];
          };
        };

        lsp = {
          rust = {
            # lspmux-attach rather than a bare `lspmux client`: with LSPMUX_SESSION
            # set it joins the named session by name, so a jailed opencode and the
            # host's neovim land on one rust-analyzer instead of two. Absolute
            # store path because the jail's PATH is its own toolbelt.
            command = [
              "${self.packages.${system}.lspmux-session}/bin/lspmux-attach"
            ];

            # lspmux gives the *first* client's initializationOptions to the
            # server and discards everyone else's, so this has to match what
            # rustaceanvim sends or the config depends on who connected first.
            initialization = self.lib.rustAnalyzerSettings;
          };
        };
      };

      xdg.configFile."opencode/plugins/ghostty-progress.js".source = ./ghostty-progress.js;

      xdg.configFile."opencode/tui.json".text = builtins.toJSON {
        "$schema" = "https://opencode.ai/tui.json";
        theme = "customtheme";
        scroll_speed = 1;
        keybinds = {
          leader = "ctrl+x";
          app_exit = "ctrl+c,ctrl+d,<leader>q";
          editor_open = "<leader>e";
          theme_list = "<leader>t";
          sidebar_toggle = "<leader>b";
          scrollbar_toggle = "none";

          status_view = "<leader>s";
          session_export = "<leader>x";
          session_new = "<leader>n";
          session_list = "<leader>l";
          session_timeline = "<leader>g";
          session_fork = "none";
          session_rename = "none";
          session_share = "none";
          session_unshare = "none";
          session_interrupt = "escape";
          session_compact = "<leader>c";
          messages_page_up = "pageup";
          messages_page_down = "pagedown";
          messages_half_page_up = "ctrl+alt+u";
          messages_half_page_down = "ctrl+alt+d";
          messages_first = "ctrl+g,home";
          messages_last = "ctrl+alt+g,end";
          messages_last_user = "none";
          messages_copy = "<leader>y";
          messages_undo = "<leader>u";
          messages_redo = "<leader>r";
          messages_toggle_conceal = "<leader>h";
          tool_details = "none";
          model_list = "<leader>m";
          model_cycle_recent = "f2";
          model_cycle_recent_reverse = "shift+f2";
          model_cycle_favorite = "none";
          model_cycle_favorite_reverse = "none";
          command_list = "ctrl+p";
          agent_list = "<leader>a";
          agent_cycle = "tab";
          agent_cycle_reverse = "shift+tab";
          input_clear = "ctrl+c";
          input_paste = "ctrl+v";
          input_submit = "ctrl+return,super+return";
          input_newline = "return";
          input_move_left = "left,ctrl+b";
          input_move_right = "right,ctrl+f";
          input_move_up = "up";
          input_move_down = "down";
          input_select_left = "shift+left";
          input_select_right = "shift+right";
          input_select_up = "shift+up";
          input_select_down = "shift+down";
          input_line_home = "ctrl+a";
          input_line_end = "ctrl+e";
          input_select_line_home = "ctrl+shift+a";
          input_select_line_end = "ctrl+shift+e";
          input_visual_line_home = "alt+a";
          input_visual_line_end = "alt+e";
          input_select_visual_line_home = "alt+shift+a";
          input_select_visual_line_end = "alt+shift+e";
          input_buffer_home = "home";
          input_buffer_end = "end";
          input_select_buffer_home = "shift+home";
          input_select_buffer_end = "shift+end";
          input_delete_line = "ctrl+shift+d";
          input_delete_to_line_end = "ctrl+k";
          input_delete_to_line_start = "ctrl+u";
          input_backspace = "backspace,shift+backspace";
          input_delete = "ctrl+d,delete,shift+delete";
          input_undo = "ctrl+-,super+z";
          input_redo = "ctrl+.,super+shift+z";
          input_word_forward = "alt+f,alt+right,ctrl+right";
          input_word_backward = "alt+b,alt+left,ctrl+left";
          input_select_word_forward = "alt+shift+f,alt+shift+right";
          input_select_word_backward = "alt+shift+b,alt+shift+left";
          input_delete_word_forward = "alt+d,alt+delete,ctrl+delete";
          input_delete_word_backward = "ctrl+w,ctrl+backspace,alt+backspace";
          history_previous = "up";
          history_next = "down";
          session_child_cycle = "<leader>right";
          session_child_cycle_reverse = "<leader>left";
          terminal_suspend = "ctrl+z";
          terminal_title_toggle = "none";
        };
      };
    };
}
