{ pkgs, ... }: {
  plugins = {
    #nix.enable = true;
    #nix-develop.enable = true;
    #lsp.servers.nixd.enable = true;
    lsp.servers.nixd = {
      enable = true;
      settings = {
        formatting.command = [ "nixfmt" ];
        nixpkgs.expr = "import <nixpkgs> { }";

        options = let flake = ''(builtins.getFlake "/etc/nixos)"'';
        in {
          # Completitions for nixos and home manager options
          nixos.expr = "${flake}.nixosConfigurations.framework13.options";
          home_manager.expr = "${flake}.homeConfigurations.framework13.options";

          nixvim.expr = "${flake}.packages.${pkgs.system}.neovim-nix.default.options";
        };
      };
    };
    #none-ls = {
    #  sources = {
    #    formatting.nixfmt.enable = true;
    #    diagnostics = {
    #      statix.enable = true;
    #      deadnix.enable = true;
    #    };
    #  };
    #};
  };
}
