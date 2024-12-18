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

    (self.packages.${pkgs.system}.nx config_dir hostname)

    (pkgs.writeShellScriptBin "test-print" ''
      echo "${config.xdg.configFile."kitty/kitty.conf".text}"
    '')

    (pkgs.writeShellScriptBin "isvpn" ''
      nmcli connection show --active | grep -q "wgnord" && echo true || echo false
    '')

    # might get rid of this.
    (pkgs.writeShellScriptBin "wrap-codeblocks" ''

      # Directory to search (default to current directory if not provided)
      DIRECTORY=''${1:-.}

      # Function to determine the Markdown code block language based on file extension
      get_filetype() {
        case "$1" in
          *.sh) echo "bash" ;;
          *.py) echo "python" ;;
          *.mcfunction) echo "mcfunction" ;;
          *.js) echo "javascript" ;;
          *.ts) echo "typescript" ;;
          *.json) echo "json" ;;
          *.md) echo "markdown" ;;
          *.txt) echo "plaintext" ;;
          *.html) echo "html" ;;
          *.htm) echo "html" ;;
          *.css) echo "css" ;;
          *.scss) echo "scss" ;;
          *.less) echo "less" ;;
          *.java) echo "java" ;;
          *.c) echo "c" ;;
          *.cpp) echo "cpp" ;;
          *.h) echo "c" ;;
          *.hpp) echo "cpp" ;;
          *.cs) echo "csharp" ;;
          *.rb) echo "ruby" ;;
          *.php) echo "php" ;;
          *.rs) echo "rust" ;;
          *.go) echo "go" ;;
          *.nix) echo "nix" ;;
          *.patch) echo "patch" ;;
          *.yaml) echo "yaml" ;;
          *.yml) echo "yaml" ;;
          *.toml) echo "toml" ;;
          *.xml) echo "xml" ;;
          *.vue) echo "vue" ;;
          *.kt) echo "kotlin" ;;
          *.dart) echo "dart" ;;
          *.pl) echo "perl" ;;
          *.pm) echo "perl" ;;
          *.r) echo "r" ;;
          *.jl) echo "julia" ;;
          *.lua) echo "lua" ;;
          *.sql) echo "sql" ;;
          *.swift) echo "swift" ;;
          *.scala) echo "scala" ;;
          *.groovy) echo "groovy" ;;
          *.ini) echo "ini" ;;
          *.bat) echo "batch" ;;
          *.ps1) echo "powershell" ;;
          *.vbs) echo "vbscript" ;;
          *.tex) echo "latex" ;;
          *.rmd) echo "rmarkdown" ;;
          *.erl) echo "erlang" ;;
          *.ex) echo "elixir" ;;
          *.exs) echo "elixir" ;;
          *.hs) echo "haskell" ;;
          *.clj) echo "clojure" ;;
          *.cljs) echo "clojurescript" ;;
          *.coffee) echo "coffeescript" ;;
          *.f90) echo "fortran" ;;
          *.f95) echo "fortran" ;;
          *.m) echo "objectivec" ;;
          *.mm) echo "objectivecpp" ;;
          *.rkt) echo "racket" ;;
          *.scm) echo "scheme" ;;
          *.lisp) echo "lisp" ;;
          *.asm) echo "assembly" ;;
          *.s) echo "assembly" ;;
          *) echo "IGNORE" ;; # Ignore all other file types
        esac
      }

      # Use fd to find all files in the specified directory and its subdirectories,
      # respecting .gitignore and excluding .git directories
      fd . --exclude .git --type f --hidden --follow "$DIRECTORY" | while read -r file; do

        # Get the filetype for the markdown code block
        filetype=$(get_filetype "$file")

        # Skip files that are not in the whitelist
        if [ "$filetype" == "IGNORE" ]; then
          continue
        fi

        # Print the file path
        echo "$file"

        # Print the opening markdown code block with the appropriate filetype
        echo "\`\`\`$filetype"

        # Print the contents of the file, escaping sequences of three consecutive backticks
        while IFS= read -r line; do
          echo "''${line//\`\`\`/\\\`\\\`\\\`}"
        done < "$file"

        # Print the closing markdown code block
        echo "\`\`\`"

        # Print a separating line for clarity (optional)
        echo "----------"
        printf "\n\n"
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
