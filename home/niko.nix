{
  pkgs,
  upkgs,
  self,
  theme,
  config,
  color-lib,
  lib,
  ...
}: {
  # test
  imports = [
    {programs.ghostty.package = lib.mkForce null;}
    ./programs/terminal/ghostty
    # ./programs/terminal/kitty
    ./programs/terminal
    ./programs/browser/firefox/default.nix

    self.homeModules.git
    self.homeModules.starship

    ./programs/terminal/shell
    {
      targets.darwin.defaults."com.apple.finder".ShowPathBar = true; # ? what does this do?

      home.packages = with pkgs; [
        gum

        skim

        watchexec

        upkgs.tsx
      ];
      programs.zsh = {
        enable = true;
        initContent = ''
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^[[101;9u' edit-command-line

          export SQLX_OFFLINE=true
        '';
        shellAliases = {
          g = "git";
          nxrb = "sudo darwin-rebuild switch --flake /Users/niko/projects/nixos/";
        };
      };
      programs.bash.enable = true;
    }

    ./programs/terminal/programs/opencode.nix
    ./programs/filemanager/yazi.nix
  ];

  home.stateVersion = "25.05";
}
