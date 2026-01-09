{
  theme,
  pkgs,
  ...
}: {
  programs.zsh = {
    enable = true;

    sessionVariables = {
      ZSH_COLORIZE_TOOL = "chroma";
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=#${theme.gray00}";
      MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    };

    initExtra =
      builtins.readFile ./zshrc.sh
      + ''
        # disable the awful vi mode
        bindkey -e

        if [ -f /etc/secrets/gpt/secret ]; then
          export OPENAI_API_KEY=$(cat /etc/secrets/gpt/secret)
        fi

        # Set the prompt to show the current directory:
        PS1=" %F{3}%3~ %f%# "

        # Note: Removed kitty SSH kitten integration
        # Kitty had: automatic terminfo copying via `kitty +kitten ssh`
        # Ghostty: uses standard SSH, manual terminfo setup if needed

        zstyle ':completion:*:*:nix:*' completer _complete _ignored
        zstyle ':completion:*:*:nix:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|[._-]=* r:|=*'

        # Set up fzf key bindings and fuzzy completion
        if [ -n "${pkgs.fzf}/share/fzf" ]; then
          source "${pkgs.fzf}/share/fzf/key-bindings.zsh"
          source "${pkgs.fzf}/share/fzf/completion.zsh"
        fi

        # Beginning search with arrow keys
        #bindkey "^[OA" up-line-or-beginning-search
        #bindkey "^[OB" down-line-or-beginning-search

        bindkey "^[[1;5C" forward-word   # Ctrl+Right
        bindkey "^[[1;5D" backward-word  # Ctrl+Left


        cl() {
            printf '\x1b]1337;SetUserVar=in_claude=MQ==\007'
            command claude "$@"
            local exit_code=$?
            printf '\x1b]1337;SetUserVar=in_claude\007'
            return $exit_code
        }

      '';

    # Enable syntax highlighting
    syntaxHighlighting.enable = true;

    # Enable autosuggestions
    autosuggestion.enable = true;

    # Enable command-not-found functionality
    enableCompletion = true;

    # History configuration
    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
      expireDuplicatesFirst = true;
      share = true;
    };

    # Additional useful plugins
    plugins = [
      {
        name = "zsh-nix-shell";
        file = "nix-shell.plugin.zsh";
        src = pkgs.fetchFromGitHub {
          owner = "chisui";
          repo = "zsh-nix-shell";
          rev = "v0.8.0";
          sha256 = "sha256-qSobM4PRXjfsvoXY6ENqJGI9NEAaFFzlij6MPeTfT0o=";
        };
      }
    ];

    # Useful aliases
    shellAliases = {
      ll = "ls -l";
      la = "ls -la";
      ".." = "cd ..";
      "..." = "cd ../..";
      update = "sudo nixos-rebuild switch";
      grep = "grep --color=auto";
      diff = "diff --color=auto";
    };

    # Directory hashes for quick navigation
    dirHashes = {
      docs = "$HOME/Documents";
      dl = "$HOME/Downloads";
      projects = "$HOME/Projects";
    };
  };
}
