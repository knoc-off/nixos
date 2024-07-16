{
  pkgs,
  ...
}: {
  imports = [
    #inputs.nixvim.homeManagerModules.nixvim
    #./neovim
  ];
  #home.packages = [inputs.neovim.packages.${system}.default];
  home.packages = [
    pkgs.neovim-nix.default
  ];

}
