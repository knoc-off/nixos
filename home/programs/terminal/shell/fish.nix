{...}: {
  programs.direnv.enable = true;
  programs.fish = {
    enable = true;
    functions = {
      __fish_command_not_found_handler = {
        body = "__fish_default_command_not_found_handler $argv[1]";
        onEvent = "fish_command_not_found";
      };
      #gitignore = "curl -sL https://www.gitignore.io/api/$argv";
      compress = {
        body = "tar -cf - \"$argv[1]\" | pv -s $(du -sb \"$argv[1]\" | awk '{print $1}') | pigz -9 > \"$argv[2]\".tar.gz";
        description = "Compress a file or directory";
      };
      cli = {
        body = "fabric -p cli \"$argv\" --stream";
        description = "Compress a file or directory";
      };
      #decompress = "pv \"$argv[1]\" | pigz -d | tar -xf -";
      chrome = "nix shell nixpkgs#$argv[1] -- $argv[2..-1] &>/dev/null &";
      cdToFile = ''pushd "$(fd . --exclude .git --exclude .gitignore -t f | fzf | xargs dirname)"'';

      edit_command_buffer = {
        description = ''Edit the command buffer in an external editor'';
        body = ''
          set -l f (mktemp)
          if set -q f[1]
              mv $f $f.fish
              set f $f.fish
          else
              # We should never execute this block but better to be paranoid.
              set f /tmp/fish.(echo %self).fish
              touch $f
          end

          set -l p (commandline -C)
          commandline -b > $f
          if set -q EDITOR
              eval $EDITOR $f
          else
              vim $f
          end

          commandline -r (cat $f)
          commandline -C $p
          command rm $f
        '';
      };

      # qr = ''
      #   if [[ $argv[1] == "--share" ]]; then
      #     declare -f qr | qrencode -l H -t UTF8;
      #     return
      #   fi

      #   local S
      #   if [[ "count $argv" == 0 ]]; then
      #     IFS= read -r S
      #     set -- "$S"
      #   fi

      #   sanitized_input="$argv"

      #   echo "$sanitized_input" | qrencode -l H -t UTF8
      # '';

      backg = ''
        eval "$argv &>/dev/null 2>&1 & disown"
      '';

      findLocalDevices = ''
        set IPADDR "$(ifconfig | grep -A 1 'wlp2s0'  | tail -1 | grep -E '.[0-9]+\.[0-9]+\.[0-9]+\.' -o | tail -1)0"
        set NETMASK 24
        nix run nixpkgs#nmap -- -sP "$IPADDR/$NETMASK"
      '';
    };
    shellInitLast = ''

      # ssh with kitty, if using kitty
      # [ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"

      # This stupid magic function annoys me, of course it works
      # function fish_user_key_bindings
      #   bind --preset \cw backward-kill-word
      #   #bind \e\[1\;5C forward-word
      #   #bind \e\[1\;5D backward-word
      # end

    '';
  };
}
