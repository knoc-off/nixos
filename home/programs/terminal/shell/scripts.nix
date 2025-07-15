{
  pkgs,
  upkgs,
  self,
  hostname,
  ...
}: let
  config_dir = "/etc/nixos"; # Should relocate to /etc? and symlink?
  inherit (self.packages.${pkgs.system}) mkComplgenScript;
in {
  home.packages = [
    (mkComplgenScript {
      name = "csv_to_excel";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        if [ "$#" -ne 2 ]; then echo "Usage: csv_to_excel <input.csv> <output.xlsx>"; exit 1; fi
        input_csv="$1"; output_xlsx="$2"
        if [ ! -f "$input_csv" ]; then echo "Error: Input CSV file not found: '$input_csv'"; exit 1; fi
        # Note: Python path comes from runtimeDeps via wrapper
        python -c "import pandas as pd; import sys; df = pd.read_csv(sys.argv[1], encoding='utf-8'); df.to_excel(sys.argv[2], index=False)" "$input_csv" "$output_xlsx"
        echo "Converted '$input_csv' to '$output_xlsx'"
      '';
      # Grammar using external command 'fd'
      grammar = ''
        csv_to_excel {{{ ${pkgs.fd}/bin/fd --type f --extension csv --max-depth 1 . --color never --hidden --no-ignore }}} "Input CSV file" <PATH> "Output XLSX file";'';
      # Runtime dependency for the script itself
      runtimeDeps = [(pkgs.python3.withPackages (ps: [ps.pandas ps.openpyxl]))];
    })

    (mkComplgenScript {
      name = "excel_to_csv";
      # Minimal script content, relies on Python/pandas for error handling
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        # Python path comes from runtimeDeps via wrapper
        python -c "import pandas as pd; import sys; pd.read_excel(sys.argv[1]).to_csv(sys.argv[2], index=False, encoding='utf-8')" "$1" "$2"
      '';
      # Grammar for completion
      grammar = ''
        excel_to_csv {{{ ${pkgs.fd}/bin/fd --type f --extension xlsx --extension xls --max-depth 1 . --color never --hidden --no-ignore }}} "Input Excel file" <PATH> "Output CSV file";
      '';
      # Runtime dependencies
      runtimeDeps = [(pkgs.python3.withPackages (ps: [ps.pandas ps.openpyxl]))];
    })

    (mkComplgenScript {
      name = "anti-sleep";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        # --- Configuration ---
        # systemd-inhibit arguments
        INHIBIT_WHAT="sleep:idle:handle-lid-switch"
        INHIBIT_WHO="$USER" # Use the current user
        INHIBIT_MODE="block"

        # --- Argument Parsing & Duration Calculation ---
        usage() {
          echo "Usage: anti-sleep <duration | HH:MM>"
          echo "  duration: e.g., 30m, 1h, 6h, or any value accepted by 'sleep' (like 90s, 2h30m)"
          echo "  HH:MM:    Target time (24-hour format), e.g., 13:00. Inhibits sleep until that time today (or tomorrow if the time has passed)."
          exit 1
        }

        if [ "$#" -ne 1 ]; then
          usage
        fi

        input="$1"
        duration_sec=""
        why_message="Manual sleep prevention" # Default reason

        # Check for predefined keywords first
        case "$input" in
          30m)
            duration_sec=1800 # 30 * 60
            why_message="Preventing sleep for 30 minutes"
            ;;
          1h)
            duration_sec=3600 # 1 * 60 * 60
            why_message="Preventing sleep for 1 hour"
            ;;
          6h)
            duration_sec=21600 # 6 * 60 * 60
            why_message="Preventing sleep for 6 hours"
            ;;
          # Check if it looks like HH:MM time format
          [0-2][0-9]:[0-5][0-9])
            # Validate time format more strictly (e.g., 24:00 is invalid)
            if ! date -d "$input" >/dev/null 2>&1; then
               echo "Error: Invalid time format '$input'. Use HH:MM (24-hour)."
               exit 1
            fi

            current_epoch=$(date +%s)
            target_epoch=$(date -d "$input" +%s)

            # If target time is in the past today, assume target is tomorrow
            if [ "$target_epoch" -lt "$current_epoch" ]; then
              target_epoch=$(date -d "$input + 1 day" +%s)
              why_message="Preventing sleep until $input tomorrow"
            else
              why_message="Preventing sleep until $input today"
            fi

            duration_sec=$((target_epoch - current_epoch))
            ;;
          # Otherwise, assume it's a duration string for 'sleep' command
          *)
            # Basic validation: Check if 'sleep' understands the duration
            if ! sleep "$input" --help >/dev/null 2>&1 && ! sleep "$input" 0 ; then
               echo "Error: Invalid duration or time format: '$input'"
               usage
            fi
            # We let systemd-inhibit pass the raw duration string to sleep
            # This allows formats like '2h30m', '90s' etc.
            # Note: We don't calculate seconds here, pass the string directly.
            duration_sec="$input"
            why_message="Preventing sleep for duration '$input'"
            ;;
        esac

        if [ -z "$duration_sec" ]; then
           echo "Error: Could not determine sleep duration from input '$input'"
           usage
        fi

        # --- Execute systemd-inhibit ---
        echo "$why_message (Duration: $duration_sec seconds/specifier)"
        echo "Press Ctrl+C to cancel the inhibit lock."

        # Use exec to replace the shell process with systemd-inhibit
        # This ensures signals (like Ctrl+C) are handled correctly by systemd-inhibit
        exec ${pkgs.systemd}/bin/systemd-inhibit \
          --what="$INHIBIT_WHAT" \
          --who="$INHIBIT_WHO" \
          --why="$why_message" \
          --mode="$INHIBIT_MODE" \
          ${pkgs.coreutils}/bin/sleep "$duration_sec"

        # This part is unlikely to be reached because of 'exec'
        echo "Sleep inhibit finished or was cancelled."
      '';

      # Grammar for command-line completion
      grammar = ''
        anti-sleep <WORD> "Duration or Time";
      '';

      # Runtime dependencies for the script
      runtimeDeps = [pkgs.systemd pkgs.coreutils]; # coreutils for date and sleep
    })

    # cli = {
    #   body = "fabric -p cli \"$argv\" --stream";
    #   description = "Compress a file or directory";
    # };
    (mkComplgenScript {
      name = "cli";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        if [ $# -eq 0 ]; then
          echo "Usage: cli <command> [args...]"
          exit 1
        fi
        fabric -p cli "$@" --stream
      '';
      grammar = ''
        cli <COMMAND> "Command to run" ...;
      '';
      runtimeDeps = [pkgs.fabric-ai];
    })

    (mkComplgenScript {
      name = "pipewire-combine-sinks";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        PW_DUMP="${pkgs.pipewire}/bin/pw-dump"
        PW_CLI="${pkgs.pipewire}/bin/pw-cli"
        JQ="${pkgs.jq}/bin/jq"
        PACTL="${pkgs.pulseaudio}/bin/pactl"
        WPCTL="${pkgs.wireplumber}/bin/wpctl"
        SLEEP="${pkgs.coreutils}/bin/sleep"

        usage() {
          echo "Usage: $0 [OPTION]"
          echo "  Interactively combine two PipeWire audio sinks."
          echo
          echo "Options:"
          echo "  -c, --clean    Remove all existing combined sinks and exit."
          echo "  -h, --help     Show this help message and exit."
          exit 0
        }

        remove_combined_sinks() {
          echo "Cleaning old combined sinks..."
          mapfile -t combined_ids < <(
            "$PW_DUMP" | "$JQ" -r '
              .[] | select(.type == "PipeWire:Interface:Node" and
                           (.info.props["node.name"]? | test("combined"))) | .id'
          )
          if [ ''${#combined_ids[@]} -eq 0 ]; then
             echo "No combined sinks found."
             return
          fi
          echo "Removing ''${#combined_ids[@]} sink(s)..."
          for id in "''${combined_ids[@]}"; do
            "$PW_CLI" destroy "$id" || echo "Warn: Failed to remove $id" >&2
          done
          echo "Cleanup finished."
        }

        # --- Argument Parsing ---
        if [ $# -gt 0 ]; then
          case "$1" in
            -c|--clean) remove_combined_sinks; exit 0 ;;
            -h|--help)  usage ;;
            *) echo "Unknown option: $1"; usage ;;
          esac
        fi

        # --- Main Logic ---
        remove_combined_sinks # Clean before creating new

        echo "Scanning for audio sinks..."
        # Get sink ID, name, and description (fallback to name) in one go (TSV format)
        mapfile -t sinks_data < <(
          "$PW_DUMP" | "$JQ" -r '
            .[] | select(.type == "PipeWire:Interface:Node" and
                         .info.props["media.class"] == "Audio/Sink")
            | [.id, .info.props["node.name"],
               (.info.props["node.description"]? // .info.props["node.name"])]
            | @tsv'
        )

        if [ ''${#sinks_data[@]} -lt 2 ]; then
          echo "Error: Need at least 2 sinks to combine." >&2; exit 1
        fi

        echo "Available Sinks:"
        declare -a sink_ids sink_names sink_descs
        for i in "''${!sinks_data[@]}"; do
          # Parse TSV data directly into variables
          IFS=$'\t' read -r id name desc <<< "''${sinks_data[$i]}"
          sink_ids+=("$id")
          sink_names+=("$name")
          sink_descs+=("$desc")
          printf "[%d] %s\n" "$((i+1))" "$desc" # Use printf for formatting
        done

        # --- User Selection ---
        select_sink() {
          local prompt="$1"
          local exclude_index="$2" # Optional index to exclude
          local selection index
          while true; do
            read -rp "$prompt [1-''${#sink_ids[@]}]: " selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && \
               [ "$selection" -ge 1 ] && [ "$selection" -le ''${#sink_ids[@]} ]; then
              index=$((selection - 1))
              if [ -z "$exclude_index" ] || [ "$index" -ne "$exclude_index" ]; then
                echo "$index" # Return the selected index
                return
              else
                echo "Cannot select the same device twice." >&2
              fi
            else
              echo "Invalid selection." >&2
            fi
          done
        }

        idx1=$(select_sink "Select first device")
        idx2=$(select_sink "Select second device" "$idx1") # Exclude first selection

        # --- Create Combined Sink ---
        read -rp "Enter name for combined sink [combined]: " combined_name
        combined_name=''${combined_name:-combined}

        echo "Creating '$combined_name' with:"
        echo "  → ''${sink_descs[$idx1]}"
        echo "  → ''${sink_descs[$idx2]}"

        "$PACTL" load-module module-combine-sink \
          sink_name="$combined_name" \
          slaves="''${sink_names[$idx1]},''${sink_names[$idx2]}"

        echo "Combined sink created. Waiting for registration..."
        "$SLEEP" 2 # Give PipeWire/PulseAudio time

        # --- Set Default ---
        # Find the ID of the newly created sink
        new_sink_id=$("$PW_DUMP" | "$JQ" -r --arg name "$combined_name" '
          [.[] | select(.type == "PipeWire:Interface:Node" and
                        .info.props["node.name"] == $name)][0].id // empty'
        )

        if [ -z "$new_sink_id" ]; then
           echo "Error: Could not find created sink '$combined_name'." >&2; exit 1
        fi

        echo "Setting '$combined_name' (ID: $new_sink_id) as default..."
        "$WPCTL" set-default "$new_sink_id"

        echo "Success! Audio should now play on both devices."
        echo "Run '$0 --clean' to remove combined sinks."
      '';

      # Grammar for command-line completion (simple options)
      grammar = ''
        pipewire-combine-sinks (-c | --clean | -h | --help)?;
      '';

      # Runtime dependencies
      runtimeDeps = [
        pkgs.bash
        pkgs.pipewire
        pkgs.jq
        pkgs.pulseaudio
        pkgs.wireplumber
        pkgs.coreutils
      ];
    })

    (mkComplgenScript {
      name = "adr";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        SMART_MODEL="openrouter/google/gemini-2.5-pro-preview-03-25"
        FAST_MODEL="openrouter/google/gemini-2.5-flash-preview"
        MEDIUM_MODEL="openrouter/google/gemini-2.5-flash-preview:thinking"
        MODEL="$FAST_MODEL"
        WEAK_MODEL="$FAST_MODEL"
        AIDER_ARGS=() # Renamed from ARGS to avoid confusion with shell ARGS

        # Parse flags and file/other arguments
        while [ $# -gt 0 ]; do
          case "$1" in
            -s) MODEL="$SMART_MODEL"; shift ;;
            -m) MODEL="$MEDIUM_MODEL"; shift ;;
            -d) MODEL="$FAST_MODEL"; shift ;;
            *) AIDER_ARGS+=("$1"); shift ;;
          esac
        done

        if [ ''${#AIDER_ARGS[@]} -eq 0 ]; then
          AIDER_ARGS=("--message" "/commit")
        fi

        ${upkgs.aider-chat}/bin/aider \
          --alias "f:$FAST_MODEL" \
          --alias "m:$MEDIUM_MODEL" \
          --alias "s:$SMART_MODEL" \
          --alias "fast:$FAST_MODEL" \
          --alias "smart:$SMART_MODEL" \
          --alias "medium:$MEDIUM_MODEL" \
          --model "$MODEL" \
          --weak-model "$WEAK_MODEL" \
          --no-auto-lint \
          --no-auto-test \
          --no-attribute-committer \
          --no-attribute-author \
          --dark-mode \
          --edit-format diff \
          "''${AIDER_ARGS[@]}"
      '';
      # Corrected grammar:
      # grammar = ''
      #   adr [(-s | -m | -d)] [{{{${pkgs.fd}/bin/fd --type f --hidden --no-ignore --max-depth 1 . --color never}}} "File"] ... [<OTHER_ARG> "Other Argument"] ... ;'';
      grammar = ''
        adr <PATH>;
      '';
      runtimeDeps = [
        upkgs.aider-chat
        pkgs.fd
        pkgs.file # For file type detection in completion
        pkgs.gnugrep # For grep in completion
        pkgs.bash # For the script itself
      ];
    })

    (mkComplgenScript {
      name = "ping"; # The command name users will type

      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        # Use exec to replace this script process with ping for cleaner signal handling
        if [ -z "$1" ]; then
          echo "No target specified, pinging default: 1.1.1.1"
          # Use inetutils ping, which is more standard than toybox's
          exec ${pkgs.inetutils}/bin/ping 1.1.1.1
        else
          # Pass all arguments exactly as received to the real ping
          exec ${pkgs.inetutils}/bin/ping "$@"
        fi
      '';

      # Grammar for command-line completion
      grammar = ''
        ping {{{
          [ -f "$HOME/.ssh/known_hosts" ] && \
          ${pkgs.gawk}/bin/awk '
            # Skip comments, hashed hosts (|1|...), and markers (@...)
            /^#/ || /^\|/ || /^@/ { next }
            {
              # Get the first field (host list)
              hosts = $1
              # Remove bracket/port notation like [host]:port
              gsub(/\[|\]:[0-9]+/, "", hosts)
              # Split comma-separated hosts and print each one
              n = split(hosts, arr, ",")
              for (i = 1; i <= n; i++) {
                print arr[i]
              }
            }
          ' "$HOME/.ssh/known_hosts" | sort -u
        }}} "Target host/IP"

        # Allow any other host/IP not in the list
        <HOST>

        # Allow any subsequent arguments (like -c, -i, etc.)
        ... ;
      '';

      # Runtime dependencies for the script itself
      # Note: Dependencies for the *grammar command* (awk, sort) are separate
      # and assumed to be available in the completion environment,
      # but we specify them explicitly above for clarity/robustness.
      runtimeDeps = [
        pkgs.bash # For the script execution
        pkgs.inetutils # For the actual ping command
        # Dependencies needed for the completion command:
        pkgs.gawk # GNU awk is robust for parsing
        pkgs.coreutils # For sort
      ];
    })

    (self.packages.${pkgs.system}.nx config_dir hostname)

    (pkgs.writeShellScriptBin "chrome" ''
      nix shell nixpkgs#ungoogled-chromium --command chromium $1 &>/dev/null &
    '')

    (mkComplgenScript {
      name = "connect";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        if [ $# -lt 1 ]; then echo "Usage: connect <SSID> [password]"; exit 1; fi
        nmcli device wifi rescan
        nmcli device wifi connect "$@"
      '';
      grammar = ''
        connect {{{ ${pkgs.networkmanager}/bin/nmcli -t -f SSID dev wifi list }}} "SSID" [password "password: string"];
      '';
      runtimeDeps = [pkgs.networkmanager];
    })

    (mkComplgenScript {
      name = "qr";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail

        # Check for --share option
        for arg in "$@"; do
            if [[ "$arg" == "--share" ]]; then
                qrencode -t UTF8 < "$0"
                exit 0
            fi
        done

        # Read input if no arguments provided
        if [ $# -eq 0 ]; then
            read -r sanitized_input
        else
            sanitized_input="$*"
        fi

        # Generate QR code
        echo "$sanitized_input" | qrencode -t UTF8
      '';
      grammar = ''
        qr (--share | {{{ ${pkgs.fd}/bin/fd --type directory --type file --max-depth 1 . --color never }}} <INPUT>);
      '';
      runtimeDeps = [pkgs.qrencode];
    })

    (mkComplgenScript {
      name = "compress";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        if [ "$#" -ne 2 ]; then echo "Usage: compress <source> <dest.tar.gz>"; exit 1; fi
        [ ! -e "$1" ] && { echo "Error: Source not found"; exit 1; }
        tar -cf - "$1" | pv -s $(du -sb "$1" | awk '{print $1}') | ${pkgs.pigz}/bin/pigz -9 > "$2".tar.gz
      '';
      grammar = ''
        compress {{{ ${pkgs.fd}/bin/fd --type directory --type file --max-depth 1 . --color never }}} "Source" <PATH> "Destination";
      '';
      runtimeDeps = [pkgs.pigz pkgs.pv];
    })

    (mkComplgenScript {
      name = "rsync-compress";
      scriptContent = ''
        #!${pkgs.bash}/bin/bash
        set -euo pipefail
        if [ "$#" -ne 2 ]; then echo "Usage: rsync-compress <source> <dest>"; exit 1; fi
        [ ! -e "$1" ] && { echo "Error: Source not found"; exit 1; }
        size=$(du -sb "$1" | awk '{print $1}')
        rsync -avz --progress --compress-level=9 "$1" "$2" | pv -lep -s "$size"
      '';
      grammar = ''
        rsync-compress {{{ ${pkgs.fd}/bin/fd --type directory --type file --max-depth 1 . --color never }}} "Source" <PATH> "Destination";
      '';
      runtimeDeps = [pkgs.rsync pkgs.pv];
    })
  ];
}
