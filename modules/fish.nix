{ ... }: {
  nixos = { ... }: {
    environment = {
      variables = {
        EDITOR = "vi";
        VISUAL = "vi";
      };

      shellAliases = {
        x = "xargs ";
        xi = "xargs -I '{}' ";
      };
    };
    programs.fish = {
      enable = true;
      interactiveShellInit = ''
        stty -echoctl

        function __auto_bg --on-event fish_prompt
            bg 2>/dev/null
        end

        function __fish_ctrl_z
            test -z (commandline); and test (count (jobs)) -gt 0; and fg 2>/dev/null; and commandline -f repaint
        end
        bind \cz __fish_ctrl_z
      '';
    };
  };

  home = { ... }: {
    programs.direnv.enable = true;
    programs.fish = {
      enable = true;
      functions = {
        __fish_command_not_found_handler = {
          body = "__fish_default_command_not_found_handler $argv[1]";
          onEvent = "fish_command_not_found";
        };
        compress = {
          body = "tar -cf - \"$argv[1]\" | pv -s $(du -sb \"$argv[1]\" | awk '{print $1}') | pigz -9 > \"$argv[2]\".tar.gz";
          description = "Compress a file or directory";
        };
        cli = {
          body = "fabric -p cli \"$argv\" --stream";
          description = "Compress a file or directory";
        };
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

        # This stupid magic function annoys me, of course it works
        # function fish_user_key_bindings
        #   bind --preset \cw backward-kill-word
        #   #bind \e\[1\;5C forward-word
        #   #bind \e\[1\;5D backward-word
        # end

      '';
    };
  };
}
