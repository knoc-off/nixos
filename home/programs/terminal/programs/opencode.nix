{
  self,
  upkgs,
  pkgs,
  lib,
  inputs,
  ...
}: let
  inherit (self.lib) color-lib theme;
  system = pkgs.stdenv.hostPlatform.system;

  # QML LSP import paths
  # Exact quickshell version shipped with noctalia (has .qmltypes for all
  # Quickshell.* modules including Quickshell.Io)
  noctaliaShell = inputs.noctalia.packages.${system}.default;
  quickshell = inputs.noctalia.inputs.noctalia-qs.packages.${system}.quickshell;

  # Shim that generates proper qmldir files for each qs.* module so qmlls can
  # actually resolve imports.  A plain symlink isn't enough -- qmlls requires
  # qmldir files to recognise a directory as a QML module.  We generate one for
  # every directory under the noctalia-shell root that contains .qml files,
  # mirroring Quickshell's `-p <shell-root>` -> `qs.<dir>` naming convention.
  #
  # ── QML Type Inference Notes ─────────────────────────────────────────────
  # When a property is typed as a base class (e.g., Process.stdout is
  # DataStreamParser), the LSP can only infer the base type even if you assign
  # a subclass (e.g., StdioCollector). To get proper type inference:
  #
  #   BAD:  Process { stdout: StdioCollector {}; onExited: stdout.text }
  #         -> LSP error: "text" not found on DataStreamParser
  #
  #   GOOD: Process { stdout: StdioCollector { id: collector }
  #                   onExited: collector.text }
  #         -> LSP knows collector is StdioCollector with .text property
  #
  # Always assign an id to nested objects when you need to access their
  # subclass-specific members. The LSP uses the id's declared type, not the
  # parent property's type.
  qsImportShim = pkgs.runCommand "noctalia-qmlls-shim" {} ''
    shell_root="${noctaliaShell}/share/noctalia-shell"

    # make_module <rel-path-from-shell-root> <qml-module-name>
    # Creates $out/qs/<rel-path>/qmldir listing every .qml in that directory,
    # plus a symlink to each source file so qmlls can parse them for type info.
    make_module() {
      local rel=$1 mod=$2
      local src="$shell_root/$rel"
      local dst="$out/qs/$rel"
      [ -d "$src" ] || return 0
      mkdir -p "$dst"
      printf 'module %s\n' "$mod" > "$dst/qmldir"
      for f in "$src"/*.qml; do
        [ -f "$f" ] || continue
        comp=$(basename "$f" .qml)
        # Mark singletons correctly so qmlls can resolve their members
        if grep -q 'pragma Singleton' "$f"; then
          printf 'singleton %s 1.0 %s\n' "$comp" "$(basename "$f")" >> "$dst/qmldir"
        else
          printf '%s 1.0 %s\n' "$comp" "$(basename "$f")" >> "$dst/qmldir"
        fi
        ln -sf "$f" "$dst/$(basename "$f")"
      done
    }

    make_module Commons        qs.Commons
    make_module Widgets        qs.Widgets

    # Widgets sub-modules (e.g. AudioSpectrum)
    for d in "$shell_root/Widgets"/*/; do
      [ -d "$d" ] || continue
      sub=$(basename "$d")
      make_module "Widgets/$sub" "qs.Widgets.$sub"
    done

    # Services sub-modules (UI, System, Compositor, ...)
    for d in "$shell_root/Services"/*/; do
      [ -d "$d" ] || continue
      svc=$(basename "$d")
      make_module "Services/$svc" "qs.Services.$svc"
    done

    # Modules and all nested sub-modules (Bar/Extras, Panels/Bluetooth, ...)
    make_module Modules qs.Modules
    for d in "$shell_root/Modules"/*/; do
      [ -d "$d" ] || continue
      sub=$(basename "$d")
      make_module "Modules/$sub" "qs.Modules.$sub"
      for d2 in "$d"/*/; do
        [ -d "$d2" ] || continue
        sub2=$(basename "$d2")
        make_module "Modules/$sub/$sub2" "qs.Modules.$sub.$sub2"
        for d3 in "$d2"/*/; do
          [ -d "$d3" ] || continue
          sub3=$(basename "$d3")
          make_module "Modules/$sub/$sub2/$sub3" "qs.Modules.$sub.$sub2.$sub3"
        done
      done
    done
  '';

  qmlImportPath = builtins.concatStringsSep ":" [
    "${qsImportShim}" # qs.*  (Noctalia modules)
    "${quickshell}/lib/qt-6/qml" # Quickshell, Quickshell.Io, ...
    "${pkgs.kdePackages.qtdeclarative}/lib/qt-6/qml" # QtQuick, QtQuick.Controls, ...
  ];

  qmlDocPath = "${pkgs.kdePackages.qtdoc}/share/doc/qtdoc";
in {
  programs.opencode = let
    inherit (color-lib) setOkhslLightness setOkhslSaturation;
    lighten = setOkhslLightness 0.7;
    saturate = setOkhslSaturation 0.9;

    sa = hex: lighten (saturate hex);
  in {
    enable = true;
    package = upkgs.opencode;
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
        diffremoved = "#${color-lib.mixColors (color-lib.setOkhslLightness 0.2 theme.dark.base08) theme.dark.base00 0.1}";
        #diffremoved = "#${color-lib.mixColors (color-lib.adjustOkhslLightness 0.03 theme.dark.base00) theme.dark.base08 0.3}";
        base09 = "#${sa theme.dark.base09}";
        base0A = "#${sa theme.dark.base0A}";
        base0B = "#${sa theme.dark.base0B}";
        #diffadded = "#${color-lib.mixColors (color-lib.adjustOkhslLightness 0.03 theme.dark.base00) theme.dark.base0B 0.3}";
        #diffadded = "#${color-lib.setOkhslLightness 0.2 theme.dark.base0B}";
        diffadded = "#${color-lib.mixColors (color-lib.setOkhslLightness 0.2 theme.dark.base0B) theme.dark.base00 0.1}";
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
          dark = "base0C"; #!!!
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
          dark = "base00-2"; # TODO
          light = "base06";
        };
        diffRemovedLineNumberBg = {
          dark = "base00-2"; # TODO
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

    settings = {
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

        grep = {
          type = "remote";
          url = "https://mcp.grep.app";
        };
        nixos = {
          type = "local";
          command = ["${upkgs.mcp-nixos}/bin/mcp-nixos"];
        };
        memory = {
          type = "local";
          command = [
            "${pkgs.uv}/bin/uvx"
            "basic-memory"
            "mcp"
          ];
          environment = {
            BASIC_MEMORY_NO_PROMOS = "1";
            PATH = "${pkgs.stdenv.cc}/bin:${pkgs.curl}/bin:${pkgs.bash}/bin:/run/current-system/sw/bin";
          };
        };
      };

      lsp = {
        qml = {
          command = [
            "${pkgs.kdePackages.qtdeclarative}/bin/qmlls"
            "-E"
            "--no-cmake-calls"
            "--doc-dir"
            qmlDocPath
          ];
          extensions = [".qml"];
          env = {
            QML_IMPORT_PATH = qmlImportPath;
          };
        };
        rust = {
          command = [
            "${self.packages.${system}.lspmux}/bin/lspmux"
            "client"
          ];
        };
      };
    };
  };

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
      username_toggle = "none";
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
}
