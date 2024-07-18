{ theme, pkgs, ... }: {
  programs.zsh = {
    enable = true;
    dotDir = ".config/zsh";

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" "docker" "sudo" "command-not-found" ];
      theme = "robbyrussell";
    };

    sessionVariables = {
      ZSH_COLORIZE_TOOL = "chroma";
      ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE = "fg=#${theme.gray00}";
    };

    initExtra = builtins.readFile ./zshrc.sh + ''
      # disable the awful vi mode
      bindkey -e

      # just a simple function to connect to wifi
      if [ -f /etc/secrets/gpt/secret ]; then
        export OPENAI_API_KEY=$(cat /etc/secrets/gpt/secret)
      fi

      # Set the prompt to show the current directory:
      PS1=" %F{3}%3~ %f%# "

      # If ssh is executed from kitty it will auto copy the term info.
      [ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"

      zstyle ':completion:*:*:nix:*' completer _complete _ignored
      zstyle ':completion:*:*:nix:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|[._-]=* r:|=*'

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
          rev = "v0.5.0";
          sha256 = "sha256-qSobM4PRXjfsvoXY6ENqJGI9NEAaFFzlij6MPeTfT0o=";
        };
      }
      {
        name = "zsh-completions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-completions";
          rev = "0.34.0";
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
