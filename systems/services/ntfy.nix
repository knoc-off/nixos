{config, ...}: {
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.niko.ink";
      behind-proxy = true;
      upstream-base-url = "https://ntfy.sh";

      auth-default-access = "deny-all";
      enable-login = true;
    };

    environmentFile = config.sops.secrets."services/ntfy/env".path;
  };
}
