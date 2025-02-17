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

    # might get rid of this.
    (pkgs.writeShellScriptBin "wrap-codeblocks" ''
      #!/usr/bin/env bash

      # Enhanced file-to-markdown converter with custom ignores and filetype handling
      # Usage: script [OPTIONS] [FILE_GLOBS...]

      # Initialize variables
      declare -A CUSTOM_FILETYPES
      declare -a EXCLUDE_PATTERNS=('.git')  # Always exclude .git by default
      SEARCH_PATTERNS=()  # Stores user-provided file patterns
      DIRECTORY='.'       # Default search directory

      # Parse command-line options
      while [[ $# -gt 0 ]]; do
          case "$1" in
              -i|--ignore)
                  EXCLUDE_PATTERNS+=("$2")
                  shift 2
                  ;;
              -f|--filetype)
                  IFS='=' read -r exts lang <<< "$2"
                  for ext in ''${exts//,/ }; do
                      CUSTOM_FILETYPES["$ext"]="$lang"
                  done
                  shift 2
                  ;;
              -*)
                  echo "Invalid option: $1" >&2
                  exit 1
                  ;;
              *)
                  # Check if argument is a directory (for backward compatibility)
                  if [[ -d "$1" && "''${#SEARCH_PATTERNS[@]}" -eq 0 ]]; then
                      DIRECTORY="$1"
                  else
                      SEARCH_PATTERNS+=("$1")
                  fi
                  shift
                  ;;
          esac
      done

      # Use provided patterns or default to directory
      if [[ "''${#SEARCH_PATTERNS[@]}" -eq 0 ]]; then
          SEARCH_PATTERNS=("$DIRECTORY")
      fi

      # Filetype detection function with custom overrides
      get_filetype() {
          local filename="$1"
          local extension="''${filename##*.}"

          # Check custom filetypes first
          for pattern in "''${!CUSTOM_FILETYPES[@]}"; do
              if [[ "$filename" == $pattern ]]; then
                  echo "''${CUSTOM_FILETYPES[$pattern]}"
                  return
              fi
          done

          # Built-in type detection
          case "$filename" in
              *.*)
                  case ".''${filename##*.}" in
                      .sh) echo "bash" ;;
                      .py) echo "python" ;;
                      .mcfunction) echo "mcfunction" ;;
                      .js) echo "javascript" ;;
                      .ts) echo "typescript" ;;
                      .json) echo "json" ;;
                      .md) echo "markdown" ;;
                      .txt) echo "plaintext" ;;
                      .html|.htm) echo "html" ;;
                      .css) echo "css" ;;
                      .scss) echo "scss" ;;
                      .less) echo "less" ;;
                      .java) echo "java" ;;
                      .c) echo "c" ;;
                      .cpp|.hpp|.hxx) echo "cpp" ;;
                      .h) echo "c" ;;
                      .cs) echo "csharp" ;;
                      .rb) echo "ruby" ;;
                      .php) echo "php" ;;
                      .rs) echo "rust" ;;
                      .go) echo "go" ;;
                      .nix) echo "nix" ;;
                      .patch) echo "patch" ;;
                      .yaml|.yml) echo "yaml" ;;
                      .toml) echo "toml" ;;
                      .xml) echo "xml" ;;
                      .vue) echo "vue" ;;
                      .kt) echo "kotlin" ;;
                      .dart) echo "dart" ;;
                      .pl|.pm) echo "perl" ;;
                      .r) echo "r" ;;
                      .jl) echo "julia" ;;
                      .lua) echo "lua" ;;
                      .sql) echo "sql" ;;
                      .swift) echo "swift" ;;
                      .scala) echo "scala" ;;
                      .groovy) echo "groovy" ;;
                      .ini) echo "ini" ;;
                      .bat) echo "batch" ;;
                      .ps1) echo "powershell" ;;
                      .vbs) echo "vbscript" ;;
                      .tex) echo "latex" ;;
                      .rmd) echo "rmarkdown" ;;
                      .erl) echo "erlang" ;;
                      .ex|.exs) echo "elixir" ;;
                      .hs) echo "haskell" ;;
                      .clj) echo "clojure" ;;
                      .cljs) echo "clojurescript" ;;
                      .coffee) echo "coffeescript" ;;
                      .f90|.f95) echo "fortran" ;;
                      .m) echo "objectivec" ;;
                      .mm) echo "objectivecpp" ;;
                      .rkt) echo "racket" ;;
                      .scm) echo "scheme" ;;
                      .lisp) echo "lisp" ;;
                      .asm|.s) echo "assembly" ;;
                      *) echo "IGNORE" ;;
                  esac
                  ;;
              *)
                  # Handle extensionless files using custom patterns
                  for pattern in "''${!CUSTOM_FILETYPES[@]}"; do
                      if [[ "$filename" == $pattern ]]; then
                          echo "''${CUSTOM_FILETYPES[$pattern]}"
                          return
                      fi
                  done
                  echo "IGNORE"
                  ;;
          esac
      }

      # Build exclude arguments for fd
      EXCLUDE_ARGS=()
      for pattern in "''${EXCLUDE_PATTERNS[@]}"; do
          EXCLUDE_ARGS+=(--exclude "$pattern")
      done

      # Main processing loop
      fd --glob "''${SEARCH_PATTERNS[@]}" \
          --type f \
          --hidden \
          --follow \
          "''${EXCLUDE_ARGS[@]}" | while read -r file; do


          filetype=$(get_filetype "$file")
          [[ "$filetype" == "IGNORE" ]] && continue

          echo "$file"
          echo "\`\`\`$filetype"

          # Escape backticks and preserve trailing newline
          awk '{ gsub(/```/, "\\`\\`\\`"); print } END { if (NR && $0 != "") printf "\n" }' "$file"

          echo "\`\`\`"
          echo -e "----------\n"
      done


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
