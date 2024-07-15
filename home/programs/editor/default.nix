{
  inputs,
  system,
  ...
}: {
  imports = [
    #inputs.nixvim.homeManagerModules.nixvim
    #./neovim
  ];
  home.packages = [inputs.neovim.packages.${system}.default];
}
