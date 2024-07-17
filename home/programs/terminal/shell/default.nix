{ pkgs, ... }: {
  # command line tools.
  home.packages = with pkgs; [
    chroma # Required for colorize...
    qrencode
    fd
    fzf
    ripgrep
    pigz
    pv
  ];
  imports = [
    ./zsh.nix
    #./fish.nix
    ./nushell.nix
    ./scripts.nix
  ];
}
