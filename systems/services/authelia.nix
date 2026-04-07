{config, ...}: let
  instance = "main";
  user = "authelia-${instance}";
in {
  sops.secrets = {
    "services/authelia/jwt-secret" = {
      owner = user;
      mode = "0400";
    };
    "services/authelia/session-secret" = {
      owner = user;
      mode = "0400";
    };
    "services/authelia/storage-encryption-key" = {
      owner = user;
      mode = "0400";
    };
    "services/authelia/users" = {
      owner = user;
      mode = "0400";
    };
  };

  services.authelia.instances.${instance} = {
    enable = true;
    secrets = {
      jwtSecretFile = config.sops.secrets."services/authelia/jwt-secret".path;
      sessionSecretFile = config.sops.secrets."services/authelia/session-secret".path;
      storageEncryptionKeyFile = config.sops.secrets."services/authelia/storage-encryption-key".path;
    };
    settings = {
      theme = "auto";
      server.address = "tcp://127.0.0.1:9091";

      log = {
        level = "info";
        format = "text";
        file_path = "/var/log/authelia/authelia.log";
        keep_stdout = true;
      };

      # File-backed user database; decrypted by sops-nix at runtime
      authentication_backend.file.path = config.sops.secrets."services/authelia/users".path;

      # Session cookie scoped to the apex so all subdomains share the session
      session.cookies = [
        {
          domain = "niko.ink";
          authelia_url = "https://auth.niko.ink";
        }
      ];

      storage.local.path = "/var/lib/authelia-${instance}/db.sqlite3";

      # Filesystem notifier because there is no SMTP configured; password
      # reset links land in this file for manual retrieval.
      notifier.filesystem.filename = "/var/lib/authelia-${instance}/notifications.txt";

      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = ["*.niko.ink"];
            policy = "one_factor";
          }
        ];
      };
    };
  };

  # LogsDirectory tells systemd to create /var/log/authelia/ and add it to
  # ReadWritePaths, which is needed because the module sets ProtectSystem=strict.
  # UMask 0027 makes logs group-readable for CrowdSec.
  systemd.services.authelia-main.serviceConfig = {
    LogsDirectory = "authelia";
    UMask = "0027";
  };
}
