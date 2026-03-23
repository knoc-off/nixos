{
  config,
  self,
  pkgs,
  lib,
  ...
}: let
  inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) grosshack;

  pam_fprintd_grosshackSo = "${grosshack}/lib/security/pam_fprintd_grosshack.so";

  # PAM services to enable grosshack fingerprint auth on.
  # greetd is excluded — its gnome-keyring integration adds extra pam_unix
  # (unix-early) before grosshack, causing multiple password prompts.
  pamServices = [
    "sudo"
    "login"
    "polkit-1"
    "swaylock"
    "noctalia"
    "noctalia-shell"
    "system-local-login"
  ];

  mkGrosshackService = name: {
    ${name} = {
      # Disable the default sequential pam_fprintd.so — grosshack replaces it.
      fprintAuth = false;

      # Insert grosshack immediately before pam_unix in the auth chain.
      # grosshack starts the fingerprint reader in a background thread and
      # returns immediately, so pam_unix can prompt for the password while
      # the reader is active.
      rules.auth.fprintd-grosshack = {
        order = config.security.pam.services.${name}.rules.auth.unix.order - 10;
        control = "sufficient";
        modulePath = pam_fprintd_grosshackSo;
      };
    };
  };
in {
  services.fprintd.enable = true;

  security.pam.services = lib.mkMerge ([
      # Explicitly disable standard fprintd on the greeter.
      {greetd.fprintAuth = false;}
    ]
    ++ (map mkGrosshackService pamServices));

  # Restart fprintd after resume from suspend/hibernate.
  # Lock screens that poll fprintd leave the dbus session in a broken state
  # after suspend because calls are interrupted mid-operation. Restarting
  # fprintd recovers the fingerprint reader cleanly.
  systemd.services.fprintd-resume = {
    description = "Restart fprintd after resume";
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    wantedBy = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart fprintd.service";
    };
  };
}
