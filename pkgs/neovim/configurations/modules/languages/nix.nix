# Nix development environment
# - nil_ls (Nix LSP)
# - alejandra formatting
{lib, pkgs, ...}: let
  alejandra = lib.getExe pkgs.alejandra;
in {
  plugins.lsp.servers.nil_ls = {
    enable = true;

    settings = {
      formatting.command = [alejandra];

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

  plugins.conform-nvim.settings = {
    formatters_by_ft.nix = ["alejandra"];
    formatters.alejandra.command = alejandra;
  };
}
