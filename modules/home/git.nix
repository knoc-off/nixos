{...}: {
  programs.git = {
    enable = true;

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };

    aliases = {
      # Commit aliases
      ca = "commit --amend";
      caa = "commit -a --amend";
      c = "commit -a";

      # Push aliases
      pf = "push --force-with-lease";

      # Other useful aliases
      st = "status";
      co = "checkout";
      br = "branch";
      l = "log --oneline --graph --decorate -5";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      # See changes since branching off of main branch
      changes = ''diff --merge-base origin/main'';
    };
    # signing = {
    #   key = "your-key-id";
    #   format = "ssh";
    #   signByDefault = true;
    # };

    delta = {
      enable = true;

      # Optional: specify a different delta package
      # package = pkgs.delta;

      options = {
        # Navigation
        navigate = true; # Use n/N to jump between files Amazing

        file-regex = "^(?!.*lock$).*"; # maybe?

        # Display
        side-by-side = true; # Show diffs side by side
        line-numbers = true; # Show line numbers

        # Syntax highlighting
        syntax-theme = "Visual Studio Dark+"; # Or "GitHub", "Monokai Extended", etc.

        # Better file headers
        file-style = "bold yellow ul";
        file-decoration-style = "none";

        # Hunk headers
        hunk-header-decoration-style = "blue box";
        hunk-header-file-style = "red";
        hunk-header-line-number-style = "#067a00";
        hunk-header-style = "file line-number syntax";

        # Line styles
        #minus-style = "red bold";
        #plus-style = "green bold";

        # Whitespace
        whitespace-error-style = "22 reverse";
      };
      # options = {
      #   # Example delta options - customize as needed
      #   features = "decorations";
      #   whitespace-error-style = "22 reverse";
      #   decorations = {
      #     commit-decoration-style = "bold yellow box ul";
      #     file-style = "bold yellow ul";
      #     file-decoration-style = "none";
      #   };
      # };
    };
  };
}
