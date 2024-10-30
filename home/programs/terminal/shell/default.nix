{ pkgs, ... }: {

  imports = [
    #./starship.nix
    ./scripts.nix
  ];

  # command line tools.
  home.packages = with pkgs; [
    chroma # Required for colorize...
    qrencode
    fd
    fzf
    ripgrep
    pigz
    pv
    sourceHighlight
    zoxide
  ];
}
