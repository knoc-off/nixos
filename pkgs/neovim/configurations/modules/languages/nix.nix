# Nix development environment
# - nil_ls (Nix LSP)
# - alejandra formatting
{lib, pkgs, ...}: {
  plugins.lsp.servers.nil_ls = {
    enable = true;

    settings = {
      formatting = {
        command = [(lib.getExe pkgs.alejandra)];
      };

      nix = {
        binary = lib.getExe pkgs.nix;

        flake = {
          # Automatically run nix flake archive on save
          autoArchive = true;
          # Disabled: can cause warnings when inputs fail to evaluate
          autoEvalInputs = false;
        };

        maxMemoryMB = 4096;
      };

      diagnostics = {
        ignored = [];
        excludedFiles = [];
      };
    };
  };

  plugins.conform-nvim.settings = {
    formatters_by_ft.nix = ["alejandra"];
    formatters.alejandra = {
      command = lib.getExe pkgs.alejandra;
    };
  };
}
