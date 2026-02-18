{
  home = import ./home.nix;
  services.lspmux = import ./services/lspmux.nix;
}
