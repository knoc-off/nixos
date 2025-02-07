{self, pkgs, lib, ...}:
{
  systemd.services.axum-website = {
    description = "Axum Web Server";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      # Create persistent state directory for the database
      StateDirectory = "axum-website";
      # Create runtime directory for temporary files
      RuntimeDirectory = "axum-website";
      WorkingDirectory = "/var/lib/axum-website";

      ExecStartPre = [
        # Copy static files
        "+${pkgs.coreutils}/bin/cp -r ${self.packages.${pkgs.system}.website.axum}/share/static /run/axum-website/"
        # result/share/static/{css,fonts,icons,js}

        "+${pkgs.coreutils}/bin/mkdir -p /var/lib/axum-website/user-content"
        "+${pkgs.chown}/bin/chown -R axum:axum /var/lib/axum-website"
      ];
      ExecStart = "${self.packages.${pkgs.system}.website.axum}/bin/axum-website";
      Restart = "always";
      RestartSec = "10";
      User = "axum";
      Group = "axum";
      # Give write permissions to the service directories
      UMask = "0022";
      ProtectSystem = "full";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };

  users.users.axum = {
    isSystemUser = true;
    group = "axum";
    description = "Axum website service user";
  };

  users.groups.axum = {};
}
