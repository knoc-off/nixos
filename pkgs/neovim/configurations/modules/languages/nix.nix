# Nix development environment.
#
# Two language servers with deliberately non-overlapping responsibilities:
#   * nixd  -> completion, hover/option docs, go-to-definition. Wired to this
#             flake's nixpkgs + NixOS options so package names and NixOS option
#             documentation resolve (the IDE-like part). Its own diagnostics are
#             suppressed to avoid duplicating nil.
#   * nil   -> diagnostics / eval errors only (its strong suit). Formatting and
#             completion disabled so it doesn't fight nixd.
#
# Formatting: nixfmt-rfc-style (the current standard) via conform.
# Linting (statix, deadnix) lives in languages/lint.nix via nvim-lint.
{lib, pkgs, ...}: let
  nixfmt = lib.getExe pkgs.nixfmt-rfc-style;
  # Host whose evaluated options power nixd's NixOS option completion/docs.
  # Change if you primarily edit a different machine's config.
  optionsHost = "thinkpad-work";
in {
  plugins.lsp.servers = {
    # nixd: the completion / documentation engine.
    nixd = {
      enable = true;
      settings.nixd = {
        # Flake-native sources so completion works without relying on channels
        # / NIX_PATH. nixpkgs packages and NixOS options both come from this
        # flake's own inputs and evaluated host config.
        nixpkgs.expr =
          "(builtins.getFlake (toString ./.)).inputs.nixpkgs-unstable.legacyPackages.\${builtins.currentSystem}";
        formatting.command = [nixfmt];
        options.nixos.expr =
          "(builtins.getFlake (toString ./.)).nixosConfigurations.${optionsHost}.options";
        # nil owns diagnostics; keep nixd from emitting overlapping ones.
        diagnostic.suppress = ["sema-escaping-with"];
      };
    };

    # nil: diagnostics only. Turn off its formatter so nixd/conform own that.
    nil_ls = {
      enable = true;
      settings = {
        nix = {
          binary = lib.getExe pkgs.nix;

          flake = {
            autoArchive = true;
            autoEvalInputs = false;
          };

          maxMemoryMB = 4096;
        };
      };
    };
  };

  # nixd + the RFC-style formatter available to the editor's runtime.
  extraPackages = [pkgs.nixd pkgs.nixfmt-rfc-style];

  plugins.conform-nvim.settings = {
    formatters_by_ft.nix = ["nixfmt"];
    formatters.nixfmt.command = nixfmt;
  };
}
