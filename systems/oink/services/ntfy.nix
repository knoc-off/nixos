{ config, ... }:
let
  ph = name: config.sops.placeholder.${name};
in
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.niko.ink";
      behind-proxy = true;
      upstream-base-url = "https://ntfy.sh";

      auth-default-access = "deny-all";
      enable-login = true;

      # The message cache is in-memory by default, so an ntfy restart drops
      # anything not yet delivered. ovwatch polls its command topic on a timer
      # rather than holding a stream open, so a restart between publishing a
      # command and the next tick would silently swallow it.
      cache-file = "/var/lib/ntfy-sh/cache.db";

      # ACLs are authoritative here; NTFY_AUTH_ACCESS must stay unset (env
      # overrides server.yml per-key). admin needs no entry (role = all topics).
      auth-access = [
        "normal:alerts:ro"
        "normal:cat-doorbell:ro"
        "normal:kitchenowl:ro"
        "normal:nixbuild:ro"
        # rw for both: ovwatch shares one topic for notifications and for the
        # commands that manage subscriptions, so each side must read and write.
        "normal:ovwatch:rw"
        "normal:wohnungen:ro"
        "publisher:alerts:wo"
        "publisher:cat-doorbell:wo"
        "publisher:kitchenowl:wo"
        "publisher:nixbuild:wo"
        "publisher:ovwatch:rw"
        "publisher:wohnungen:wo"
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
