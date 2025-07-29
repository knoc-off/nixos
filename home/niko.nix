{
  pkgs,
  upkgs,
  self,
  ...
}: {
  # test
  imports = [
    ./programs/terminal/kitty
    ./programs/terminal
    #./programs/terminal/shell/scripts.nix
    # {
    #   home.packages = let
    #     inherit (self.packages.${pkgs.system}) mkComplgenScript;
    #   in [
    #     self.packages.${pkgs.system}.cli-ai
    #     pkgs.television
    #     #(mkComplgenScript {
    #     #  name = "cli";
    #     #  # TODO, we should instruct the model, to create a xml-tag like <clip> </clip> that we then copy to the clipboard
    #     #  # pbcopy/wl-copy
    #     #  scriptContent = ''
    #     #    #!${pkgs.bash}/bin/bash
    #     #    set -euo pipefail
    #     #    if [ $# -eq 0 ]; then
    #     #      echo "Usage: cli <command> [args...]"
    #     #      exit 1
    #     #    fi
    #     #    fabric -p cli "$@" --stream
    #     #  '';
    #     #  grammar = ''
    #     #    cli <COMMAND> "Command to run" ...;
    #     #  '';
    #     #  runtimeDeps = [pkgs.fabric-ai];
    #     #})

    #     (mkComplgenScript {
    #       name = "adr";
    #       scriptContent = ''
    #         #!${pkgs.bash}/bin/bash
    #         set -euo pipefail

    #         SMART_MODEL="openrouter/google/gemini-2.5-pro-preview-03-25"
    #         FAST_MODEL="openrouter/google/gemini-2.5-flash-preview"
    #         MEDIUM_MODEL="openrouter/google/gemini-2.5-flash-preview:thinking"
    #         MODEL="$FAST_MODEL"
    #         WEAK_MODEL="$FAST_MODEL"
    #         AIDER_ARGS=() # Renamed from ARGS to avoid confusion with shell ARGS

    #         # Parse flags and file/other arguments
    #         while [ $# -gt 0 ]; do
    #           case "$1" in
    #             -s) MODEL="$SMART_MODEL"; shift ;;
    #             -m) MODEL="$MEDIUM_MODEL"; shift ;;
    #             -d) MODEL="$FAST_MODEL"; shift ;;
    #             *) AIDER_ARGS+=("$1"); shift ;;
    #           esac
    #         done

    #         if [ ''${#AIDER_ARGS[@]} -eq 0 ]; then
    #           AIDER_ARGS=("--message" "/commit")
    #         fi

    #         ${upkgs.aider-chat}/bin/aider \
    #           --alias "f:$FAST_MODEL" \
    #           --alias "m:$MEDIUM_MODEL" \
    #           --alias "s:$SMART_MODEL" \
    #           --alias "fast:$FAST_MODEL" \
    #           --alias "smart:$SMART_MODEL" \
    #           --alias "medium:$MEDIUM_MODEL" \
    #           --model "$MODEL" \
    #           --weak-model "$WEAK_MODEL" \
    #           --no-auto-lint \
    #           --no-auto-test \
    #           --no-attribute-committer \
    #           --no-attribute-author \
    #           --dark-mode \
    #           --edit-format diff \
    #           "''${AIDER_ARGS[@]}"
    #       '';
    #       # Corrected grammar:
    #       # grammar = ''
    #       #   adr [(-s | -m | -d)] [{{{${pkgs.fd}/bin/fd --type f --hidden --no-ignore --max-depth 1 . --color never}}} "File"] ... [<OTHER_ARG> "Other Argument"] ... ;'';
    #       grammar = ''
    #         adr <PATH>;
    #       '';
    #       runtimeDeps = [
    #         upkgs.aider-chat
    #         pkgs.fd
    #         pkgs.file # For file type detection in completion
    #         pkgs.gnugrep # For grep in completion
    #         pkgs.bash # For the script itself
    #       ];
    #     })
    #   ];
    # }

    ./programs/browser/firefox/default.nix

    #./programs/terminal/shell
    ./programs/terminal/shell/fish.nix
    {
      targets.darwin.defaults."com.apple.finder".ShowPathBar = true;

      home.packages = with pkgs; [
        _1password-gui
        _1password-cli
        gum
      ];
      programs.zsh = {
        enable = true;
        initContent = ''
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^[[101;9u' edit-command-line
        '';
      };
      programs.bash.enable = true;
      programs.starship = {
        enable = true;
        enableZshIntegration = true;
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
            symbol = "";
            version_format = "$major.$minor";
            # Format with parentheses
            format = "([$symbol$version]($style))";
            style = "italic yellow";
            detect_extensions = ["py"];
            detect_files = ["requirements.txt" "pyproject.toml" "setup.py"];
            detect_folders = [".venv" "venv"];
          };

          rust = {
            symbol = "";
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

    ./programs/filemanager/yazi.nix
  ];
  home.stateVersion = "25.05";
}
