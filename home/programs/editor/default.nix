{pkgs, self, ...}: {
  home.packages = [
    self.packages.${pkgs.system}.neovim-nix.default
  ];
}
