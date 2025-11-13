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
      r = ''!f() { git rebase -i HEAD~''${1:-0} --; }; f'';
      l = ''!f() { git log --oneline --graph --decorate -''${1:-10}; }; f'';
      #l = "log --oneline --graph --decorate -10";

      co = "checkout";
      br = "branch";
      #l = "log --oneline --graph --decorate -10";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";

      # list last 10 branches checked out.
      lb = "!git reflog | grep -o 'checkout: moving from .* to .*' | sed 's/checkout: moving from .* to //' | awk '!seen[$0]++' | head -10";

      # See changes since branching off of main branch
      ch = ''diff --merge-base origin/HEAD'';

      # Comprehensive overview of changes without showing diff content
      changes = ''!f() {
        echo "=== Repository Overview ===";
        echo "";
        git status --short --branch;
        echo "";

        # Find merge base with main/origin/main
        current_branch=$(git branch --show-current);
        merge_base="";
        if git show-ref --verify --quiet refs/remotes/origin/main; then
          merge_base=$(git merge-base HEAD origin/main 2>/dev/null);
        elif git show-ref --verify --quiet refs/heads/main; then
          merge_base=$(git merge-base HEAD main 2>/dev/null);
        fi;

        if [ -n "$merge_base" ] && [ "$current_branch" != "main" ]; then
          commit_count=$(git rev-list --count $merge_base..HEAD);
          if [ "$commit_count" -gt 0 ]; then
            echo "=== Changes Since Split From Main ($commit_count commits) ===";
            echo "";
            git log --graph --pretty=format:"%h - %ad - %an: %s" --date=short --stat --color=always $merge_base..HEAD | sed "s/^/ /";
          else
            echo "=== No Changes Since Split From Main ===";
          fi;
        else
          echo "=== Recent Changes (last ''${1:-10} commits) ===";
          echo "";
          git log --graph --pretty=format:"%h - %ad - %an: %s" --date=short --stat --color=always -''${1:-10} | sed "s/^/ /";
        fi;

        echo "";
        if [ -n "$(git status --porcelain)" ]; then
          echo "=== Uncommitted Changes ===";
          echo "";
          git status --short | sed "s/^/  /";
          echo "";
        fi;
        echo "=== Branch Information ===";
        echo "Current: $(git branch --show-current)";
        echo "Tracking: $(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo 'No upstream')";
        if [ -n "$merge_base" ] && [ "$current_branch" != "main" ]; then
          echo "Merge base: $(git log --oneline -1 $merge_base)";
        fi;
        echo "";
      }; f'';
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
