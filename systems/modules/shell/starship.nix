{
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;

      # Using conditional format string for line break
      format = "(($python )($rust )$nix_shell\n)$directory( $cmd_duration)$line_break$character";
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

      git_branch = {
        symbol = "󰘬 ";
        style = "bold purple";
        format = "[$symbol$branch]($style)";
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
        # Format with parentheses
        format = "([(\($name\))]($style))";
        style = "bold blue";
        heuristic = true;
      };

      python = {
        symbol = "py ";
        version_format = "$major.$minor";
        # Format with parentheses
        format = "([$symbol$version]($style))";
        style = "italic yellow";
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" "pyproject.toml" "setup.py"];
        detect_folders = [".venv" "venv"];
      };

      rust = {
        symbol = "rs ";
        version_format = "$major.$minor";
        # Format with parentheses
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
    };
  };
}

