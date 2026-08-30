{
  self,
  inputs,
  pkgs,
  lib,
  upkgs,
  jailContext,
  claudeMem,
  hostQuery,
  lspmuxSession,
}:

# The jail's entire ~/.config/opencode, built in the store.
#
# This used to be the host's real config directory, bind-mounted in. It isn't
# any more: the jail's ~ is a tmpfs (jail-nix `base`), so every file under it
# is something we deliberately put there, and there is no reason for the one
# directory that decides how the agent behaves to be the mutable host copy.
# Generating it here means the jail reads exactly what this file says and
# nothing else -- no host state, no merge layer, no drift between a machine
# that has been running opencode for a year and a fresh install.
#
# It is mounted as the lower (read-only) layer of a tmpfs overlay rather than
# a plain ro-bind, because opencode writes into its own config dir on every
# start and cannot be told not to:
#
#   * `ensureGitignore` (config/config.ts) writes .gitignore into every config
#     directory it walks, unconditionally.
#   * a background `bun add @opencode-ai/plugin` runs against each config dir
#     (config/config.ts), producing package.json / bun.lock / node_modules.
#   * ponytail persists the active level to .ponytail-active.
#
# Those all land in the overlay's tmpfs upper layer and are discarded at
# session end. The npm install re-runs each session as a result; it is
# backgrounded and non-fatal, and the jail has network, so that is cheap.
# The upside is that a session can never accumulate config state.
#
# Note OPENCODE_CONFIG_DIR is deliberately NOT used to point opencode here.
# It is additive, not a replacement: ConfigPaths.directories() appends it to a
# list that always begins with Global.Path.config, and Global.Path.config is
# derived from XDG_CONFIG_HOME and mkdir'd at module load regardless. Owning
# ~/.config/opencode outright is the only way to be sure nothing else is read.

let
  inherit (self.lib) color-lib theme;

  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.7;
  saturate = setOkhslSaturation 0.9;
  sa = hex: lighten (saturate hex);

  customtheme = {
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
      base09 = "#${sa theme.dark.base09}";
      base0A = "#${sa theme.dark.base0A}";
      base0B = "#${sa theme.dark.base0B}";
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
        dark = "base0C";
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
        dark = "base0E";
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

  opencodeJson = {
    "$schema" = "https://opencode.ai/config.json";
    autoupdate = false;

    provider.anthropic.options = {
      # Set by wrap-entry once compat-proxy has a port.
      baseURL = "{env:OPENCODE_PROXY_URL}";
      apiKey = "not-needed";
    };

    # No agent.*.prompt overrides: packages/opencode/src/session/prompt/anthropic.txt
    # is patched at the source (pkgs/opencode) to be the real system prompt, so
    # build/plan/general/explore/title/summary/compaction all fall through to
    # opencode's own (now Claude-Code-branded) defaults.

    # The agent's model of the filesystem it has been given: real project
    # paths, the scratch and workspaces binds, and which of them persist.
    # An instruction file rather than a proxy-injected prompt, so it is
    # opencode's own config that decides.
    instructions = [ "${jailContext}" ];

    # Relaxed relative to a bare host install because the sandbox already
    # constrains blast radius.
    permission = {
      # Read/explore — always allowed, no side effects
      read = "allow";
      glob = "allow";
      grep = "allow";
      list = "allow";
      lsp = "allow";
      repo_overview = "allow";
      codesearch = "allow";
      webfetch = "allow";
      websearch = "allow";

      # Agent utilities — safe
      # NOTE: task and todowrite are intentionally omitted. The default
      # "*": "allow" still lets the top-level agent use them, but opencode's
      # exact-match checks (rule.permission === "task"/"todowrite") won't
      # find explicit rules, so sub-agents get these tools disabled --
      # preventing recursive spawning and todo list clobbering.
      question = "allow";
      repo_clone = "allow";
      skill = "allow";
      external_directory = "allow";

      # Bash — sandbox + trash-backed rm constrain damage
      bash = "allow";

      # Edit — user approves each file modification
      edit = "ask";

      # Host exec — user approves each host command
      host_exec = "ask";
    };

    # ponytail: injects its ruleset into the system prompt every turn and adds
    # the /ponytail* commands. Referenced by store path rather than the npm
    # spec "@dietrichgebert/ponytail" so opencode never installs it at runtime
    # -- the whole point of this directory is that nothing here is fetched or
    # mutated per session. The plugin locates its own hooks/ and skills/
    # relative to its file, which is why an in-tree path works (upstream
    # documents this as the "share one checkout" mode).
    #
    # Caveat: pkgs/opencode drops the `skill` tool from the outgoing tools
    # array (CC_DROPPED_TOOLS), so ponytail's six skills are advertised in the
    # system prompt but cannot actually be invoked. The always-on ruleset
    # injection and the slash commands -- the substance of it -- work.
    plugin = [ "${inputs.ponytail}/.opencode/plugins/ponytail.mjs" ];

    mcp = {
      context7 = {
        type = "remote";
        url = "https://mcp.context7.com/mcp";
        headers.CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
        enabled = true;
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

    lsp.rust = {
      # lspmux-attach rather than a bare `lspmux client`: with LSPMUX_SESSION
      # set it joins the named session by name, so a jailed opencode and the
      # host's neovim land on one rust-analyzer instead of two.
      command = [ "${lspmuxSession}/bin/lspmux-attach" ];

      # lspmux gives the *first* client's initializationOptions to the server
      # and discards everyone else's, so this has to match what rustaceanvim
      # sends or the config depends on who connected first.
      initialization = self.lib.rustAnalyzerSettings;
    };
  };

  tuiJson = {
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
in
# Real files rather than symlinks into the store. Both the plugin scan
# ({plugin,plugins}/*.{ts,js}) and the theme scan (themes/*.json) go through
# glob with nodir, and this directory is an overlayfs lower layer -- copying
# keeps both of those away from any symlink-resolution edge case for the sake
# of a few KB.
pkgs.runCommand "opencode-jail-config" { } ''
  mkdir -p $out/themes $out/plugins

  cp ${pkgs.writeText "opencode.json" (builtins.toJSON opencodeJson)} $out/opencode.json
  cp ${pkgs.writeText "tui.json" (builtins.toJSON tuiJson)} $out/tui.json
  cp ${pkgs.writeText "customtheme.json" (builtins.toJSON customtheme)} $out/themes/customtheme.json

  cp ${./ghostty-progress.js} $out/plugins/ghostty-progress.js
  cp ${claudeMem}/lib/claude-mem/dist/opencode-plugin/index.js $out/plugins/claude-mem.js
  cp ${hostQuery}/lib/host-query/plugin/index.js $out/plugins/host-query.js
''
