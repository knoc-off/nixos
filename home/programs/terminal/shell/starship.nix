{
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$line_break$nix_shell$character";

      scan_timeout = 10;

      character = {
        success_symbol = "[->](bold green)";
        error_symbol = "[~>](bold red)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };

      git_branch = {
        symbol = "🌱 ";
        style = "bold green";
      };

      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
        ahead = "⇡${"\${count}"}";
        diverged = "⇕⇡${"\${ahead_count}"}⇣${"\${behind_count}"}";
        behind = "⇣${"\${count}"}";
        style = "bold red";
      };

      nix_shell = {
        symbol = "❄️ ";
        format = "[$symbol$state( \($name\))]($style) ";
        style = "bold blue";
      };

      nodejs = {
        format = "[$symbol($version )]($style)";
        style = "bold green";
      };

      cmd_duration = {
        min_time = 500;
        format = "[$duration]($style) ";
        style = "yellow";
      };
    };
  };
}
