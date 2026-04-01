{
  self,
  pkgs,
  lib,
  ...
}: let
  branchColors = [
    "#e06c75"
    "#98c379"
    "#e5c07b"
    "#61afef"
    "#c678dd"
    "#56b6c2"
    "#d19a66"
    "#be5046"
    "#7ec8e3"
    "#c3e88d"
    "#ffcb6b"
    "#f78c6c"
    "#bb80b3"
    "#89ddff"
    "#f07178"
    "#82aaff"
  ];

  colorArrayPerl = "(${builtins.concatStringsSep ", " (map (c: "\"${c}\"") branchColors)})";

  # Single self-contained script: reads .git files directly (one git subprocess
  # to find the git dir, then pure file I/O) -> hashes remote URL -> prints
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

    # Strip ticket prefix (e.g. INT-2895-) for display
    (my $display = $branch) =~ s/^[A-Z]+-\d+-//i;

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

    if (length($display) > 25) {
      my $start = substr($display, 0, 10);
      my $end   = substr($display, -9);
      $display = "$start\x{2026}$end";
    }

    my ($r, $g, $b) = map { hex } ($colors[$idx] =~ /^#(..)(..)(..)$/);

    printf "\e[1;38;2;%d;%d;%dm%s\e[0m", $r, $g, $b, $display;
  '';

  linearTicket = pkgs.writeShellScriptBin "linear-ticket" ''
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
    ticket=$(echo "$branch" | grep -oiP '^[A-Z]+-\d+') || exit 0

    json=$(linear i v "$ticket" -j 2>/dev/null) || exit 0

    state_color=$(echo "$json" | jq -r '.state.color // empty')
    linear_url=$(echo "$json" | jq -r '.url // empty')
    [ -z "$state_color" ] || [ -z "$linear_url" ] && exit 0

    r=$(printf '%d' "0x''${state_color:1:2}")
    g=$(printf '%d' "0x''${state_color:3:2}")
    b=$(printf '%d' "0x''${state_color:5:2}")

    printf '\e[38;2;%d;%d;%dm\e]8;;%s\e\\● %s\e]8;;\e\\\e[0m' \
      "$r" "$g" "$b" "$linear_url" "$ticket"
  '';

  upstreamLink = pkgs.writeShellScriptBin "upstream-link" ''
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
    remote_url=$(git remote get-url origin 2>/dev/null) || exit 0
    repo=$(echo "$remote_url" | sed -E 's|.*github\.com[:/]||; s|\.git$||')

    json=$(${pkgs.gh}/bin/gh pr view --json url,state 2>/dev/null) || {
      create_url="https://github.com/$repo/compare/$branch?expand=1"
      printf '\e[2;37m\e]8;;%s\e\\󰘬\e]8;;\e\\\e[0m' "$create_url"
      exit 0
    }

    url=$(echo "$json" | jq -r '.url' | tr -d '\n')
    state=$(echo "$json" | jq -r '.state' | tr -d '\n')
    case "$state" in
      MERGED) color="38;2;163;113;247" ;;
      OPEN)   color="38;2;63;185;80"   ;;
      *)      color="38;2;128;128;128" ;;
    esac

    printf '\e[%sm\e]8;;%s\e\\󰘬\e]8;;\e\\\e[0m' "$color" "$url"
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
            env = ["CWD" "PATH"];
            exec_in_cwd = true;
          };
          linear_ticket = {
            run = "${linearTicket}/bin/linear-ticket"; # or the resolved store path;
            check = "git rev-parse --abbrev-ref HEAD";
            check_interval = "5m";
            watch = [".git/HEAD"];
            env = ["CWD"];
            exec_in_cwd = true;
            idle_timeout = "30m";
          };
          upstream_link = {
            run = "${upstreamLink}/bin/upstream-link";
            check = "git rev-parse --abbrev-ref HEAD";
            check_interval = "5m";
            interval = "5m"; # also poll — PR might be created while on the same branch;
            watch = [".git/HEAD"];
            env = ["CWD"];
            exec_in_cwd = true;
            idle_timeout = "30m";
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

      # format = "((($python )(\${custom.rust} )$nix_shell )(\${custom.upstream_link} (\${custom.linear_ticket}-)\${custom.git_branch} )\n)$directory( $cmd_duration)$line_break$character";
      format = "((($python )(\${custom.rust} )$nix_shell )(\${custom.upstream_link} (\${custom.linear_ticket}-)\${custom.git_branch} )\n)$directory( $cmd_duration)$line_break$character";
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
      custom.linear_ticket = {
        command = "linear_ticket";
        use_stdin = false;
        shell = ["${self.packages.${pkgs.stdenv.hostPlatform.system}.prompt-daemon}/bin/prompt-client"];
        detect_folders = [".git"];
        when = "true";
        style = "";
        symbol = "";
        format = "$output";
      };
      custom.upstream_link = {
        command = "upstream_link";
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
