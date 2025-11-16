{
  config,
  pkgs,
  ...
}: {
  # WebDAV server for rclone sync
  services.nginx = {
    enable = true;

    # Enable DAV module
    additionalModules = [pkgs.nginxModules.dav];

    virtualHosts."sync.niko.ink" = {
      forceSSL = true;
      enableACME = true;

      locations."/" = {
        root = "/var/lib/webdav";
        extraConfig = ''
          # WebDAV support
          dav_methods PUT DELETE MKCOL COPY MOVE;
          dav_ext_methods PROPFIND OPTIONS;
          dav_access user:rw group:rw;

          # Create intermediate directories
          create_full_put_path on;

          # Basic auth
          auth_basic "Sync Storage";
          auth_basic_user_file ${config.sops.secrets."services/webdav/htpasswd".path};

          # Increase client body size for large files
          client_max_body_size 10G;
          client_body_temp_path /var/lib/webdav/tmp;

          # Better performance
          sendfile on;
          tcp_nopush on;
          tcp_nodelay on;

          # Reduce latency
          keepalive_timeout 65;
          keepalive_requests 100;

          # Suppress "File exists" error logs
          error_page 405 =200 $uri;
        '';
      };
    };
  };

  # Allow nginx to write to WebDAV directory despite ProtectSystem=strict
  systemd.services.nginx.serviceConfig = {
    ReadWritePaths = ["/var/lib/webdav"];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/webdav 0777 nginx nginx -"
    "d /var/lib/webdav/tmp 0777 nginx nginx -"
  ];

  sops.secrets."services/webdav/htpasswd" = {
    mode = "0440";
    owner = "nginx";
    group = "nginx";
  };
}
