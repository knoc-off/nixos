{ pkgs, self, ... }:
let
  config_dir = "/etc/nixos"; # Should relocate to /etc? and symlink?
  config_name = "framework13";
  inherit (self.packages.${pkgs.system}) writeNuScript;
in {
  home.packages = [
    (pkgs.writeShellScriptBin "nx" ''
      #!/usr/bin/env bash
      set -e

      force_flag=false
      args=("$@")

      # Check if -f flag is present
      for arg in "$@"; do
        if [[ $arg == "-f" ]]; then
          force_flag=true
          break
        fi
      done

      # Remove -f from args if present
      args=(''${args[@]/-f/})

      case "''${args[0]}" in
        "rb")
          cd "${config_dir}"

          if [[ $(git status --porcelain) != "" && $force_flag == false ]]; then
            echo "git is dirty"
            exit 1
          fi

          echo "force rebuild"
          sudo nixos-rebuild switch --flake "${config_dir}#${config_name}"
          ;;
        "rt")
          sudo nixos-rebuild test --flake "${config_dir}#${config_name}"
          ;;
        "cr")
          nix repl --extra-experimental-features repl-flake "${config_dir}#nixosConfigurations.${config_name}"
          ;;
        "vm")
          sudo nixos-rebuild build-vm --flake "${config_dir}#${config_name}"
          ;;
        "cd")
          query="''${args[@]:1}"
          file=$(fd . "${config_dir}" --type=d -E .git -H | fzf --query "$query")
          if [[ -d $file ]]; then
            echo "$file"
            cd "$file"
          fi
          ;;
        *)
          query="''${args[@]}"
          file=$(fd . "${config_dir}" -e nix -E .git -H | fzf --query "$query")
          if [[ -f $file ]]; then
            echo "$file"
            nvim "$file"
          fi
          ;;
      esac
    '')

    (writeNuScript "nixx" ''
      def main [
        --sudo (-s): bool,  # Run the command with sudo
        --bg (-b): bool,    # Run the command in the background
        package: string,    # The Nix package to run
        ...args: string     # Additional arguments for the command
      ] {
        mut command = []

        if $sudo and $bg {
          echo "Warning: Using sudo with background tasks may require manual authentication"
        }

        if $bg {
          $command = ($command | append ["pueue", "add"])
        }

        $command = ($command | append [
          "env",
          "NIXPKGS_ALLOW_UNFREE=1",
          "nix",
          "shell",
          "--impure",
          $"nixpkgs#($package)",
          "--command"
        ])

        if $sudo {
          $command = ($command | append "sudo")
        }

        $command = ($command | append $package)
        $command = ($command | append $args)

        let command_str = ($command | str join " ")

        if $bg {
          let task_id = (^$nu.current-exe -c $command_str | parse "{id}")
          pueue follow $task_id
        } else {
          ^$nu.current-exe -c $command_str
        }
      }
    '')

    (pkgs.writeShellScriptBin "gen-git-msg" ''
      git diff HEAD | llm "from the text extract only important changes to craft a concise and simple git commit message, formatted like this:
      <Title of the git commit>

      <body, Details of the commit>"
    '')

    (pkgs.writeShellScriptBin "compress" ''
      tar -cf - "$1" | pv -s $(du -sb "$1" | awk '{print $1}') | pigz -9 > "$2".tar.gz
    '')
    (pkgs.writeShellScriptBin "chrome" ''
      nix shell nixpkgs#ungoogled-chromium --command chromium $1 &>/dev/null &
    '')
    (pkgs.writeShellScriptBin "connect" ''
      echo "nmcli device wifi rescan"
      nmcli device wifi rescan
      echo "nmcli device wifi connect $@"
      nmcli device wifi connect $@
    '')

  ];
}
