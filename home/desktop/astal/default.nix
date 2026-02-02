{
  outputs,
  self,
  pkgs,
  upkgs,
  user,
  inputs,
  system,
  color-lib,
  theme,
  ...
}: {
  home.packages = [
    inputs.astal.packages.${system}.default

    (inputs.ags.packages.${system}.default.override {
      extraPackages = with inputs.astal.packages.${system}; [
        notifd
        mpris
        network
        battery
        bluetooth
        powerprofiles
        tray
      ];
    })

    (self.packages.${pkgs.stdenv.hostPlatform.system}.astal-widget-wrapper {
      path = ./configs/notifications;
      entry = "app.tsx";
      name = "astal-notify";
    })
  ];
}

