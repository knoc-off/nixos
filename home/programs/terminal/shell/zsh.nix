{ theme, pkgs, ... }: {
  programs.zsh = {
    enable = true;
    #dirHashes = {
    #  docs = "$HOME/Documents";
    #  dl = "$HOME/Downloads";
    #};
    oh-my-zsh.enable = true;

    sessionVariables = {
      ZSH_COLORIZE_TOOL = "chroma";
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=#${theme.base05}";
    };

    #shellAliases = { mnt = "${pkgs.udisks}/bin/udisksctl mount -b"; };

    initExtra = builtins.readFile ./zshrc.sh + ''
      # disable the awful vi mode
      bindkey -e

      # just a simple function to connect to wifi
      if [ -f /etc/secrets/gpt/secret ]; then
        export OPENAI_API_KEY=$(cat /etc/secrets/gpt/secret)
      fi

      ## DirEnv Config - should conditionally be enabled based on config.xyz
      # eval "$(direnv hook zsh)"

      ## Silence Direnv output:
      # export DIRENV_LOG_FORMAT=

      # Set the prompt to show the current directory:
      PS1=" %F{3}%3~ %f%# "

      # If ssh is executed from kitty it will auto copy the term info.
      # should move this to kitty config
      [ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"
    '';
  };
}
