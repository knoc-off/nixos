{pkgs, ...}: {
  # I want to add the ability to see the git-stash, and if there is uncommitted changes.
  # it would be pretty cool to show each stash based on its hash condensed into a single letter.
  # we would want to then make sure they dont repeat.
  # maybe just A-Z. and show them in a queue, next to git data. <git_branch_short> <untracked_files_status> A B C D
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = false;

      # Using conditional format string for line break
      format = ''((($python )($rust )$nix_shell )''${custom.git_branch_short} ''\n)$directory( $cmd_duration)$line_break$character'';

      #format = "(($python )($rust )$nix_shell '${custom.git_branch_short}\n)$directory( $cmd_duration)$line_break$character";
      #format = "$directory$git_branch$git_status$cmd_duration$nodejs$python$rust$nix_shell$line_break$character";

      scan_timeout = 10;
      command_timeout = 500;

      character = {
        success_symbol = "[>](bold green)";
        error_symbol = "[>](bold red)";
        vimcmd_symbol = "[ν](bold blue)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
        format = "[$path]($style)";
        repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)";
        repo_root_style = "underline bold cyan";
      };

      git_status = {
        format = "[[($staged$modified$untracked )](bold yellow) ±$ahead_behind]($style) ";
        staged = "+$count";
        modified = "~$count";
        untracked = "…$count";
        ahead = " ⇡$count";
        behind = " ⇣$count";
        diverged = " ⇵ $ahead_count⇣$behind_count";
        style = "bold yellow";
        disabled = false;
      };

      nix_shell = {
        symbol = "*";
        format = "([(\($name\))]($style))";
        style = "bold blue";
        heuristic = true;
      };

      python = {
        symbol = "";
        version_format = "$major.$minor";
        format = "([$symbol$version]($style))";
        style = "italic yellow";
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" "pyproject.toml" "setup.py"];
        detect_folders = [".venv" "venv"];
      };

      rust = {
        symbol = "";
        version_format = "$major.$minor";
        format = "([$symbol$version]($style))";
        style = "italic red";
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml"];
      };

      cmd_duration = {
        min_time = 500;
        format = "[$duration]($style)";
        style = "bold green";
        show_milliseconds = false;
      };

      git_branch = {
        symbol = "󰘬 ";
        style = "bold purple";
        format = "[$symbol$branch]($style)";
      };

      custom.git_branch_short = {
        command = let
          # script:
          git_branch_short_sh = pkgs.writeShellScript "git-branch-short" ''
            #!/usr/bin/env bash
            git rev-parse --abbrev-ref HEAD 2> /dev/null | awk '
              {
                  max_len = 25
                  first_chars = 10
                  first_boundary = 3
                  last_chars = 9
                  last_boundary = 3

                  if (length($0) <= max_len) {
                      print $0
                  } else {
                      # Find word boundary after first_chars (up to +first_boundary)
                      start_idx = first_chars
                      for (i = first_chars + 1; i <= first_chars + first_boundary && i <= length($0); i++) {
                          if (substr($0, i, 1) ~ /[^a-zA-Z0-9]/) {
                              start_idx = i - 1
                              break
                          }
                      }
                      start_part = substr($0, 1, start_idx)

                      # Find word boundary before last_chars (up to -last_boundary)
                      end_idx = length($0) - last_chars + 1
                      for (i = end_idx - 1; i >= end_idx - last_boundary && i > 0; i--) {
                          if (substr($0, i, 1) ~ /[^a-zA-Z0-9]/) {
                              end_idx = i + 1
                              break
                          }
                      }
                      end_part = substr($0, end_idx, length($0) - end_idx + 1)

                      print start_part "…" end_part
                  }
              }'
          '';
        in "${git_branch_short_sh}";
        when = "git rev-parse --is-inside-work-tree 2>/dev/null | grep -q true";
        style = "bold purple";
        symbol = "󰘬 ";
        format = "[$symbol$output]($style)";
      };
    };
  };
}
