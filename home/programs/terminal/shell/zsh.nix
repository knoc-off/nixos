{ lib, theme, pkgs, config, ... }:
{
  home.packages = with pkgs; [
    chroma # Required for colorize...
    qrencode
    fd
    fzf
    rg
  ];

  programs.zsh = {
    enable = true;
    #enableAutosuggestions = true; # i dont like this too much. seems to mess with me more than help

    dirHashes = {
      # Will shorten the supplied path, to the variable name.
      docs = "$HOME/Documents";
      dl = "$HOME/Downloads";
    };


    sessionVariables = {
      ZSH_COLORIZE_TOOL = "chroma";
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=#${theme.base05}"; # 05-07 for white
    };


    shellAliases = {
      remove = ''/usr/bin/env rm'';
      sshk = "kitty +kitten ssh";
    };


    # append text to end of read file
    initExtra =
      builtins.readFile ./zshrc.sh +
      ''

        nixx () {
            nix shell nixpkgs#$1 --command $1 "$\{@:2}"
        }

        chrome() {
          nix shell nixpkgs#ungoogled-chromium --command chromium $1 &>/dev/null &
        }

        # just a simple function to connect to wifi
        connect() {
          echo "nmcli device wifi rescan"
          nmcli device wifi rescan
          echo "nmcli device wifi connect $@"
          nmcli device wifi connect $@
        }


        # Dont judge me too harshly... ai is useful.
        if [ -f /etc/secrets/gpt/secret ]; then
          export OPENAI_API_KEY=$(cat /etc/secrets/gpt/secret)
        fi

        ## DirEnv Config
        eval "$(direnv hook zsh)"

        # Silence Direnv output:
        export DIRENV_LOG_FORMAT=

        # Set the prompt to show the current directory:
        PS1=" %F{3}%3~ %f%# "

        # If ssh is executed from kitty it will auto copy the term info.
        # should move this to kitty config
        [ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"

      '';
  };
}
