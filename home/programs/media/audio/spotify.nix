{
  pkgs,
  self,
  ...
}: {
  home.packages = [
    # self.packages.${pkgs.system}.spotify-adblock
  ];
}
