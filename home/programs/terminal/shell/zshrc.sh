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

function findLocalDevices() {
    IPADDR="$(ifconfig | grep -A 1 'wlp2s0'  | tail -1 | grep -E '.[0-9]+\.[0-9]+\.[0-9]+\.' -o | tail -1)0"
    NETMASK=24
    eval "nix run nixpkgs#nmap -- -sP $IPADDR/$NETMASK"
}

function render_images() {
    clear

    local max_icon_size=50
    local min_icon_size=3

    local width=$(tput cols)
    local height=$(tput lines)

    local images=("$@")
    local count=${#images[@]}

    local icon_size=$((width / count))
    if ((icon_size > max_icon_size)); then
        icon_size=$max_icon_size
    elif ((icon_size < min_icon_size)); then
        icon_size=$min_icon_size
    fi


    #local rows=$((height / icon_size))

    # how many times does, icon_size * 2 fit into width
    local cols=$((width / (icon_size * 2) +1))

    local rows=$((count / cols))

    local index=0
    # make nested for loop, one for rows, one for cols
    for ((i=0; i < rows; i++)); do
        ypos=$((icon_size * i))
        for ((j=0; j < cols; j++)); do
            xpos=$(( (icon_size * 2) * (j-1)))


            kitten icat --align left --scale-up --place "${icon_size}x${icon_size}@${xpos}x${ypos}" "${images[index]}"

            ((index++))
        done

        # get current line number
        local line=$(tput lines)
    done
    tput cud $rows
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


