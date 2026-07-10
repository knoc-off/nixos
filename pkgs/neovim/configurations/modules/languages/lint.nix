# Non-LSP linters via nvim-lint (complements conform.nvim formatting + LSP).
# autoInstall pulls the linter binaries from nixpkgs automatically; the built-in
# BufWritePost autocmd runs `try_lint()` on save, which only executes linters
# matching the current buffer's filetype -- so linting stays lazy per-filetype.
{pkgs, ...}: {
  plugins.lint = {
    enable = true;

    autoInstall = {
      enable = true;
      # nvim-lint calls this linter `markdownlint`, but the nixpkgs attr is
      # `markdownlint-cli`; every other linter below resolves as `pkgs.<name>`.
      overrides.markdownlint = pkgs.markdownlint-cli;
    };

    lintersByFt = {
      nix = ["statix" "deadnix"];
      lua = ["selene"];
      yaml = ["yamllint"];
      sh = ["shellcheck"];
      bash = ["shellcheck"];
      markdown = ["markdownlint"];
      dockerfile = ["hadolint"];
    };
  };

  # actionlint only makes sense for GitHub workflow files, not arbitrary YAML.
  # Run it as an extra, filename-guarded linter on save for those paths only.
  extraConfigLua = ''
    vim.api.nvim_create_autocmd("BufWritePost", {
      pattern = { "*/.github/workflows/*.yml", "*/.github/workflows/*.yaml" },
      callback = function()
        require("lint").try_lint("actionlint")
      end,
      desc = "Lint GitHub Actions workflows with actionlint",
    })
  '';

  extraPackages = [pkgs.actionlint];
}
