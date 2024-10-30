{ pkgs, ... }: {
  programs.bash = {
    enable = true;

    # History settings
    historySize = 10000;
    historyFileSize = 20000;
    historyControl = [ "erasedups" ];

    # Shell options
    shellOptions = [
      "histappend"
      "checkwinsize"
      "extglob"
      "globstar"
      "checkjobs"
      "autocd"
      "cdspell"
    ];

    # Extra initialization commands
    initExtra = ''
      if [ -f ~/.profile ]; then
        . ~/.profile
      fi
      echo "realpath ~/.profile"


      # Improved command line editing
      bind 'set show-all-if-ambiguous on'
      bind 'set show-all-if-unmodified on'
      bind 'set completion-ignore-case on'
      bind 'set menu-complete-display-prefix on'
      bind '"\t": menu-complete'
      bind '"\e[Z": menu-complete-backward'
      bind 'set colored-stats on'
      bind 'set visible-stats on'
      bind 'set mark-symlinked-directories on'
      bind 'set colored-completion-prefix on'
      bind 'set menu-complete-display-prefix on'

      # Custom key bindings
      bind '"\C-w":backward-kill-word'

      # Fuzzy finder configuration
      if command -v fzf >/dev/null; then
        source ${pkgs.fzf}/share/fzf/completion.bash
        source ${pkgs.fzf}/share/fzf/key-bindings.bash
      fi

      # Syntax highlighting for less
      export LESSOPEN="| ${pkgs.sourceHighlight}/bin/src-hilite-lesspipe.sh %s"
      export LESS=' -R '

      # Improved directory navigation with zoxide
      eval "$(${pkgs.zoxide}/bin/zoxide init bash)"
    '';

    # Enable bash completion
    enableCompletion = true;
  };
}
