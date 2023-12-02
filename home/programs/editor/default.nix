{ pkgs, inputs, libs, config, system, ... }:
{
  imports = [

    #inputs.nixvim.homeManagerModules.nixvim
    #./neovim
  ];
  home.packages = [ inputs.nixvim-flake.packages.${system}.default ];

}
