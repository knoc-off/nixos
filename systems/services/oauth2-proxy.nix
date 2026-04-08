{config, ...}: {
  sops.secrets."services/oauth2-proxy/env" = {
    restartUnits = ["oauth2-proxy.service"];
  };

  services.oauth2-proxy = {
    enable = true;
    provider = "github";
    reverseProxy = true;
    setXauthrequest = true;

    # Secrets (client-id, client-secret, cookie-secret) loaded from sops
    # env file so they don't leak into the nix store or /proc.
    keyFile = config.sops.secrets."services/oauth2-proxy/env".path;

    cookie = {
      domain = ".niko.ink";
      secure = true;
      httpOnly = true;
    };

    redirectURL = "https://auth.niko.ink/oauth2/callback";

    email.addresses = ''
      selby@niko.ink
      placeholder@example.com
    '';

    # Allow any email domain -- actual restriction is via the addresses above
    email.domains = ["*"];

    extraConfig = {
      # Show "auto" prompt so returning users skip the provider choice
      approval-prompt = "auto";
      whitelist-domain = ".niko.ink";
    };
  };
}
