{
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$nodejs$python$rust$nix_shell$line_break$character";

      scan_timeout = 10;
      command_timeout = 500;

      character = {
        success_symbol = "[λ](bold green)";
        error_symbol = "[✗](bold red)";
        vimcmd_symbol = "[ν](bold blue)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        style = "bold cyan";
        format = "[$path]($style) ";
        repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style) ";
        repo_root_style = "underline bold cyan";
      };

      git_branch = {
        symbol = "󰘬 ";
        style = "bold purple";
        format = "[$symbol$branch]($style) ";
      };

      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
        ahead = "⇡${"\${count}"}";
        diverged = "⇕⇡${"\${ahead_count}"}⇣${"\${behind_count}"}";
        behind = "⇣${"\${count}"}";
        modified = "!${"\${count}"}";
        staged = "+${"\${count}"}";
        renamed = "»${"\${count}"}";
        deleted = "✘${"\${count}"}";
        style = "bold yellow";
      };

      nix_shell = {
        symbol = "❄️ ";
        format = "[$symbol$state( \($name\))]($style) ";
        style = "bold blue";
        heuristic = true;
      };

      python = {
        symbol = "󰌠 ";
        format = "[$symbol($version )]($style)";
        style = "bold yellow";
        detect_extensions = ["py"];
        detect_files = ["requirements.txt" "pyproject.toml" "setup.py"];
        detect_folders = [".venv" "venv"];
      };

      rust = {
        symbol = "󱘗 ";
        format = "[$symbol($version )]($style)";
        style = "bold red";
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml"];
      };

      cmd_duration = {
        min_time = 500;
        format = "[$duration]($style) ";
        style = "bold yellow";
        show_milliseconds = false;
      };
    };
  };
}

