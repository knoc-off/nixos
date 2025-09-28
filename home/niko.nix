{
  pkgs,
  upkgs,
  self,
  config,
  ...
}: {
  # test
  imports = [
    ./programs/terminal/kitty
    ./programs/terminal
    ./programs/browser/firefox/default.nix

    self.homeModules.git
    self.homeModules.starship

    #./programs/terminal/shell
    ./programs/terminal/shell/fish.nix
    {
      targets.darwin.defaults."com.apple.finder".ShowPathBar = true; # ? what does this do?

      home.packages = with pkgs; [
        gum
        television

        upkgs.tsx
      ];
      programs.zsh = {
        enable = true;
        initContent = ''
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^[[101;9u' edit-command-line
        '';
        shellAliases = {
          g = "git";
          nxrb = "sudo darwin-rebuild switch --flake /Users/niko/projects/nixos/";
        };
      };
      programs.bash.enable = true;
    }

    ./programs/filemanager/yazi.nix
  ];

  home.stateVersion = "25.05";
}
