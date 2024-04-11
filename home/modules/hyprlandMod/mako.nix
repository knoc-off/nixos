{
  pkgs,
  theme,
  config,
  ...
}: {
  services.mako = {
    enable = true;
  };
}
