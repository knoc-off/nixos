{
  pkgs,
  config,
  ...
}: {

  services.gnome.localsearch.enable = true;

  # add totem package to the system
  environment.systemPackages = with pkgs; [
    totem
  ];


}
