# nixx takes arguments, and assumes nixpkgs#<arg>. then it runs a script.
# nix shell nixpkgs#hello --command hello --greeting 'Hi everybody!'

# Should search for a matching word in apps
function nx () {
    # create a variable that contians all arguments except the first one
    varsA="${@:1}"
    varsB="${@:2}"

    config_dir="/home/knoff/nixos" #$(realpath "~/nix-config")
    case $1 in
        rb)
            sudo nixos-rebuild switch --flake $config_dir/#laptop
            ;;
        rh)
            home-manager switch --flake $config_dir/#knoff/laptop
            ;;
        rt)
            sudo nixos-rebuild test --flake $config_dir/#lapix
            ;;
        cr)
            nix repl --extra-experimental-features repl-flake $config_dir#nixosConfigurations.lapix
            ;;
        hr)
            nix repl --extra-experimental-features repl-flake $config_dir#homeConfigurations."knoff@lapix"
            ;;
        vm)
            sudo nixos-rebuild build-vm --flake $config_dir/#lapix
        ;;
        cd)
          # find all directories in the config dir.
            file=$(fd . $config_dir/ --type=d -E .git -H | fzf --query "$varsB")
            if [[ $file == "" ]]; then return; fi
            cd "$file"
        ;;
            *)
            file=$(fd . $config_dir -e nix -E .git -H | fzf --query "$varsA")
            if [[ $file == "" ]]; then return; fi
              nvim "$file"
        ;;
    esac
}


qr () {
  if [[ $1 == "--share" ]]; then
    declare -f qr | qrencode -l H -t UTF8;
    return
  fi

  local S
  if [[ "$#" == 0 ]]; then
    IFS= read -r S
    set -- "$S"
  fi

  sanitized_input="$*"

  echo "${sanitized_input}" | qrencode -l H -t UTF8
}


