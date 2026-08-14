# rhizome nixvim module
#
# Trilium notes as Neovim buffers. The plugin talks to a `rhizome lsp` process
# over stdio, so the only real configuration is how to reach the server and
# where to get a token.
{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib) types mkEnableOption mkOption mkIf;

  cfg = config.plugins.rhizome;
in {
  options.plugins.rhizome = {
    enable = mkEnableOption "rhizome - Trilium notes in Neovim";

    package = mkOption {
      type = types.package;
      default = pkgs.rhizome;
      defaultText = lib.literalExpression "pkgs.rhizome";
      description = ''
        The rhizome package. Its `passthru.plugin` supplies the Lua side with
        the engine's store path already baked in, so the binary never has to be
        on $PATH.
      '';
    };

    url = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://trilium.example.com";
      description = ''
        Base URL of the Trilium server. Read from `urlEnv` when null.
      '';
    };

    urlEnv = mkOption {
      type = types.str;
      default = "RHIZOME_URL";
      description = "Environment variable holding the server URL, used when `url` is null.";
    };

    tokenEnv = mkOption {
      type = types.str;
      default = "RHIZOME_TOKEN";
      example = "TRILIUM_TOKEN";
      description = ''
        Environment variable holding the ETAPI token.

        This is the seam that keeps the editor configuration independent of any
        particular secret manager: whatever populates the environment (sops,
        direnv, a password manager) is none of nixvim's business. The variable
        must be visible to the process running Neovim, not merely to an
        interactive shell.
      '';
    };

    tokenCommand = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
      example = ["pass" "trilium/etapi"];
      description = ''
        Command printing an ETAPI token on stdout, for when the token is not in
        the environment. Takes precedence over `tokenEnv`.
      '';
    };

    softWrap = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Soft-wrap note buffers for prose editing: `wrap`/`linebreak` so long
        paragraphs wrap at word boundaries, `breakindent` (+ a Markdown-aware
        `formatlistpat`) so wrapped list continuations align under the marker,
        and the conform.nvim `disable_autoformat` buffer flag so a project-wide
        markdown formatter/linter leaves the note alone -- every newline in a
        rhizome buffer round-trips to a `<br>`, so a reflow would rewrite the
        note's HTML. The bundled `languages` module's `format_on_save` and
        nvim-lint hooks honour that flag.
      '';
    };

    keymaps = {
      enable = mkEnableOption "default rhizome keymaps" // {default = true;};

      pick = mkOption {
        type = types.nullOr types.str;
        default = "<leader>nn";
        description = "Open the note picker. Null to skip.";
      };

      search = mkOption {
        type = types.nullOr types.str;
        default = "<leader>ns";
        description = "Search notes by query. Null to skip.";
      };

      metadata = mkOption {
        type = types.nullOr types.str;
        default = "<leader>nm";
        description = "Show the current note's metadata. Null to skip.";
      };

      actions = mkOption {
        type = types.nullOr types.str;
        default = "<leader>na";
        description = "Browse and run rhizome actions. Null to skip.";
      };
    };
  };

  config = mkIf cfg.enable {
    extraPlugins = [cfg.package.passthru.plugin];

    # `rhizome` in $PATH is not needed by the plugin, but having the CLI
    # available makes `rhizome roundtrip` and friends usable from :terminal.
    extraPackages = [cfg.package];

    extraConfigLua = let
      luaString = s: ''"${lib.escape ["\"" "\\"] s}"'';
      tokenCommandLua =
        if cfg.tokenCommand == null
        then "nil"
        else "{ ${lib.concatMapStringsSep ", " luaString cfg.tokenCommand} }";
    in ''
      require("rhizome").setup({
        url = ${
        if cfg.url == null
        then "nil"
        else luaString cfg.url
      },
        url_env = ${luaString cfg.urlEnv},
        token_env = ${luaString cfg.tokenEnv},
        token_cmd = ${tokenCommandLua},
        soft_wrap = ${lib.boolToString cfg.softWrap},
      })
    '';

    keymaps = lib.optionals cfg.keymaps.enable (
      lib.optional (cfg.keymaps.pick != null) {
        mode = "n";
        key = cfg.keymaps.pick;
        action = "<cmd>Rhizome<cr>";
        options.desc = "Trilium: pick a note";
      }
      ++ lib.optional (cfg.keymaps.search != null) {
        mode = "n";
        key = cfg.keymaps.search;
        action = ":Rhizome search ";
        options.desc = "Trilium: search notes";
      }
      ++ lib.optional (cfg.keymaps.metadata != null) {
        mode = "n";
        key = cfg.keymaps.metadata;
        action = "<cmd>Rhizome meta<cr>";
        options.desc = "Trilium: note metadata";
      }
      ++ lib.optional (cfg.keymaps.actions != null) {
        mode = "n";
        key = cfg.keymaps.actions;
        action = "<cmd>Rhizome actions<cr>";
        options.desc = "Trilium: browse actions";
      }
    );
  };
}
