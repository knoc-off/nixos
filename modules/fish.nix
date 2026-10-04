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
        chrome = "nix shell nixpkgs#$argv[1] -- $argv[2..-1] &>/dev/null &";
        cdToFile = ''pushd "$(fd . --exclude .git --exclude .gitignore -t f | fzf | xargs dirname)"'';

        # `!!` abbr below: expands in place to the previous command.
        last_history_item = "echo $history[1]";

        backg = ''
          eval "$argv &>/dev/null 2>&1 & disown"
        '';

        findLocalDevices = ''
          set IPADDR "$(ifconfig | grep -A 1 'wlp2s0'  | tail -1 | grep -E '.[0-9]+\.[0-9]+\.[0-9]+\.' -o | tail -1)0"
          set NETMASK 24
          nix run nixpkgs#nmap -- -sP "$IPADDR/$NETMASK"
        '';
      };
      shellAbbrs."!!" = {
        position = "anywhere";
        function = "last_history_item";
      };
    };
  };
}
