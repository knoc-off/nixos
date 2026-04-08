{config, ...}: {
  sops.secrets."services/oauth2-proxy/env" = {
    restartUnits = ["oauth2-proxy.service"];
  };

  services.oauth2-proxy = {
    enable = true;
    provider = "github";
    reverseProxy = true;
    setXauthrequest = true;

    keyFile = config.sops.secrets."services/oauth2-proxy/env".path;

    cookie = {
      domain = ".niko.ink";
      secure = true;
      httpOnly = true;
    };

    redirectURL = "https://auth.niko.ink/oauth2/callback";

    email.addresses = ''
      selby@niko.ink
      git@tilley.cc
    '';

    email.domains = ["*"];

    extraConfig = {
      approval-prompt = "auto"; # skip prompt for returning users
      whitelist-domain = ".niko.ink";
    };
  };
}
