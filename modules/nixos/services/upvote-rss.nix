# Upvote RSS - RSS feed generator from Reddit, HN, Lobsters, Lemmy, etc.
# Runs as a PHP-FPM service with optional nginx frontend and Redis caching.
{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.services.upvote-rss;

  # Build the PHP with required extensions
  phpPackage = pkgs.php.withExtensions ({enabled, all}:
    enabled
    ++ [
      all.gd
      all.apcu
    ]);

  # The app's webroot -- a mutable working copy derived from the immutable
  # Nix store package, with cache/logs symlinked from the state directory.
  appRoot = "${cfg.dataDir}/webroot";

  # Convert settings attrset to environment variable list
  envVars =
    lib.mapAttrs' (name: value: lib.nameValuePair name (toString value)) cfg.settings
    // lib.optionalAttrs (cfg.redis.host != null) {
      REDIS_HOST = cfg.redis.host;
      REDIS_PORT = toString cfg.redis.port;
    };

  # PHP-FPM pool name
  poolName = "upvote-rss";

  # PHP-FPM socket path (NixOS convention)
  fpmSocket = config.services.phpfpm.pools.${poolName}.socket;
in {
  options.services.upvote-rss = {
    enable = lib.mkEnableOption "upvote-rss RSS feed generator";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.upvote-rss;
      description = "The upvote-rss package to use.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address for the PHP-FPM pool to listen on (used by the web server).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8675;
      description = "Port for the service. Used for firewall and web server config.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/upvote-rss";
      description = "Directory for upvote-rss state (cache, logs, and working copy of the app).";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "upvote-rss";
      description = "User account under which upvote-rss runs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "upvote-rss";
      description = "Group under which upvote-rss runs.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an environment file loaded by the PHP-FPM service.
        Use this for secrets (Reddit API credentials, AI API keys, etc.)
        that should not end up in the Nix store.

        Example contents:
          REDDIT_USER=myuser
          REDDIT_CLIENT_ID=abc123
          REDDIT_CLIENT_SECRET=secret
          OPENAI_API_KEY=sk-...
      '';
      example = "/run/secrets/upvote-rss-env";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = ''
        Environment variable overrides for upvote-rss configuration.
        These are non-secret settings passed to the PHP-FPM pool.
        See https://github.com/johnwarne/upvote-rss for all available options.
      '';
      example = lib.literalExpression ''
        {
          TZ = "America/New_York";
          MAX_EXECUTION_TIME = "120";
          DEBUG = "true";
          DEMO_MODE = "false";
          SUMMARY_TEMPERATURE = "0.4";
          SUMMARY_MAX_TOKENS = "1000";
        }
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to open the firewall for the upvote-rss port.";
    };

    nginx = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to configure an nginx virtualhost for upvote-rss.";
      };

      domain = lib.mkOption {
        type = lib.types.str;
        description = "Domain name for the nginx virtualhost.";
        example = "upvote.example.com";
      };

      forceSSL = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to force SSL on the nginx virtualhost.";
      };

      enableACME = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to enable ACME (Let's Encrypt) for the nginx virtualhost.";
      };
    };

    redis = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to automatically provision a local Redis instance
          for upvote-rss caching. When enabled, a dedicated Redis
          server is created and the REDIS_HOST/REDIS_PORT are
          configured automatically.
        '';
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Redis host for distributed caching.
          Automatically set when redis.createLocally is true.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Auto-set redis host when creating locally
    services.upvote-rss.redis.host = lib.mkIf cfg.redis.createLocally "127.0.0.1";

    # Create system user/group
    users.users.${cfg.user} = lib.mkIf (cfg.user == "upvote-rss") {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      description = "Upvote RSS service user";
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "upvote-rss") {};

    # Firewall
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [cfg.port];

    # Local Redis instance
    services.redis.servers.upvote-rss = lib.mkIf cfg.redis.createLocally {
      enable = true;
      port = cfg.redis.port;
      bind = "127.0.0.1";
    };

    # Ensure state directories exist
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/cache 0750 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir}/logs 0750 ${cfg.user} ${cfg.group} -"
    ];

    # Prepare the mutable webroot from the immutable package
    # This runs before PHP-FPM starts, creating a working copy of the app
    # with cache/ and logs/ symlinked from the state directory.
    systemd.services.upvote-rss-setup = {
      description = "Upvote RSS webroot setup";
      after = ["local-fs.target"];
      before = ["phpfpm-${poolName}.service"];
      requiredBy = ["phpfpm-${poolName}.service"];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        RemainAfterExit = true;
        StateDirectory = "upvote-rss";
        StateDirectoryMode = "0750";

        # Hardening
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged"];
        ReadWritePaths = [cfg.dataDir];
      };

      script = ''
        # Create/update the mutable webroot from the Nix store package
        mkdir -p "${appRoot}"

        # Sync app files from the package (immutable source of truth)
        ${pkgs.rsync}/bin/rsync -a --delete \
          --exclude='cache' \
          --exclude='logs' \
          --exclude='.env' \
          "${cfg.package}/share/upvote-rss/" "${appRoot}/"

        # Ensure mutable dirs exist and are symlinked
        mkdir -p "${cfg.dataDir}/cache"
        mkdir -p "${cfg.dataDir}/logs"

        # Create symlinks for mutable directories
        ln -sfn "${cfg.dataDir}/cache" "${appRoot}/cache"
        ln -sfn "${cfg.dataDir}/logs" "${appRoot}/logs"

        # Create .env symlink if environmentFile is provided
        ${lib.optionalString (cfg.environmentFile != null) ''
          ln -sfn "${cfg.environmentFile}" "${appRoot}/.env"
        ''}
      '';
    };

    # PHP-FPM pool
    services.phpfpm.pools.${poolName} = {
      user = cfg.user;
      group = cfg.group;

      phpPackage = phpPackage;

      settings = {
        # When nginx is enabled, let the nginx user read the socket
        "listen.owner" =
          if cfg.nginx.enable
          then config.services.nginx.user
          else cfg.user;
        "listen.group" =
          if cfg.nginx.enable
          then config.services.nginx.group
          else cfg.group;
        "listen.mode" = "0660";

        "pm" = "dynamic";
        "pm.max_children" = 10;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 4;
        "pm.max_requests" = 500;

        # PHP settings
        "php_admin_value[error_log]" = "${cfg.dataDir}/logs/php-error.log";
        "php_admin_flag[log_errors]" = true;
        "php_value[max_execution_time]" = cfg.settings.MAX_EXECUTION_TIME or "60";

        # Security: disable dangerous PHP functions
        # Note: parse_ini_file is needed by config.php to read .env
        "php_admin_value[disable_functions]" = "exec,passthru,shell_exec,system,proc_open,popen";
        "php_admin_value[expose_php]" = "Off";
        "php_admin_value[allow_url_fopen]" = "On";
        "php_admin_value[allow_url_include]" = "Off";
        "php_admin_value[open_basedir]" = "${appRoot}:${cfg.dataDir}:/tmp";
      };

      phpEnv = envVars;
    };

    # Harden the PHP-FPM systemd service
    systemd.services."phpfpm-${poolName}".serviceConfig = {
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      RestrictSUIDSGID = true;
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
      ReadWritePaths = [cfg.dataDir];
      # PHP needs write+execute for opcache/JIT
      # MemoryDenyWriteExecute = true; -- incompatible with PHP opcache
    };

    # Nginx virtualhost
    services.nginx = lib.mkIf cfg.nginx.enable {
      enable = true;

      virtualHosts.${cfg.nginx.domain} = {
        forceSSL = cfg.nginx.forceSSL;
        enableACME = cfg.nginx.enableACME;

        root = appRoot;
        index = "index.php";

        # Security headers
        extraConfig = ''
          add_header X-Content-Type-Options "nosniff" always;
          add_header X-Frame-Options "SAMEORIGIN" always;
          add_header X-XSS-Protection "1; mode=block" always;
          add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        '';

        # Serve static files directly, fall back to index.php for routing
        locations."/" = {
          tryFiles = "$uri $uri/ /index.php$is_args$args";
        };

        # Pass PHP scripts to the FPM pool
        locations."~ \\.php$" = {
          extraConfig = ''
            fastcgi_pass unix:${fpmSocket};
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include ${pkgs.nginx}/conf/fastcgi_params;
            include ${pkgs.nginx}/conf/fastcgi.conf;

            # Increase timeouts for long-running feed generation
            fastcgi_read_timeout 120s;
            fastcgi_send_timeout 120s;
          '';
        };

        # Server-Sent Events endpoint needs special buffering config
        locations."= /progress-sse.php" = {
          extraConfig = ''
            fastcgi_pass unix:${fpmSocket};
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
            include ${pkgs.nginx}/conf/fastcgi_params;
            include ${pkgs.nginx}/conf/fastcgi.conf;

            # SSE-specific: disable buffering so events stream in real-time
            fastcgi_buffering off;
            proxy_buffering off;
            chunked_transfer_encoding off;
            fastcgi_read_timeout 300s;
          '';
        };

        # Block access to dotfiles (.env, .git, etc.)
        locations."~ /\\." = {
          extraConfig = ''
            deny all;
            return 404;
          '';
        };

        # Cache static assets
        locations."~* \\.(css|js|ico|png|jpg|jpeg|gif|svg|woff|woff2)$" = {
          extraConfig = ''
            expires 7d;
            add_header Cache-Control "public, immutable";
          '';
        };
      };
    };
  };
}
