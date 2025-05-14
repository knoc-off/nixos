# TODO: make all of the special arguments default? its better if it hard fails
{ config, lib, theme, color-lib, pkgs, user, ... }:
let
  inherit (color-lib) setOkhslLightness setOkhslSaturation;
  lighten = setOkhslLightness 0.8;
  saturate = setOkhslSaturation 0.9;

  sa = hex: lighten (saturate hex);

in {
  imports = [ ./starship.nix ];

  users.defaultUserShell = pkgs.fish;
  users.users.${user}.shell = pkgs.fish;

  environment.variables = {
    EDITOR = "vi";
    VISUAL = "vi";
  };

  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      #   # Terminal title
      #   function fish_title
      #     set -q argv[1]; or set argv fish
      #     echo (status current-command) " "
      #     pwd
      #   end

      #   # Better history search
      #   function history-search
      #     history | fzf --height=40% | read -l command
      #     and commandline -rb $command
      #   end
      #   bind \cr history-search


      function __newline
          commandline -i "\n"
      end

      #   bind \n __newline

      #   function __edit_command
      #       set -l tmpfile (mktemp)
      #       commandline > $tmpfile
      #       $EDITOR $tmpfile
      #       commandline -r (cat $tmpfile)
      #       commandline -f repaint
      #       rm $tmpfile
      #   end


      #   # Set key bindings
      #   bind -M insert \e\n __newline  # Alt-Enter for newline
      #   bind -M insert \cr history-search
      #   bind -M insert \ee __edit_command  # Alt-e for editor



      # # Set background color (typically base00 in Base16)
      # printf %b '\e]11;#${theme.base00}\e\\'

      # # Set foreground color (typically base05, base06, or base07 in Base16 - using base05)
      # printf %b '\e]10;#${theme.base06}\e\\'

      # # Set cursor color (often an accent color like base0D in Base16)
      # printf %b '\e]12;#${theme.base0D}\e\\'

      # # --- Set the standard 16 color palette entries (using RRGGBB format) ---
      # # Maps Base16 colors to standard ANSI 16 colors

      # # Set color palette entry 0 (Black) - typically base00
      # printf %b '\e]P0${theme.base00}'

      # # Set color palette entry 1 (Red) - typically base08
      # printf %b '\e]P1${theme.base08}'

      # # Set color palette entry 2 (Green) - typically base0B
      # printf %b '\e]P2${theme.base0B}'

      # # Set color palette entry 3 (Yellow) - typically base0A
      # printf %b '\e]P3${theme.base0A}'

      # # Set color palette entry 4 (Blue) - typically base0D
      # printf %b '\e]P4${theme.base0D}'

      # # Set color palette entry 5 (Magenta) - typically base0E
      # printf %b '\e]P5${theme.base0E}'

      # # Set color palette entry 6 (Cyan) - typically base0C
      # printf %b '\e]P6${theme.base0C}'

      # # Set color palette entry 7 (White) - typically base06 or base07 (using base06)
      # printf %b '\e]P7${theme.base06}'

      # # Set color palette entry 8 (Bright Black / Dark Grey) - typically base03
      # printf %b '\e]P8${theme.base03}'

      # # Set color palette entry 9 (Bright Red) - typically base09
      # printf %b '\e]P9${theme.base09}'

      # # Set color palette entry 10 (Bright Green) - typically base0B (often same as green)
      # printf %b '\e]Pa${sa theme.base0B}'

      # # Set color palette entry 11 (Bright Yellow) - typically base0A (often same as yellow)
      # printf %b '\e]Pb${sa theme.base0A}'

      # # Set color palette entry 12 (Bright Blue) - typically base0D (often same as blue)
      # printf %b '\e]Pc${sa theme.base0D}'

      # # Set color palette entry 13 (Bright Magenta) - typically base0E (often same as magenta)
      # printf %b '\e]Pd${sa theme.base0E}'

      # # Set color palette entry 14 (Bright Cyan) - typically base0C (often same as cyan)
      # printf %b '\e]Pe${sa theme.base0C}'

      # # Set color palette entry 15 (Bright White) - typically base07
      # printf %b '\e]Pf${theme.base07}'




    '';

    shellAbbrs = {
      l = "eza -l --group-directories-first --git";
      la = "eza -la --group-directories-first --git";
      lt = "eza --tree --level=2";
      g = "git";
      nrs = "sudo nixos-rebuild switch";
      ncg = "nix-collect-garbage -d";
      nr = "NIXPKGS_ALLOW_UNFREE=1 nix run --impure nixpkgs#";
      adf =
        "aider --model openrouter/google/gemini-2.0-flash-001 --weak-model openrouter/google/gemini-2.0-flash-001 --no-auto-lint --no-auto-test --no-attribute-committer --no-attribute-author --dark-mode --edit-format diff --file ";
    };

    shellAliases = {
      wgnord = "sudo ${pkgs.wgnord}/bin/wgnord";
      cat = "bat";
    };
  };

  # These packages are required for the Fish configuration to work properly
  environment.systemPackages = with pkgs; [
    eza # Modern replacement for ls with more features and better defaults
    bat # Cat clone with syntax highlighting
    zoxide # Smarter cd command that learns your habits
    fzf # Command-line fuzzy finder
    ripgrep # Fast grep alternative
    fd # User-friendly alternative to find
  ];
}
