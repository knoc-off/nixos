# Non-LSP linters via nvim-lint (complements conform.nvim formatting + LSP).
# autoInstall pulls the linter binaries from nixpkgs automatically; the built-in
# BufWritePost autocmd runs `try_lint()` on save, which only executes linters
# matching the current buffer's filetype -- so linting stays lazy per-filetype.
{pkgs, lib, ...}: {
  plugins.lint = {
    enable = true;

    autoInstall = {
      enable = true;
      # nvim-lint calls this linter `markdownlint`, but the nixpkgs attr is
      # `markdownlint-cli`; every other linter below resolves as `pkgs.<name>`.
      overrides.markdownlint = pkgs.markdownlint-cli;
    };

    # Skip linting on buffers that opt out via `vim.b.disable_autoformat`
    # (conform's convention, reused here so one flag silences both formatter
    # and linter). rhizome note buffers set it: they are `filetype =
    # "markdown"` but markdownlint's diagnostics are noise on a buffer whose
    # newlines and blank-line runs are load-bearing HTML, not prose.
    autoCmd.callback = lib.nixvim.mkRaw ''
      function()
        if vim.b.disable_autoformat or vim.g.disable_autoformat then
          return
        end
        require('lint').try_lint()
      end
    '';

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
    -- markdownlint's MD013 (line-length, 80 cols) fires constantly on prose and
    -- is mostly noise. Disable just that rule; every other markdownlint rule
    -- still runs. NOTE: upstream default args are { "--stdin" } (nvim-lint/lua/
    -- lint/linters/markdownlint.lua) -- re-sync this list if that ever changes.
    require("lint").linters.markdownlint.args = { "--stdin", "--disable", "MD013" }

    -- Same story for yamllint's line-length rule (80 cols, also noisy on
    -- generated/data YAML). NOTE: upstream default args are
    -- { "--format", "parsable", "-" } (nvim-lint/lua/lint/linters/yamllint.lua)
    -- -- re-sync this list if that ever changes.
    require("lint").linters.yamllint.args = {
      "--format", "parsable",
      "-d", "{extends: default, rules: {line-length: disable}}",
      "-",
    }

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
