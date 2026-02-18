# TypeScript/JavaScript development environment
# - vtsls (TypeScript LSP, faster alternative to ts_ls)
# - Inlay hints for parameters, return types, variable types
# - Auto-imports, completions with full function signatures
{...}: {
  plugins.lsp.servers.vtsls = {
    enable = true;

    settings = {
      typescript = {
        # Disable vtsls built-in formatter (we use biome via conform)
        format.enable = false;

        inlayHints = {
          parameterNames.enabled = "literals";
          parameterTypes.enabled = true;
          variableTypes.enabled = true;
          variableTypes.suppressWhenTypeMatchesName = true;
          propertyDeclarationTypes.enabled = true;
          functionLikeReturnTypes.enabled = true;
          enumMemberValues.enabled = true;
        };

        suggest = {
          completeFunctionCalls = true;
          autoImports = true;
        };

        preferences = {
          importModuleSpecifier = "shortest";
          preferTypeOnlyAutoImports = true;
        };

        updateImportsOnFileMove.enabled = "always";
      };

      javascript = {
        format.enable = false;

        inlayHints = {
          parameterNames.enabled = "literals";
          parameterTypes.enabled = true;
          variableTypes.enabled = true;
          variableTypes.suppressWhenTypeMatchesName = true;
          propertyDeclarationTypes.enabled = true;
          functionLikeReturnTypes.enabled = true;
        };

        suggest = {
          completeFunctionCalls = true;
          autoImports = true;
        };

        preferences = {
          importModuleSpecifier = "shortest";
        };

        updateImportsOnFileMove.enabled = "always";
      };

      vtsls = {
        autoUseWorkspaceTsdk = true;
      };
    };
  };
}
