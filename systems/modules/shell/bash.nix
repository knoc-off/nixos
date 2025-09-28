{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.bash = {
    shellAliases = {
      wgnord = "sudo ${pkgs.wgnord}/bin/wgnord";
    };
    interactiveShellInit = ''
      if [ -f ~/.profile ]; then
        . ~/.profile
      fi

      # History settings
      export HISTSIZE=10000
      export HISTFILESIZE=20000
      export HISTCONTROL=ignoreboth:erasedups
      shopt -s histappend
      shopt -s autocd
      shopt -s cdspell

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

      # Syntax highlighting using 'sourceHighlight'
      export LESSOPEN="| ${pkgs.sourceHighlight}/bin/src-hilite-lesspipe.sh %s"
      export LESS=' -R '

      # Improved directory navigation
      eval "$(${pkgs.zoxide}/bin/zoxide init bash)"

      # Load bash-completion if available
      [[ $PS1 && -f ${pkgs.bash-completion}/share/bash-completion/bash_completion ]] && \
        . ${pkgs.bash-completion}/share/bash-completion/bash_completion

      # Enable programmable completion features
      if ! shopt -oq posix; then
        if [ -f /usr/share/bash-completion/bash_completion ]; then
          . /usr/share/bash-completion/bash_completion
        elif [ -f /etc/bash_completion ]; then
          . /etc/bash_completion
        fi
      fi
    '';
  };

  environment.variables = {
    EDITOR = "vi";
    VISUAL = "vi";
  };

  # Install useful tools
  environment.systemPackages = with pkgs; [
    fzf # Fuzzy finder
    ripgrep # Fast grep alternative
    eza # Modern ls alternative
    bat # Cat clone with syntax highlighting
    fd # Find alternative
    zoxide # Smarter cd command
    sourceHighlight # For syntax highlighting in less
    bash-completion # For better command completion
  ];
}
