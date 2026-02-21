# smart-paste.nvim nixvim module
# Provides typed options for configuring smart-paste
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) types mkEnableOption mkOption;
  inherit (lib.nixvim) defaultNullOpts mkRaw;

  cfg = config.plugins.smart-paste;

  # Key entry submodule for structured key configuration
  keyEntryType = types.submodule {
    options = {
      lhs = mkOption {
        type = types.str;
        description = "The left-hand side (key sequence) for the mapping";
      };

      like = mkOption {
        type = types.nullOr (types.enum ["p" "P" "gp" "gP" "]p" "[p"]);
        default = null;
        description = "Inherit behavior flags from a built-in key";
      };

      after = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Paste after cursor position";
      };

      follow = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Move cursor to end of pasted content";
      };

      charwise_newline = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Convert charwise content to new indented line";
      };
    };
  };

  # Type that accepts either a string or a structured key entry
  keyType = types.either types.str keyEntryType;
in {
  options.plugins.smart-paste = {
    enable = mkEnableOption "smart-paste.nvim - auto-indenting paste";

    package = mkOption {
      type = types.package;
      default = pkgs.vimPlugins.smart-paste-nvim or (pkgs.callPackage ./package.nix {inherit (pkgs) vimUtils fetchFromGitHub;});
      defaultText = lib.literalExpression "pkgs.vimPlugins.smart-paste-nvim";
      description = "The smart-paste.nvim package to use";
    };

    settings = {
      keys = mkOption {
        type = types.nullOr (types.listOf keyType);
        default = null;
        example = ["p" "P" "gp" "gP" "]p" "[p"];
        description = ''
          List of keys to enhance with smart paste behavior.
          Can be strings (e.g., "p", "P") or structured entries with custom flags.

          Default plugin keys: ["p" "P" "gp" "gP" "]p" "[p"]

          Structured example:
          ```nix
          [
            "p"
            { lhs = "-p"; like = "]p"; }
            { lhs = "gP"; after = false; follow = true; charwise_newline = false; }
          ]
          ```
        '';
      };

      exclude_filetypes = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["oil" "neo-tree" "TelescopePrompt"];
        description = "Filetypes where smart paste is disabled (uses native paste instead)";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    extraPlugins = [cfg.package];

    extraConfigLua = let
      # Convert Nix key entries to Lua
      keyToLua = key:
        if builtins.isString key
        then ''"${key}"''
        else let
          attrs =
            ["lhs = \"${key.lhs}\""]
            ++ lib.optional (key.like != null) "like = \"${key.like}\""
            ++ lib.optional (key.after != null) "after = ${lib.boolToString key.after}"
            ++ lib.optional (key.follow != null) "follow = ${lib.boolToString key.follow}"
            ++ lib.optional (key.charwise_newline != null) "charwise_newline = ${lib.boolToString key.charwise_newline}";
        in "{ ${lib.concatStringsSep ", " attrs} }";

      keysLua =
        if cfg.settings.keys == null
        then "nil"
        else "{ ${lib.concatStringsSep ", " (map keyToLua cfg.settings.keys)} }";

      excludeFiletypesLua =
        if cfg.settings.exclude_filetypes == []
        then "{}"
        else "{ ${lib.concatStringsSep ", " (map (ft: ''"${ft}"'') cfg.settings.exclude_filetypes)} }";
    in ''
      require("smart-paste").setup({
        ${lib.optionalString (cfg.settings.keys != null) "keys = ${keysLua},"}
        exclude_filetypes = ${excludeFiletypesLua},
      })
    '';
  };
}
