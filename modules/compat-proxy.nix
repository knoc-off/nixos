{ self, ... }: {
  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    with lib;
    let
      cfg = config.services.compat-proxy;
      system = pkgs.stdenv.hostPlatform.system;
    in
    {
      options.services.compat-proxy = {
        enable = mkEnableOption "compat-proxy, an OAuth shim that lets Anthropic-compatible clients use Claude Code credentials";

        package = mkOption {
          type = types.package;
          default = self.packages.${system}.compat-proxy;
          description = "The compat-proxy package to use.";
        };

        credentialsPath = mkOption {
          type = types.str;
          default = "${config.home.homeDirectory}/.claude/.credentials.json";
          description = "Path to Claude credentials JSON file.";
        };

        upstreamUrl = mkOption {
          type = types.str;
          default = "https://api.anthropic.com";
          description = "Upstream Anthropic API base URL.";
        };

        port = mkOption {
          type = types.nullOr types.port;
          default = null;
          description = "TCP port to bind to. If null, uses a Unix socket instead.";
        };

        socket = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Unix socket path. Used when port is not set.";
        };

        logLevel = mkOption {
          type = types.str;
          default = "info";
          description = "Log level filter.";
        };

        dumpDir = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Directory to dump shaped requests into (one JSON file per
            exchange, in a per-run subdirectory keyed by session ID).
            Records contain full prompts and conversation history --
            leave unset outside of debugging.
          '';
        };

        maxTokens = mkOption {
          type = types.nullOr types.int;
          default = 64000;
          description = ''
            Override `max_tokens` on every request (real CC sends 64000).
            Set to null to leave the client's own `max_tokens` untouched.
          '';
        };

        injectThinking = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Inject `thinking: {type: "adaptive"}` on models the client
            didn't already request thinking on. Off by default: "adaptive"
            only exists on specific newer model families (Opus/Sonnet 4.6+)
            and the API 400s outright on anything older, with no reliable
            way to tell which from the model string alone.
          '';
        };

        injectContextManagement = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Inject `context_management` clearing stale thinking blocks.
            Tied to the same model-family guesswork as `injectThinking` and
            just as unsafe to guess at, so also off by default.
          '';
        };

        stripToolChoiceAuto = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Drop `tool_choice: {type: "auto"}` (real CC omits it rather
            than sending the default explicitly). Cosmetic, not required
            for correctness.
          '';
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.port != null || cfg.socket != null;
            message = ''
              services.compat-proxy: set at least one of `port` or `socket`.
              With both null, the binary falls back to
              $XDG_RUNTIME_DIR/compat-proxy.sock on its own, but
              home.sessionVariables.OPENCODE_PROXY_URL only gets set from
              `port` -- with neither set explicitly, opencode would have
              nothing to connect to.
            '';
          }
        ];

        home.packages = [ cfg.package ];

        # opencode's `baseURL` config option needs an HTTP URL -- it can't
        # reach a Unix socket -- so this is only meaningful in port mode.
        home.sessionVariables = mkIf (cfg.port != null) {
          OPENCODE_PROXY_URL = "http://127.0.0.1:${toString cfg.port}/v1";
        };

        systemd.user.services.compat-proxy = {
          Unit = {
            Description = "compat-proxy OAuth shim";
            After = [ "network.target" ];
          };

          Service = {
            ExecStart = concatStringsSep " " (
              [
                "${lib.getExe cfg.package}"
                "--credentials-path ${cfg.credentialsPath}"
                "--upstream-url ${cfg.upstreamUrl}"
                "--log-level ${cfg.logLevel}"
              ]
              ++ optional (cfg.port != null) "--port ${toString cfg.port}"
              ++ optional (cfg.socket != null) "--socket ${cfg.socket}"
              ++ optional (cfg.dumpDir != null) "--dump-dir ${cfg.dumpDir}"
              ++ optional (cfg.maxTokens != null) "--max-tokens ${toString cfg.maxTokens}"
              ++ optional cfg.injectThinking "--inject-thinking"
              ++ optional cfg.injectContextManagement "--inject-context-management"
              ++ optional cfg.stripToolChoiceAuto "--strip-tool-choice-auto"
            );
            Restart = "on-failure";
            RestartSec = 5;
          };

          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
    };
}
