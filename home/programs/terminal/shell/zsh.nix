{ lib, theme, pkgs, config, ... }:
{
  programs.zsh = {
    enable = true;
    #enableAutosuggestions = true; # i dont like this too much. seems to mess with me more than help

    dirHashes = {
      # Will shorten the supplied path, to the variable name.
      docs = "$HOME/Documents";
      dl = "$HOME/Downloads";
    };
    oh-my-zsh.enable = true;

    sessionVariables = {
      ZSH_COLORIZE_TOOL = "chroma";
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=#${theme.base05}"; # 05-07 for white
    };


    shellAliases = {
      remove = ''/usr/bin/env rm'';
      sshk = "kitty +kitten ssh";
      mnt = "${pkgs.udisks}/bin/udisksctl mount -b";
    };


    # append text to end of read file
    initExtra =
      builtins.readFile ./zshrc.sh +
      ''
        # disable the awful vi mode
        bindkey -e

        compress() {
            tar -cf - "$1" | pv -s $(du -sb "$1" | awk '{print $1}') | pigz -9 > "$2".tar.gz
        }

        nixx () {
            nix run nixpkgs#$1 -- "$\{@:2}"
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
