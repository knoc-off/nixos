{ pkgs, ... }:
let
  config_dir = "~/nixos";
  config_name = "framework13";

in
{

  home.packages = [
    (pkgs.writeNuScript "nx"
     ''
      def main --env [ -f, ...x] {
        match ($x.0) {
          "rb" => {
              enter ${config_dir}
              # if dirty > commit. unless forced then continue

              if ( (git status --porcelain) != "" and $f == false) {
                  echo "git is dirty"
                  nixcommit
                  if ($env.LAST_EXIT_CODE == 1 ) { return }
              }
              dexit

              echo "force rebuild"
              sudo nixos-rebuild switch --flake (("${config_dir}" | path expand) + "#" + "${config_name}")

          },
          "rt" => {
              sudo nixos-rebuild test --flake (("${config_dir}" | path expand) + "#" + "${config_name}")
          },
          "cr" => {
            nix repl --extra-experimental-features repl-flake (("${config_dir}" | path expand) + "#nixosConfigurations." + "${config_name}" )
          },
           "vm" => {
              sudo nixos-rebuild build-vm --flake (("${config_dir}" | path expand) + "#" + "${config_name}")
          },
          "cd" => {
              let file = (fd . ("${config_dir}" | path expand) --type=d -E .git -H | fzf --query ( $x | range 1..-1 | str join " "))
              if not ( echo $file | path exists) { return }
              echo $file

              cd $file

          }
          _ => {
              let file = (fd . ("${config_dir}" | path expand) -e nix -E .git -H | fzf --query ( $x | range 0..-1 | str join " "))
              if ( echo $file | path exists) {
                  echo $file
                  nvim $file
              }
          },
        }
      }
      ''
    )
    (pkgs.writeNuScript "nixcommit"
    ''
      def main [] {

        let config_dir = ("${config_dir}" | path expand)

        # Initial commit without an editor
        try {
          let mut GIT_EDITOR = false
          git -C $config_dir commit
          #GIT_EDITOR = $previous_GIT_EDITOR
        }

        # Edit the commit message with nvim, setting textwidth to 80
        nvim -c 'set textwidth=80' (($config_dir + "/.git/COMMIT_EDITMSG") | path expand)

        let first_line = (open (($config_dir + "/.git/COMMIT_EDITMSG") | path expand ) | lines | first 1).0

        # Check if the first line of COMMIT_EDITMSG is empty
        if ( $first_line == "") {
          echo "empty data"
          exit 1
        }


        let message = (echo $first_line | str trim | str replace -a " " "_" | str replace -ra '[^a-zA-Z0-9:_\.-]' "")

        # Truncate or pad message to exactly 50 characters
        let message = ($message | str substring 0..50)

        let message = ($message | fill -a left -c '_' -w 50)
        #'1234' | fill -a left -c '0' -w 10

        echo $message

        let message_path =  ( $config_dir + "/systems/commit-message.nix"  | path expand )

        echo ("{\n  system.nixos.label = \"" + $message + "\";\n}") | save -f $message_path
        # Add and commit the changes
        git -C $config_dir add $message_path
        git -C $config_dir commit --all --file (($config_dir + "/.git/COMMIT_EDITMSG") | path expand)

        exit 0
      }
    '')
    (pkgs.writeNuScript "nixx"
    ''
      # i should really just add everything to a list and then combine with " "
      def main [--sudo, --bg, package: string, ...args] {
        mut command = [];

        if ($sudo and $bg) {
          # sudo and pueue is not made for this, im just gonna do it.
          echo "place fingerprint"
        }

        if ($bg) {
          $command = ($command | append "pueue add -p")
        }

        # Allow unfree
        $command = ($command | append "NIXPKGS_ALLOW_UNFREE=1")

        # Shell or run?
        $command = ($command | append "nix shell")

        # impure
        $command = ($command | append "--impure")

        # Package
        $command = ($command | append ( "nixpkgs#" + $package + " " ))

        # command


        if ($sudo) {
          $command = ($command | append ("--command sudo"))
        } else {
          $command = ($command | append ("--command"))
        }

        $command = ( $command | append $package )

        # extra
        $command = ( $command | append $args )

        #echo $command
        let strCommand = ($command | str join " ")
        let variable = nu -c $strCommand
        if ( $bg ) {
          pueue follow $variable
        }

      }
    '')
  ];
}
