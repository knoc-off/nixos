# lspmux - LSP multiplexer
# NixOS side: systemd service + system package
# HM side: config file generation (TOML) + session tooling
#
# The named-session commands (`lspmux-session`, `lspmux-attach`) and the
# environment allowlist they share with `pass_environment` live in
# pkgs/lspmux-session, not here -- the opencode sandbox needs them in its
# toolbelt, and packages can't reach into home-manager modules.
{ inputs, self }:
let
  lspmuxPkg = system: self.packages.${system}.lspmux;
  sessionPkg = system: self.packages.${system}.lspmux-session;
in
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.lspmux;
    in
    {
      options.services.lspmux = {
        enable = lib.mkEnableOption "lspmux LSP multiplexer";

        package = lib.mkOption {
          type = lib.types.package;
          default = lspmuxPkg pkgs.stdenv.hostPlatform.system;
          description = "The lspmux package to use";
        };

        # rust-analyzer, cargo check and its parallel rustc all share this
        # cgroup; uncapped they exhaust RAM and thrash the box into a freeze.
        memoryHigh = lib.mkOption {
          type = lib.types.str;
          default = "40%";
          description = "MemoryHigh for lspmux.service -- soft limit, throttles and reclaims.";
        };

        memoryMax = lib.mkOption {
          type = lib.types.str;
          default = "50%";
          description = "MemoryMax for lspmux.service -- hard limit, triggers a cgroup-scoped OOM kill.";
        };

        memorySwapMax = lib.mkOption {
          type = lib.types.str;
          default = "4G";
          description = "MemorySwapMax for lspmux.service. Stops lspmux pushing swap deep enough to starve the system.";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.user.services.lspmux = {
          description = "Language server multiplexer";
          wantedBy = [ "default.target" ];

          serviceConfig = {
            Type = "simple";
            ExecStart = "${cfg.package}/bin/lspmux server";
            Restart = "on-failure";
            RestartSec = 5;

            MemoryAccounting = true;
            MemoryHigh = cfg.memoryHigh;
            MemoryMax = cfg.memoryMax;
            MemorySwapMax = cfg.memorySwapMax;

            # Default "stop" would kill the multiplexer whenever one child rustc
            # gets OOM-killed; "continue" loses only the child.
            OOMPolicy = "continue";

            ManagedOOMMemoryPressure = "kill";
            ManagedOOMMemoryPressureLimit = "50%";
          };
        };

        environment.systemPackages = [ cfg.package ];
      };
    };

  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.lspmux;
      tomlFormat = pkgs.formats.toml { };
      configFile = tomlFormat.generate "lspmux-config" cfg.settings;
      sessionTools = sessionPkg pkgs.stdenv.hostPlatform.system;
    in
    {
      options.services.lspmux = {
        settings = lib.mkOption {
          type = tomlFormat.type;
          default = { };
          description = ''
            lspmux configuration options (converted to TOML).
            See https://codeberg.org/p2502/lspmux for available options.

            `instance_timeout` and `pass_environment` have module-provided
            defaults. Entries added to `pass_environment` here are concatenated
            with the defaults rather than replacing them.
          '';
          example = lib.literalExpression ''
            {
              gc_interval = 10;
              listen = ["127.0.0.1" 27631];
              log_filters = "info";
              pass_environment = ["MY_PROJECT_VAR" "!NOISY_VAR"];
            }
          '';
        };
      };

      config = {
        services.lspmux.settings = {
          # Sessions are managed by hand (`lspmux-session save` / `kill`), so an
          # idle instance is a deliberately parked one, not a stale cache entry.
          instance_timeout = lib.mkDefault false;
          pass_environment = sessionTools.envAllowlist;
        };

        home.packages = [ sessionTools ];

        # The `directories` crate uses platform-native config paths
        home.file = lib.mkIf pkgs.stdenv.isDarwin {
          "Library/Application Support/lspmux/config.toml".source = configFile;
        };
        xdg.configFile = lib.mkIf (!pkgs.stdenv.isDarwin) {
          "lspmux/config.toml".source = configFile;
        };
      };
    };
}
