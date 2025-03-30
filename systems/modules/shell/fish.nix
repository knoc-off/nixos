{ config, lib, pkgs, user, ... }: # TODO: make all of the special arguments default? its better if it hard fails
{
  imports = [
    ./starship.nix
  ];

  users.defaultUserShell = pkgs.fish;
  users.users.${user}.shell = pkgs.fish;

  environment.variables = {
    EDITOR = "vi";
    VISUAL = "vi";
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
    #   # Terminal title
    #   function fish_title
    #     set -q argv[1]; or set argv fish
    #     echo (status current-command) " "
    #     pwd
    #   end

    #   # Better history search
    #   function history-search
    #     history | fzf --height=40% | read -l command
    #     and commandline -rb $command
    #   end
    #   bind \cr history-search


    function __newline
        commandline -i "\n"
    end

    #   bind \n __newline

    #   function __edit_command
    #       set -l tmpfile (mktemp)
    #       commandline > $tmpfile
    #       $EDITOR $tmpfile
    #       commandline -r (cat $tmpfile)
    #       commandline -f repaint
    #       rm $tmpfile
    #   end


    #   # Set key bindings
    #   bind -M insert \e\n __newline  # Alt-Enter for newline
    #   bind -M insert \cr history-search
    #   bind -M insert \ee __edit_command  # Alt-e for editor



    '';

    shellAbbrs = {
      l = "eza -l --group-directories-first --git";
      la = "eza -la --group-directories-first --git";
      lt = "eza --tree --level=2";
      g = "git";
      nrs = "sudo nixos-rebuild switch";
      ncg = "nix-collect-garbage -d";
    };

    shellAliases = {
      wgnord = "sudo ${pkgs.wgnord}/bin/wgnord";
      cat = "bat";
    };
  };

  # These packages are required for the Fish configuration to work properly
  environment.systemPackages = with pkgs; [
    eza        # Modern replacement for ls with more features and better defaults
    bat        # Cat clone with syntax highlighting
    zoxide     # Smarter cd command that learns your habits
    fzf        # Command-line fuzzy finder
    ripgrep    # Fast grep alternative
    fd         # User-friendly alternative to find
  ];
}

