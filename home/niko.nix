{...}: {
  # test
  imports = [
    ./programs/terminal/kitty
    ./programs/terminal

    #./programs/terminal/shell
    ./programs/terminal/shell/fish.nix
    # ./programs/filemanager/yazi.nix
  ];
  home.stateVersion = "25.05";
}
