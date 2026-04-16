{
  self,
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.compat-proxy;
  system = pkgs.stdenv.hostPlatform.system;

  # Generate a single TOML rule file from a client config attrset.
  mkRuleToml = name: client: let
    replacementLines =
      concatMapStringsSep "\n" (r: ''
        [[system_prompt.text_replacements]]
        find = ${builtins.toJSON r.find}
        replace = ${builtins.toJSON r.replace}
      '')
      client.textReplacements;

    renameLines =
      concatMapStringsSep "\n" (r: ''
        [[tools.rename]]
        from = ${builtins.toJSON r.from}
        to_schema = ${builtins.toJSON r.to}
      '')
      client.toolRenames;

    dropLines =
      concatMapStringsSep "\n" (t: ''
        [[tools.drop]]
        name = ${builtins.toJSON t}
      '')
      client.toolDrops;
  in
    pkgs.writeText "${name}.toml" ''
      [meta]
      client_name = ${builtins.toJSON name}
      target_cc_version = ${builtins.toJSON client.targetVersion}

      [system_prompt]
      detect = ${builtins.toJSON client.systemPrompt.detect}
      replace_with_file = ${builtins.toJSON client.systemPrompt.replaceWithFile}

      ${replacementLines}

      [tools]
      unmapped_policy = ${builtins.toJSON client.unmappedPolicy}

      ${renameLines}

      ${dropLines}

      [properties]

      [headers]
      inject = []

      [billing]
      inject_block = ${boolToString client.billing.injectBlock}
      cc_version = ${builtins.toJSON client.billing.ccVersion}
    '';

  # Assemble a rules directory from all client configs + the bundled schema registry.
  bundledRules = "${cfg.package}/share/compat-proxy/rules";

  rulesDir = pkgs.runCommand "compat-proxy-rules" {} (''
      mkdir -p $out
      # Copy schema registry and system prompts from the package
      cp ${bundledRules}/cc-schemas.toml $out/
      cp -r ${bundledRules}/system-prompts $out/
    ''
    + concatStringsSep "\n" (mapAttrsToList (
        name: client: "cp ${mkRuleToml name client} $out/${name}.toml"
      )
      cfg.clients));

  textReplacementType = types.submodule {
    options = {
      find = mkOption {
        type = types.str;
        description = "Text to find.";
      };
      replace = mkOption {
        type = types.str;
        description = "Replacement text.";
      };
    };
  };

  toolRenameType = types.submodule {
    options = {
      from = mkOption {
        type = types.str;
        description = "Client tool name.";
      };
      to = mkOption {
        type = types.str;
        description = "Canonical schema name.";
      };
    };
  };

  clientType = types.submodule {
    options = {
      targetVersion = mkOption {
        type = types.str;
        default = "2.1.97";
        description = "Target Claude Code version to emulate.";
      };

      systemPrompt = {
        detect = mkOption {
          type = types.str;
          description = "Substring to detect in the client's system prompt.";
        };

        replaceWithFile = mkOption {
          type = types.str;
          default = "system-prompts/cc-2.1.97.txt";
          description = "Replacement system prompt file, relative to rules dir.";
        };
      };

      textReplacements = mkOption {
        type = types.listOf textReplacementType;
        default = [];
        description = "Text replacements applied after system prompt replacement.";
      };

      toolRenames = mkOption {
        type = types.listOf toolRenameType;
        default = [];
        description = "Tool name mappings from client names to canonical schema names.";
      };

      toolDrops = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Tool names to drop silently.";
      };

      unmappedPolicy = mkOption {
        type = types.enum ["error" "drop" "passthrough"];
        default = "error";
        description = "Policy for tools with no mapping rule.";
      };

      billing = {
        injectBlock = mkOption {
          type = types.bool;
          default = true;
          description = "Inject billing header block into the system prompt.";
        };

        ccVersion = mkOption {
          type = types.str;
          default = "2.1.97";
          description = "Claude Code version for billing fingerprint.";
        };
      };
    };
  };
in {
  options.services.compat-proxy = {
    enable = mkEnableOption "compat-proxy, a typed API compatibility proxy";

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

    dumpRequests = mkOption {
      type = types.bool;
      default = false;
      description = "Dump request/response bodies for debugging. WARNING: logs sensitive data.";
    };

    clients = mkOption {
      type = types.attrsOf clientType;
      default = {};
      description = "Client rule definitions. Each key becomes a TOML rule file.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [cfg.package];

    # Generate the rules directory into XDG config
    xdg.configFile."compat-proxy/rules".source = rulesDir;

    home.sessionVariables.OPENCODE_PROXY_URL = "http://127.0.0.1:58192/v1";

    systemd.user.services.compat-proxy = {
      Unit = {
        Description = "compat-proxy API compatibility proxy";
        After = ["network.target"];
      };

      Service = {
        ExecStart = concatStringsSep " " ([
            "${lib.getExe cfg.package}"
            "--rules-dir ${config.xdg.configHome}/compat-proxy/rules"
            "--schema-registry ${config.xdg.configHome}/compat-proxy/rules/cc-schemas.toml"
            "--credentials-path ${cfg.credentialsPath}"
            "--upstream-url ${cfg.upstreamUrl}"
            "--log-level ${cfg.logLevel}"
          ]
          ++ optional (cfg.port != null) "--port ${toString cfg.port}"
          ++ optional (cfg.socket != null) "--socket ${cfg.socket}"
          ++ optional cfg.dumpRequests "--dump-requests");
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = ["default.target"];
      };
    };
  };
}
