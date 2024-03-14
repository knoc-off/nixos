{
  imports = [
    ./profiles/main
    ./profiles/minimal
  ];

  programs.firefox = {
    enable = true;
  };
}
