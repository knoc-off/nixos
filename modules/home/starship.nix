{
  self,
  pkgs,
  lib,
  ...
}: let
  # Palette: one color per repo, derived by hashing the remote URL.
  branchColors = [
    "#e06c75" # soft red
    "#98c379" # green
    "#e5c07b" # warm yellow
    "#61afef" # blue
    "#c678dd" # purple
    "#56b6c2" # teal
    "#d19a66" # orange
    "#be5046" # brick
    "#7ec8e3" # sky blue
    "#c3e88d" # lime
    "#ffcb6b" # gold
    "#f78c6c" # coral
    "#bb80b3" # mauve
    "#89ddff" # cyan
    "#f07178" # pink
    "#82aaff" # periwinkle
  ];

  # Inline the palette as a Perl array literal: ("#rrggbb", "#rrggbb", ...)
  colorArrayPerl = "(${builtins.concatStringsSep ", " (map (c: "\"${c}\"") branchColors)})";

  # Single self-contained script: reads .git files directly (one git subprocess
  # to find the git dir, then pure file I/O) → hashes remote URL → prints
  # colored branch name with ANSI codes. No env vars, no extra processes.
  gitBranchColored = pkgs.writers.writePerlBin "git-branch-colored" {} ''
    use utf8;
    binmode STDOUT, ':utf8';

    my @colors = ${colorArrayPerl};

    my $gitdir = `git rev-parse --git-dir 2>/dev/null`;
    chomp $gitdir;
    exit 1 unless length $gitdir;

    open my $fh, '<', "$gitdir/HEAD" or exit 1;
    my $head = <$fh>; close $fh; chomp $head;
    my ($branch) = $head =~ m{^ref: refs/heads/(.+)$};
    $branch //= substr($head, 0, 8);

    my $url = 'local';
    if (open my $cfg, '<', "$gitdir/config") {
      my $in_origin = 0;
      while (<$cfg>) {
        $in_origin = 1 if /^\[remote "origin"\]/;
        $in_origin = 0 if $in_origin && /^\[/ && !/origin/;
        if ($in_origin && /url\s*=\s*(.+)/) { $url = $1; last }
      }
    }

    my $h = 5381;
    $h = (($h << 5) + $h + ord($_)) & 0xFFFFFFFF for split //, $url;
    my $idx = $h % scalar @colors;

    if (length($branch) > 25) {
      my $start = substr($branch, 0, 10);
      my $end   = substr($branch, -9);
      $branch = "$start\x{2026}$end";
    }

    my ($r, $g, $b) = map { hex } ($colors[$idx] =~ /^#(..)(..)(..)$/);

    printf "\e[1;38;2;%d;%d;%dm\x{f062c} %s\e[0m", $r, $g, $b, $branch;
  '';
in {
  imports = [
    self.homeModules.prompt-daemon
    {
      services.prompt-daemon = {
        enable = true;
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.prompt-daemon;
        daemon = {
          workers = 4;
          idle_timeout = "60s";
        };
        defaults = {
          shell = true;
          timeout = "5s";
        };
        commands = {
          git_branch = {
            run = "${gitBranchColored}/bin/git-branch-colored";
            watch = [".git/HEAD"];
            env = ["CWD"];
            exec_in_cwd = true;
          };
          rust_version = {
            run = "rustc --version | cut -d' ' -f2 | cut -d. -f1,2";
            check = "which rustc";
            check_interval = "2s";
            env = ["CWD" "PATH"];
            exec_in_cwd = true;
          };
        };
      };
    }
  ];

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {
      add_newline = false;

      format = "((($python )(\${custom.rust} )$nix_shell )(\${custom.git_branch} )\n)$directory( $cmd_duration)$line_break$character";

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

      rust.disabled = true;

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

      custom.rust = {
        command = "rust_version";
        use_stdin = false;
        shell = ["${self.packages.${pkgs.stdenv.hostPlatform.system}.prompt-daemon}/bin/prompt-client"];
        detect_files = ["Cargo.toml"];
        detect_extensions = ["rs"];
        style = "italic red";
        symbol = "";
        format = "([$symbol$output]($style))";
      };

      custom.git_branch = {
        command = "git_branch";
        use_stdin = false;
        shell = ["${self.packages.${pkgs.stdenv.hostPlatform.system}.prompt-daemon}/bin/prompt-client"];
        detect_folders = [".git"];
        when = "true";
        style = "";
        symbol = "";
        format = "$output";
      };
    };
  };
}
