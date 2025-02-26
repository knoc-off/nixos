{ pkgs, self, hostname, config, ... }:
let
  config_dir = "/etc/nixos"; # Should relocate to /etc? and symlink?
  inherit (self.packages.${pkgs.system}) writeNuScript;
in {
  home.packages = [
    (pkgs.writeShellScriptBin "anti-sleep" ''
      #${pkgs.sox}/bin/play -n synth 604800 sin 440 vol 0.01
      # $1 is the time in seconds to not sleep
      # ${pkgs.sudo}/bin/sudo ${pkgs.systemd}/bin/systemd-inhibit --what=handle-suspend:sleep --why="Anti-Sleep" --mode=block -- $@
      # ${pkgs.sox}/bin/play -n synth $1 sin 440 vol 0.01

      ${pkgs.systemd}/bin/systemd-inhibit \
        --what=sleep:idle:handle-lid-switch \
        --who="$USER" \
        --why="Manual sleep prevention" \
        --mode=block \
        sleep "$1"

    '')

    (pkgs.writeShellScriptBin "ping" ''
      # replace the ping command if no input is given just ping 1.1.1.1
      if [ -z "$1" ]; then
        ${pkgs.toybox}/bin/ping 1.1.1.1
      else
        ${pkgs.toybox}/bin/ping $@
      fi
    '')

    # not sure if this works w/o sudo.
    (pkgs.writeShellScriptBin "vpn" ''
      if [ -z "$1" ]; then
        if isvpn; then
          echo "VPN is already connected"
        else
          echo "VPN is not connected"
          wgnord c de
        fi
        exit 0
      fi

      wgnord c $@

    '')

    (self.packages.${pkgs.system}.nx config_dir hostname)

    (pkgs.writeShellScriptBin "test-print" ''
      echo "${config.xdg.configFile."kitty/kitty.conf".text}"
    '')

    (pkgs.writeShellScriptBin "isvpn" ''
      nmcli connection show --active | grep -q "wgnord" && echo true || echo false
    '')

    (writeNuScript "nixx" ''
      def --wrapped main [...args: string] {
        mut command = []
        mut nixx_args = []
        mut program_args = []
        mut package = ""
        mut sudo = false
        mut bg = false

        let separator_indices = ($args | enumerate | where item == "--" | get index)
        let separator_index = if ($separator_indices | length) == 0 {
          null
        } else {
          $separator_indices | first
        }

        if $separator_index != null {
          $nixx_args = ($args | range ..$separator_index)
          $program_args = ($args | range ($separator_index + 1)..)
        } else {
          $nixx_args = $args
          $program_args = []
        }

        # Process nixx arguments
        for arg in $nixx_args {
          if $arg == "sudo" {
            $sudo = true
          } else if $arg == "bg" {
            $bg = true
          } else if $package == "" {
            $package = $arg
          }
        }

        if $sudo and $bg {
          print "Warning: Using sudo with background tasks may require manual authentication"
        }

        if $bg {
          $command = ($command | append ["pueue" "add"])
        }

        $command = ($command | append [
          "env"
          "NIXPKGS_ALLOW_UNFREE=1"
          "nix"
          "shell"
          "--impure"
          $"nixpkgs#($package)"
          "--command"
        ])

        if $sudo {
          $command = ($command | append "sudo")
        }

        $command = ($command | append $package)
        $command = ($command | append $program_args)

        let command_str = ($command | str join " ")

        if $bg {
          let pueue_output = (nu -c $command_str | str trim)
          let task_id = ($pueue_output | parse "New task added (id {id})." | get id | first)
          if $task_id != null {
            print $"Task added with ID: ($task_id)"
            # pueue follow $task_id
          } else {
            print "Failed to parse task ID. Pueue output:"
            print $pueue_output
          }
        } else {
          bash -c $command_str
        }
      }
    '')

    (pkgs.writeShellScriptBin "git-msg" ''
      git diff HEAD | llm "from the text extract only important changes to craft a concise and simple git commit message, formatted like this:
      <Title of the git commit>

      <body, Details of the commit>"
    '')

    (pkgs.writeShellScriptBin "compress" ''
      tar -cf - "$1" | pv -s $(du -sb "$1" | awk '{print $1}') | ${pkgs.pigz}/bin/pigz -9 > "$2".tar.gz
    '')

    (writeNuScript "rsync-compress" ''
      def main [source: path, destination: string] {
        let size = (du -sb $source | split row " " | get 0 | into int)
        rsync -avz --progress --compress-level=9 $source $destination
        | pv -lep -s $size
        | ignore
      }
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
