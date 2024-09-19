{ config, pkgs, lib, ... }:
let
  blerc = pkgs.writeText "blerc" ''
    # ble.sh settings
    bleopt input_encoding=UTF-8
    bleopt complete_auto_complete=1
    bleopt complete_menu_complete=1

    # Vim mode
    #set -o vi
    bleopt editor=vim

    # Key bindings
    #ble-bind -m vi_nmap '"jk" vi_imap@accept'

    # Improved color scheme (explicitly setting backgrounds to none)
    ble-face -s region                    fg=15,bg=none
    ble-face -s region_target             fg=0,bg=none
    ble-face -s region_match              fg=11,bold,bg=none
    ble-face -s region_insert             fg=14,bg=none
    ble-face -s disabled                  fg=8,bg=none
    ble-face -s overwrite_mode            fg=0,bg=none
    ble-face -s syntax_default            none
    ble-face -s syntax_command            fg=4,bg=none
    ble-face -s syntax_quoted             fg=2,bg=none
    ble-face -s syntax_quotation          fg=2,bold,bg=none
    ble-face -s syntax_escape             fg=5,bg=none
    ble-face -s syntax_expr               fg=14,bg=none
    ble-face -s syntax_error              fg=9,bold,bg=none
    ble-face -s syntax_varname            fg=3,bg=none
    ble-face -s syntax_delimiter          bold,bg=none
    ble-face -s syntax_param_expansion    fg=13,bg=none
    ble-face -s syntax_history_expansion  fg=3,bold,bg=none
    ble-face -s syntax_function_name      fg=4,bold,bg=none
    ble-face -s syntax_comment            fg=8,bg=none
    ble-face -s syntax_glob               fg=9,bold,bg=none
    ble-face -s syntax_brace              fg=14,bold,bg=none
    ble-face -s syntax_tilde              fg=4,bold,bg=none
    ble-face -s command_builtin_dot       fg=1,bold,bg=none
    ble-face -s command_builtin           fg=1,bg=none
    ble-face -s command_alias             fg=6,bg=none
    ble-face -s command_function          fg=5,bg=none
    ble-face -s command_file              fg=2,bg=none
    ble-face -s command_keyword           fg=4,bg=none
    ble-face -s command_jobs              fg=1,bg=none
    ble-face -s command_directory         fg=14,bg=none
    ble-face -s filename_directory        fg=14,bg=none
    ble-face -s filename_directory_sticky fg=14,bold,bg=none
    ble-face -s filename_link             fg=6,bg=none
    ble-face -s filename_executable       fg=2,bg=none
    ble-face -s filename_setuid           fg=9,bold,bg=none
    ble-face -s filename_setgid           fg=11,bold,bg=none
    ble-face -s filename_other            bg=none
    ble-face -s filename_socket           fg=14,bg=none
    ble-face -s filename_pipe             fg=10,bg=none
    ble-face -s filename_character        fg=15,bg=none
    ble-face -s filename_block            fg=11,bg=none
    ble-face -s filename_warning          fg=9,bg=none
    ble-face -s filename_url              fg=4,bg=none
    ble-face -s filename_ls_colors        bg=none
    ble-face -s varname_array             fg=3,bold,bg=none
    ble-face -s varname_empty             fg=14,bg=none
    ble-face -s varname_export            fg=13,bold,bg=none
    ble-face -s varname_expr              fg=5,bold,bg=none
    ble-face -s varname_hash              fg=2,bold,bg=none
    ble-face -s varname_number            fg=2,bg=none
    ble-face -s varname_readonly          fg=13,bg=none
    ble-face -s varname_unset             fg=9,bg=none
    ble-face -s varname_transform         fg=6,bold,bg=none
    ble-face -s argument_option           fg=6,bg=none
    ble-face -s argument_error            fg=9,bold,bg=none
    ble-face -s auto_complete             fg=8,bg=none
    ble-face -s vbell                     reverse
    ble-face -s vbell_erase               none
    ble-face -s vbell_flash               fg=10,reverse
    ble-face -s prompt_status_line        fg=15,bg=none
    ble-face -s cmdinfo_cd_cdpath         fg=26,bg=none

    bleopt complete_menu_style=align-nowrap

    # Disable marking of directories, symlinks, etc.
    bind 'set mark-directories off'
    bind 'set mark-symlinked-directories off'
    bind 'set visible-stats off'
  '';

in

{
  #blesh

  # Configure Bash to use ble.sh
  programs.bash = {
    interactiveShellInit = ''
      # Load ble.sh
      if [[ $- == *i* ]]; then
        source "$(${pkgs.blesh}/bin/blesh-share)/ble.sh" --rcfile ${blerc} --noattach
      fi

      # Your existing Bash configurations...
      export HISTSIZE=10000
      export HISTFILESIZE=20000
      export HISTCONTROL=ignoreboth:erasedups
      shopt -s histappend
      shopt -s autocd
      shopt -s cdspell

      # Aliases
      alias ls='ls --color=auto'
      alias ll='ls -alF'
      alias la='ls -A'
      alias l='ls -CF'
      alias grep='grep --color=auto'
      alias fgrep='fgrep --color=auto'
      alias egrep='egrep --color=auto'

      # Attach ble.sh
      [[ ! $${BLE_VERSION-} ]] || ble-attach

      export EDITOR="vi";
      export VISUAL="vi";
    '';
  };

  environment.variables = {
    EDITOR = "vi";
    VISUAL = "vi";
  };


  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = lib.concatStrings [
        "$directory"
        "$line_break"
        "$nix_shell"
        "$character"
      ];
      scan_timeout = 10;
      character = {
        success_symbol = "➜";
        error_symbol = "[~>](bold red)";
      };
      package.disabled = false;
      nodejs.disabled = false;
      cmd_duration.disabled = false;
      directory.truncation_length = 3;
      directory.truncate_to_repo = true;
      git_branch.symbol = "🌱 ";
      git_status = {
        ahead = "⇡$${count}";
        diverged = "⇕⇡$${ahead_count}⇣$${behind_count}";
        behind = "⇣$${count}";
      };
    };
  };

  # Install some useful tools
  environment.systemPackages = with pkgs; [
    fzf       # Fuzzy finder
    ripgrep   # Fast grep alternative
    eza       # Modern ls alternative
    bat       # Cat clone with syntax highlighting
    fd        # Find alternative
    blesh
  ];
}
