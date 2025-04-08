{ pkgs, upkgs, self, hostname, config, ... }:
let
  config_dir = "/etc/nixos"; # Should relocate to /etc? and symlink?
  inherit (self.packages.${pkgs.system}) writeNuScript;
in {
  home.packages = [

    (pkgs.writeShellScriptBin "anti-sleep" ''

      ${pkgs.systemd}/bin/systemd-inhibit \
        --what=sleep:idle:handle-lid-switch \
        --who="$USER" \
        --why="Manual sleep prevention" \
        --mode=block \
        sleep "$1"
    '')

    (pkgs.writeShellScriptBin "pipewire-combine-sinks" ''
      #!/usr/bin/env bash
      set -euo pipefail

      # Function to get a more user-friendly name for a sink
      get_friendly_name() {
        local node_name="$1"

        # Extract device name from node name
        local device_id=""

        if [[ "$node_name" =~ bluez_output\.([0-9A-F_]+)\. ]]; then
          device_id="bluez_card.''${BASH_REMATCH[1]}"
        elif [[ "$node_name" =~ alsa_output\.([^\.]+)\. ]]; then
          device_id="alsa_card.''${BASH_REMATCH[1]}"
        fi

        # If we found a device ID, look up its description
        if [ -n "$device_id" ]; then
          local description=$(${pkgs.pipewire}/bin/pw-dump | ${pkgs.jq}/bin/jq -r --arg id "$device_id" '
            [.[] | select(.type == "PipeWire:Interface:Device")
             | select(.info.props["device.name"] == $id)
             | .info.props["device.description"]][0]')

          if [ "$description" != "null" ] && [ -n "$description" ]; then
            echo "$description"
            return 0
          fi
        fi

        # Fallback: For combined sinks, just return "Combined Output"
        if [[ "$node_name" == "combined"* ]]; then
          echo "Combined Output ($node_name)"
          return 0
        fi

        # Last resort: return the node name itself
        echo "$node_name"
      }

      # Function to remove all combined sinks
      remove_combined_sinks() {
        echo "Searching for existing combined sinks..."

        # Find all nodes with "combined" in their name
        combined_sinks=$(${pkgs.pipewire}/bin/pw-dump  | \
          ${pkgs.jq}/bin/jq -r '[.[]
            | select(.type == "PipeWire:Interface:Node")
            | select(.info.props["node.name"] | contains("combined"))
            | {id: .id, name: .info.props["node.name"]}]')

        num_combined=$(echo "$combined_sinks" | ${pkgs.jq}/bin/jq 'length')

        if [ "$num_combined" -eq 0 ]; then
          echo "No existing combined sinks found."
          return 0
        fi

        echo "Found $num_combined existing combined sink(s):"

        # Display and destroy each combined sink
        for (( i=0; i < num_combined; i++ )); do
          id=$(echo "$combined_sinks" | ${pkgs.jq}/bin/jq -r ".[$i].id")
          name=$(echo "$combined_sinks" | ${pkgs.jq}/bin/jq -r ".[$i].name")
          echo "  → Removing: $name (ID: $id)"

          ${pkgs.pipewire}/bin/pw-cli destroy "$id" || echo "  Warning: Failed to remove sink $id"
        done

        echo "All combined sinks removed."
        return 0
      }

      # Check for command-line arguments
      if [ $# -gt 0 ]; then
        if [ "$1" = "--clean" ] || [ "$1" = "-c" ]; then
          remove_combined_sinks
          exit 0
        elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
          echo "Usage: pipewire-combine-sinks [OPTION]"
          echo ""
          echo "Options:"
          echo "  -c, --clean    Remove all existing combined sinks without creating a new one"
          echo "  -h, --help     Display this help message"
          echo ""
          echo "With no options, the script will guide you through creating a new combined sink."
          exit 0
        else
          echo "Unknown option: $1"
          echo "Use --help to see available options."
          exit 1
        fi
      fi

      # First, remove any existing combined sinks
      remove_combined_sinks

      echo "Scanning for audio devices..."

      # Get all audio sinks
      SINKS_JSON=$(${pkgs.pipewire}/bin/pw-dump  | \
        ${pkgs.jq}/bin/jq '[.[]
          | select(.type == "PipeWire:Interface:Node")
          | select(.info.props["media.class"] == "Audio/Sink")
          | { id: .id, node_name: .info.props["node.name"] }
        ]')

      NUM_SINKS=$(echo "$SINKS_JSON" | ${pkgs.jq}/bin/jq 'length')

      if [ "$NUM_SINKS" -lt 2 ]; then
        echo "Error: You need at least two active audio sink devices to combine."
        exit 1
      fi

      echo "Available Audio Sink Devices:"

      # Create arrays to store sink information
      declare -a sink_ids
      declare -a sink_node_names
      declare -a sink_display_names

      # Process each sink and get friendly names
      for (( i=0; i < NUM_SINKS; i++ )); do
        id=$(echo "$SINKS_JSON" | ${pkgs.jq}/bin/jq -r ".[$i].id")
        node_name=$(echo "$SINKS_JSON" | ${pkgs.jq}/bin/jq -r ".[$i].node_name")

        # Get a friendly name for this sink
        friendly_name=$(get_friendly_name "$node_name")

        sink_ids+=("$id")
        sink_node_names+=("$node_name")
        sink_display_names+=("$friendly_name")

        # Display the sink with its friendly name
        echo "[$((i+1))] $friendly_name"
      done

      # Ask for user selection for the first sink
      while true; do
        read -rp "Select first device [1-$NUM_SINKS]: " selection1
        if [[ "$selection1" =~ ^[0-9]+$ ]] && [ "$selection1" -ge 1 ] && \
           [ "$selection1" -le "$NUM_SINKS" ]; then
          index1=$((selection1 - 1))
          break
        else
          echo "Invalid selection. Please try again."
        fi
      done

      # Ask for user selection for the second sink
      while true; do
        read -rp "Select second device [1-$NUM_SINKS]: " selection2
        if [[ "$selection2" =~ ^[0-9]+$ ]] && [ "$selection2" -ge 1 ] && \
           [ "$selection2" -le "$NUM_SINKS" ] && [ "$selection2" -ne "$selection1" ]; then
          index2=$((selection2 - 1))
          break
        else
          if [ "$selection2" -eq "$selection1" ]; then
            echo "You cannot choose the same device twice."
          else
            echo "Invalid selection. Please try again."
          fi
        fi
      done

      # Get the node names for the selected sinks
      node1="''${sink_node_names[$index1]}"
      node2="''${sink_node_names[$index2]}"

      # Get the display names for the selected sinks
      display1="''${sink_display_names[$index1]}"
      display2="''${sink_display_names[$index2]}"

      # Prompt for a name for the combined sink
      read -rp "Enter name for the combined sink [combined]: " combined_name
      combined_name=''${combined_name:-combined}

      echo ""
      echo "Creating combined sink '''"$combined_name"''' using:"
      echo "  → $display1"
      echo "  → $display2"
      echo ""

      # Create the combined sink using pactl (the method that worked)
      module_id=$(${pkgs.pulseaudio}/bin/pactl load-module module-combine-sink \
        sink_name="$combined_name" \
        slaves="$node1,$node2")

      echo "Combined sink created successfully."

      # Wait for the sink to register
      sleep 2

      # Look up the combined sink ID
      combined_sink_id=$(${pkgs.pipewire}/bin/pw-dump  | \
        ${pkgs.jq}/bin/jq -r --arg name "$combined_name" '
          [ .[] | select(.type == "PipeWire:Interface:Node")
            | select(.info.props["node.name"] == $name)
          ][0].id
        ')

      if [ -z "$combined_sink_id" ] || [ "$combined_sink_id" == "null" ]; then
        echo "Error: Could not find the combined sink in the PipeWire registry."
        exit 1
      fi

      echo "Setting '''"$combined_name"''' as the default audio output..."

      # Set the combined sink as default
      ${pkgs.wireplumber}/bin/wpctl set-default "$combined_sink_id"

      echo "Success: Combined sink is now the default output."
      echo "Audio will now play through both selected devices."
      echo ""
      echo "Note: This combined sink will disappear after a reboot."
      echo "To remove all combined sinks without rebooting, run: pipewire-combine-sinks --clean"
      exit 0
    '')

      (pkgs.writeShellScriptBin "adr" ''
        M="openrouter/google/gemini-2.0-flash-001"
        W="openrouter/google/gemini-2.0-flash-001"
        A=$#

        while [ $# -gt 0 ]; do
          case "$1" in
            -s) M="openrouter/google/gemini-2.5-pro-preview-03-25"; shift;;
            -d) M="openrouter/google/gemini-2.0-flash-001"; shift;;
            *) B="$B \"$1\""; shift;;
          esac
        done

        [ $A -eq 0 ] && B="--message /commit"

        eval ${upkgs.aider-chat}/bin/aider --model "\"$M\"" --weak-model "\"$W\"" --no-auto-lint --no-auto-test --no-attribute-committer --no-attribute-author --dark-mode --edit-format diff $B
        # aider --model openrouter/google/gemini-2.0-flash-001 --weak-model openrouter/google/gemini-2.0-flash-001 --no-auto-lint --no-auto-test --no-attribute-committer --no-attribute-author --dark-mode --edit-format diff --file
      '')


    (pkgs.writeShellScriptBin "ping" ''
      # replace the ping command if no input is given just ping 1.1.1.1
      if [ -z "$1" ]; then
        ''${pkgs.toybox}/bin/ping 1.1.1.1
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
