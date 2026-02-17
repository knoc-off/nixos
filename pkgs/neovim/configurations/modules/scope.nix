# Cohesive scope visualization
# - Rainbow delimiters: vivid, depth-based brackets
# - IBL indent: subtle single color
# - IBL scope: depth-based using rainbow colors (language-aware)
# - Matchup: bright active pair highlighting
{lib, ...}: let
  # Shared rainbow highlight groups (used by both rainbow-delimiters and IBL scope)
  rainbowHighlights = [
    "RainbowDelimiterRed"
    "RainbowDelimiterYellow"
    "RainbowDelimiterBlue"
    "RainbowDelimiterOrange"
    "RainbowDelimiterGreen"
    "RainbowDelimiterViolet"
    "RainbowDelimiterCyan"
  ];

  # Language-aware treesitter node types for scope highlighting
  scopeNodeTypes = {
    rust = [
      "function_item"
      "impl_item"
      "trait_item"
      "struct_item"
      "enum_item"
      "mod_item"
      "macro_definition"
      "block"
      "if_expression"
      "match_expression"
      "while_expression"
      "loop_expression"
      "for_expression"
      "try_expression"
    ];

    typescript = [
      "function_declaration"
      "function"
      "method_definition"
      "arrow_function"
      "class_declaration"
      "class_body"
      "if_statement"
      "for_statement"
      "for_in_statement"
      "for_of_statement"
      "while_statement"
      "do_statement"
      "switch_statement"
      "switch_body"
      "try_statement"
      "catch_clause"
      "finally_clause"
      "statement_block"
      "object"
      "object_pattern"
      "array"
      "array_pattern"
      "call_expression"
      "arguments"
      "parenthesized_expression"
    ];

    tsx = [
      # TSX reuses most TS nodes, plus JSX containers
      "function_declaration"
      "function"
      "method_definition"
      "arrow_function"
      "class_declaration"
      "class_body"
      "if_statement"
      "for_statement"
      "for_in_statement"
      "for_of_statement"
      "while_statement"
      "do_statement"
      "switch_statement"
      "switch_body"
      "try_statement"
      "catch_clause"
      "finally_clause"
      "statement_block"
      "object"
      "array"
      "call_expression"
      "arguments"
      "parenthesized_expression"
      "jsx_element"
      "jsx_self_closing_element"
      "jsx_fragment"
    ];

    lua = [
      "function_declaration"
      "function_definition"
      "local_function"
      "function_call"
      "arguments"
      "do_statement"
      "if_statement"
      "while_statement"
      "repeat_statement"
      "for_statement"
      "for_in_statement"
      "table_constructor"
      "field"
      "block"
    ];

    nix = [
      # top-level / let-in
      "let_expression"
      "attrset_expression"
      "rec_attrset_expression"
      # blocks / grouping
      "list_expression"
      "parenthesized_expression"
      # functions / lambdas
      "lambda_expression"
      # control-ish
      "if_expression"
      "with_expression"
      "assert_expression"
      # common "structured" spots
      "binding"
      "inherit"
    ];

    json = [
      "object"
      "array"
      "pair"
    ];

    yaml = [
      "block_mapping_pair"
      "block_mapping"
      "block_sequence"
      "flow_mapping"
      "flow_sequence"
    ];

    markdown = [
      "section"
      "list"
      "list_item"
      "block_quote"
      "fenced_code_block"
    ];

    # Fallback for anything else
    "*" = [
      "function"
      "method"
      "class"
      "block"
      "^if"
      "^for"
      "^while"
      "try_statement"
      "catch_clause"
      "arguments"
      "object"
      "array"
      "parenthesized_expression"
    ];
  };
in {
  plugins.rainbow-delimiters = {
    enable = true;
    settings.highlight = rainbowHighlights;
  };

  plugins.indent-blankline = {
    enable = true;
    settings = {
      exclude = {
        filetypes = [
          "dashboard"
          "lspinfo"
          "packer"
          "checkhealth"
          "help"
          "man"
          "gitcommit"
          "TelescopePrompt"
          "TelescopeResults"
          "''"
        ];
      };

      indent = {
        char = "│";
        highlight = ["IblIndent"];
      };

      scope = {
        enabled = true;
        char = "▎";
        show_start = false;
        show_end = false;
        highlight = rainbowHighlights;
        include.node_type = scopeNodeTypes;
      };
    };
  };

  # vim-matchup - enhanced % matching with highlighting
  # Treesitter integration is automatic in Neovim
  plugins.vim-matchup.enable = true;

  extraConfigLua = ''
    -- Integrate IBL with rainbow-delimiters for consistent scope colors
    local hooks = require("ibl.hooks")
    hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
  '';
}
