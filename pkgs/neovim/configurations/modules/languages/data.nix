# JSON + YAML language support with the full SchemaStore catalog.
#
# jsonls / yamlls provide completion, validation and hover; SchemaStore.nvim
# feeds them hundreds of schemas (package.json, tsconfig.json, docker-compose,
# .eslintrc, GitHub workflows, ...) so you get the IDE-like "which keys are
# valid here" experience. The nixvim schemastore module auto-injects the schema
# lists into jsonls.settings / yamlls.settings AND auto-disables yamlls' weaker
# built-in schemaStore (required by the plugin), so no manual wiring is needed.
#
# Formatting is handled in languages/formatters.nix (biome for JSON, prettierd
# for YAML), so nothing formatting-related belongs here.
#
# NOTE: languages/github-actions.nix (currently disabled in minimal.nix) also
# configures yamlls. If you ever enable it, reconcile it with this module --
# two yamlls server definitions would otherwise collide.
{...}: {
  plugins.lsp.servers = {
    jsonls.enable = true;
    yamlls.enable = true;
  };

  plugins.schemastore = {
    enable = true;
    json.enable = true;
    yaml.enable = true;
  };
}
