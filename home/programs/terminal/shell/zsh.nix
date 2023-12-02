{ lib, pkgs, config, ... }:
{
  home.packages = with pkgs; [
    chroma # Required for colorize...
    qrencode
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
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=#${config.colorScheme.colors.base05}";
    };


    shellAliases = {
      rm = ''echo "use trash-cli instead"'';
      remove = ''/usr/bin/env rm'';
      tmux = "TERM=screen-256color tmux";
      sshk = "kitty +kitten ssh";
    };


    # append text to end of read file
    initExtra =
      builtins.readFile ./zshrc.sh +

      ''

        # Dont judge me too harshly... ai is useful.
        # if file exists, export the variable export OPENAI_API_KEY=
        if [ -f /etc/secrets/gpt/secret ]; then
          export OPENAI_API_KEY=$(cat /etc/secrets/gpt/secret)

        fi

        PS1=" %F{3}%3~ %f%# "

        ## DirEnv Config
        eval "$(direnv hook zsh)"

        # Silence Direnv output:
        export DIRENV_LOG_FORMAT=

      '';

    #oh-my-zsh.enable = true;
    #oh-my-zsh.plugins = [
    #  "colorize"
    #  "extract"
    #  "fancy-ctrl-z"
    #  "fd"
    #  "mosh"
    #];
  };
}
