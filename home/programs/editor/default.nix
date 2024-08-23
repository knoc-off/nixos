{pkgs, self, ...}: {
  imports = [
    #inputs.nixvim.homeManagerModules.nixvim
    #./neovim
  ];
  #home.packages = [inputs.neovim.packages.${system}.default];
  home.packages = [
    self.packages.${pkgs.system}.neovim-nix.default
  ];
}
