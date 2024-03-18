{ conf
, pkgs
, lib
, ...
}:
let
  config_dir = "/home/knoff/nixos";
  configName = "laptop";
  homeConfigName = "knoff/laptop";
in
{
  programs.fish = {
    enable = true;
    functions = {
      __fish_command_not_found_handler = {
        body = "__fish_default_command_not_found_handler $argv[1]";
        onEvent = "fish_command_not_found";
      };
      #gitignore = "curl -sL https://www.gitignore.io/api/$argv";
      nixx = "nix run nixpkgs#$argv[1] -- $argv[2..-1]";
      compress = {
        body = "tar -cf - \"$argv[1]\" | pv -s $(du -sb \"$argv[1]\" | awk '{print $1}') | pigz -9 > \"$argv[2]\".tar.gz";
        description = "Compress a file or directory";
      };
      #decompress = "pv \"$argv[1]\" | pigz -d | tar -xf -";
      chrome = "nix shell nixpkgs#$argv[1] -- $argv[2..-1] &>/dev/null &";

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

      nixcommit = ''
        GIT_EDITOR=false git -C ${config_dir} commit

        git -C ${config_dir} diff --stat HEAD~ | sed 's/^/# /' >> ${config_dir}/.git/COMMIT_EDITMSG
        nvim -c 'set textwidth=80' ${config_dir}/.git/COMMIT_EDITMSG
        set TARGET_FILE "${config_dir}/systems/commit-message.nix"
        sed -i '/^#/d' ${config_dir}/.git/COMMIT_EDITMSG
        if test -z "$(head -n 1 ${config_dir}/.git/COMMIT_EDITMSG)"
            echo "no data"
            return 1
        end
        set first_line (head -n 1 ${config_dir}/.git/COMMIT_EDITMSG)
        set message (echo $first_line | sed -E 's/^\s+//g' | sed -E 's/\s+$//g' | sed 's/ /_/g' | sed -E 's/[^a-zA-Z0-9:_\.-]//g')
        set git_rev (git rev-parse --short HEAD)
        if test (string length -- $message) -lt 50
            set message (string pad -w 50 -r --char=_ "$message")
        end
        set message (string sub --length 50 "$message")
        printf "{\n  system.nixos.label = \"$message\";\n}" > $TARGET_FILE
        git -C ${config_dir} add $TARGET_FILE
        git -C ${config_dir} commit -a -F ${config_dir}/.git/COMMIT_EDITMSG

        #set leng


        return 0
        # Could now add the revision too. but it wouldent be tracked
        # but thats fine.
      '';

      nx = ''
        # fish function to run nix commands easily
        # switch statemnt to handle different commands
        switch $argv[1]
          case rb
            # if $argv[2] is -f then skip this check
            git -C ${config_dir} diff --quiet; set nochanges $status
            if [ $nochanges -eq 0 ]; or test "$argv[2]" = "-f"
              sudo nixos-rebuild switch --flake ${config_dir}#${configName}
            else
              nixcommit
              if [ "$status" = "0" ];
                nx rb
              end
            end
          case rh
            home-manager switch --flake ${config_dir}#${homeConfigName}
          case rt
            sudo nixos-rebuild test --flake ${config_dir}#${configName}
          case cr
            nix repl --extra-experimental-features repl-flake ${config_dir}#nixosConfigurations."${configName}"
          case hr
            nix repl --extra-experimental-features repl-flake ${config_dir}#homeConfigurations."${homeConfigName}"
          case vm
            sudo nixos-rebuild build-vm --flake ${config_dir}#${configName}
          case rg
            set -l file $(rg "$argv[2..-1]" ${config_dir} -l. | fzf)
            if test -z "$file"
              return
            end

            nvim "$file"
          case cd
            set -l file $(fd . ${config_dir} --type=d -E .git -H | fzf --query "$argv[2..-1]")
            if test -z "$file"
              return
            end
            cd "$file"
          case '*'
            set -l file $(fd . ${config_dir} -e nix -E .git -H | fzf --query "$argv[1..-1]")
            if test -z "$file"
              return
            end

            nvim "$file"
        end

      '';

      qr = ''
          if [[ $argv[1] == "--share" ]]; then
            declare -f qr | qrencode -l H -t UTF8;
            return
          fi

          local S
          if [[ "count $argv" == 0 ]]; then
            IFS= read -r S
            set -- "$S"
          fi

          sanitized_input="$argv"

          echo "$sanitized_input" | qrencode -l H -t UTF8
      '';

      findLocalDevices = ''
        set IPADDR "$(ifconfig | grep -A 1 'wlp2s0'  | tail -1 | grep -E '.[0-9]+\.[0-9]+\.[0-9]+\.' -o | tail -1)0"
        set NETMASK 24
        nix run nixpkgs#nmap -- -sP "$IPADDR/$NETMASK"
      '';
    };
    shellInitLast = ''

      # ssh with kitty, if using kitty
      [ "$TERM" = "xterm-kitty" ] && alias ssh="kitty +kitten ssh"


      # Dont judge me, its useful
      if test -f /etc/secrets/gpt/secret
          export OPENAI_API_KEY=(cat /etc/secrets/gpt/secret)
      end

      # This stupid magic function annoys me, of course it works
      function fish_user_key_bindings
        bind --preset \cw backward-kill-word
        #bind \e\[1\;5C forward-word
        #bind \e\[1\;5D backward-word
      end

    '';

    #function fish_prompt
    #  set -l git_branch " {"(git branch 2>/dev/null | sed -n '/\* /s///p')"}"
    #  echo -n (set_color yellow)(prompt_pwd)(set_color normal)"$git_branch"' $ '
    #end
  };
}
