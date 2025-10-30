{...}: {
  programs.git = {
    enable = true;

    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.excludesfile = "~/.gitignore_global";
    };

    aliases = {
      ca = "commit --amend";
      caa = "commit --all --amend";
      c = "commit";

      s = "status --short --branch";

      pf = "push --force-with-lease";
      p = "push";
      a = "add";
      d = ''!f() { git diff HEAD~''${1:-0} --; }; f'';

      co = "checkout";
      br = "branch";
      l = "log --oneline --graph --decorate -10";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";

      # list last 10 branches checked out.
      lb = "!git reflog | grep -o 'checkout: moving from .* to .*' | sed 's/checkout: moving from .* to //' | awk '!seen[$0]++' | head -10";

      # See changes since branching off of main branch
      ch = ''diff --merge-base origin/HEAD'';
    };
    # signing = {
    #   key = "your-key-id";
    #   format = "ssh";
    #   signByDefault = true;
    # };

    delta = {
      enable = true;
      options = {
        # Navigation
        navigate = true; # Use n/N to jump between files Amazing

        file-regex = "^(?!.*lock$).*"; # maybe?

        # Display
        side-by-side = true;
        line-numbers = true;

        syntax-theme = "Visual Studio Dark+";

        file-style = "bold yellow ul";
        file-decoration-style = "none";

        hunk-header-decoration-style = "blue box";
        hunk-header-file-style = "red";
        hunk-header-line-number-style = "#067a00";
        hunk-header-style = "file line-number syntax";

        whitespace-error-style = "22 reverse";
      };
    };
  };
}
