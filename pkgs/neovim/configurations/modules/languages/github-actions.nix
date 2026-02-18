# GitHub Actions + YAML development environment
# - gh_actions_ls (workflow-aware completions, expression validation)
# - yamlls (general YAML schema validation + completion)
# - actionlint via none-ls (workflow linting as LSP diagnostics)
{pkgs, ...}: {
  # Actions-specific LSP: understands workflow syntax, action inputs/outputs, expressions
  plugins.lsp.servers.gh_actions_ls = {
    enable = true;
    package = pkgs.gh-actions-language-server;
  };

  # General YAML LSP: schema validation, completion, hover docs
  plugins.lsp.servers.yamlls = {
    enable = true;
    settings.yaml = {
      validate = true;
      hover = true;
      completion = true;
      schemaStore.enable = true;

      schemas = {
        "https://json.schemastore.org/github-workflow.json" = "/.github/workflows/*";
        "https://json.schemastore.org/github-action.json" = "action.{yml,yaml}";
        "https://json.schemastore.org/dependabot-2.0.json" = ".github/dependabot.{yml,yaml}";
      };
    };
  };

  # actionlint diagnostics injected via LSP (shows inline in editor)
  plugins.none-ls = {
    enable = true;
    sources.diagnostics.actionlint.enable = true;
  };
}
