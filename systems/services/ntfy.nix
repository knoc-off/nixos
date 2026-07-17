{config, ...}: let
  ph = name: config.sops.placeholder.${name};
in {
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.niko.ink";
      behind-proxy = true;
      upstream-base-url = "https://ntfy.sh";

      auth-default-access = "deny-all";
      enable-login = true;

      # ACLs are authoritative here; NTFY_AUTH_ACCESS must stay unset (env
      # overrides server.yml per-key). admin needs no entry (role = all topics).
      auth-access = [
        "normal:cat-doorbell:ro"
        "normal:shopping-list:ro"
        "publisher:cat-doorbell:wo"
        "publisher:shopping-list:wo"
      ];
    };

    environmentFile = config.sops.templates."ntfy.env".path;
  };

  # Single-source the publisher token: publish-token is the one place it lives;
  # ntfy and both publishing clients read from it. Only literal scaffolding hits
  # the store; hashes/tokens are placeholders resolved at activation.
  sops.templates."ntfy.env".content = ''
    NTFY_AUTH_USERS=admin:${ph "services/ntfy/admin-hash"}:admin,normal:${ph "services/ntfy/normal-hash"}:user,publisher:${ph "services/ntfy/publisher-hash"}:user
    NTFY_AUTH_TOKENS=publisher:${ph "services/ntfy/publish-token"}
  '';
}
