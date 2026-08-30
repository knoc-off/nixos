# Aggregates per-window key layers contributed by app modules and the user's
# `base` layer, then wires the assembled result into kanata + a generated
# Hyprland Lua fragment that switches kanata layers on window focus change.
#
# App modules (firefox, ghostty, slack, zen-browser, ...) contribute their
# slice via `keyLayers.layers.<name>`. The layer schema is documented in
# lib/key-layers.nix; shared building blocks live in `self.lib.keyLayers.presets`.
#
# There used to be a third leg here: hyprkan, a Python daemon that watched
# Hyprland's IPC socket, matched window class against a JSON rule file, and
# forwarded layer switches to kanata over TCP. Hyprland's own Lua config
# (configType = "lua") already gets a window-focus callback with the class
# on it for free, so the daemon, its rule schema, and the JSON intermediary
# were redundant -- this module now emits the equivalent ~30-line Lua
# fragment directly. Pulled in from hypr/hyprland.lua via
# `pcall(require, "kanata-app-layers")`, same pattern as the optional
# user.lua override -- the file only exists when keyLayers.enable is set.
{ self, ... }: {
  home =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    with lib;
    let
      cfg = config.keyLayers;
      inherit (self.lib.keyLayers) mkKeyLayers;

      modNames = [
        "ctrl"
        "shift"
        "alt"
      ];

      # A single key/chord action: bare key, modified key, shell command, or a
      # raw escape-hatch kanata expression. Shared by capsbinds.keys entries,
      # simple binds, and each branch of a fork.
      actionSubmodule = types.submodule {
        options = {
          mod = mkOption {
            type = types.nullOr (types.enum modNames);
            default = null;
            description = "Modifier to combine with `key` (or the bound key itself if `key` is unset).";
          };
          key = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Target key name. Defaults to the bound/held key's own name.";
          };
          cmd = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Shell command to run instead of emitting a key.";
          };
          raw = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Raw kanata action expression (escape hatch).";
          };
        };
      };

      # String shorthand (e.g. "ctrl" or "down") or an explicit actionSubmodule.
      actionType = types.either types.str actionSubmodule;

      # A bind key's value: either a simple action, or a fork over currently
      # held modifiers (each branch an actionType). lib/key-layers.nix's
      # `isFork` distinguishes the two by which fields are present after
      # null-stripping below.
      bindSubmodule = types.submodule {
        options =
          {
            mod = mkOption {
              type = types.nullOr (types.enum modNames);
              default = null;
            };
            key = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            cmd = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            raw = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          }
          // genAttrs
            [
              "default"
              "shift"
              "ctrl"
              "alt"
              "alt_ctrl"
              "alt_shift"
              "ctrl_shift"
              "alt_ctrl_shift"
            ]
            (
              _:
              mkOption {
                type = types.nullOr actionType;
                default = null;
              }
            );
      };
      bindType = types.either types.str bindSubmodule;

      capsbindsSubmodule = types.submodule {
        options = {
          ctrl = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          shift = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          alt = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          keys = mkOption {
            type = types.attrsOf actionType;
            default = { };
          };
        };
      };

      layerSubmodule = types.submodule {
        options = {
          classes = mkOption {
            type = types.listOf types.str;
            default = [ ];
          };
          capsbinds = mkOption {
            type = capsbindsSubmodule;
            default = { };
          };
          binds = mkOption {
            type = types.attrsOf bindType;
            default = { };
          };
        };
      };

      # Submodule evaluation fills every unset option with `null` instead of
      # omitting it, but the compiler in lib/key-layers.nix distinguishes
      # "field present" from "field absent" (`action ? mod`, `isFork`'s
      # field-presence check) -- so strip nulls before handing layers over.
      layers = filterAttrsRecursive (_: v: v != null) cfg.layers;
      kl = mkKeyLayers layers;

      port = (config.services.kanata.keyboards.${cfg.kanataKeyboard} or { }).port or null;

      # ponytail: exact class match only, no title/regex matching -- add
      # `w.title` / string.find into the Lua below if a layer ever needs it.
      ruleLines = concatMapStringsSep ",\n  " (
        r: ''{ class = "${escape [ "\\" "\"" ] r.class}", layer = "${r.layer}" }''
      ) kl.windowRules;
    in
    {
      options.keyLayers = {
        enable = mkEnableOption "per-window kanata layer switching (kanata config + Hyprland Lua)";

        layers = mkOption {
          type = types.attrsOf layerSubmodule;
          default = { };
          description = ''
            Map of layer name to layer definition, merged from app modules and the
            user config. See lib/key-layers.nix for the layer schema. "base" is the
            wildcard fallback for unmatched windows.
          '';
        };

        extraAliases = mkOption {
          type = types.lines;
          default = "";
          description = ''
            Extra kanata aliases injected into the generated config (host-specific,
            e.g. the application launcher command).
          '';
        };

        kanataKeyboard = mkOption {
          type = types.str;
          default = "main";
          description = "Name of the services.kanata.keyboards entry to populate and read the TCP port from.";
        };
      };

      config = mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.layers ? base;
            message = "keyLayers.enable is set but no `base` layer is defined.";
          }
          {
            assertion = port != null;
            message = "keyLayers.enable requires services.kanata.keyboards.${cfg.kanataKeyboard}.port to be set.";
          }
        ];

        services.kanata.keyboards.${cfg.kanataKeyboard}.config = kl.kanataConfig cfg.extraAliases;

        xdg.configFile."hypr/kanata-app-layers.lua".text = ''
          -- Generated by modules/keylayers. Switches kanata's active layer to
          -- match the focused window's class. Uses hl.exec_cmd (detached,
          -- fire-and-forget) per switch instead of a persistent io.popen `nc`
          -- pipe: closing that pipe runs pclose -> waitpid on the compositor
          -- main thread, and nc doesn't exit on stdin EOF, which deadlocked
          -- Hyprland whenever a home-manager activation reloaded this config
          -- while restarting kanata. `-N -w1` bounds nc's lifetime so no
          -- stray processes accumulate.
          local rules = {
            ${ruleLines}
          }

          local port = ${toString port}
          local lastLayer = nil

          local function send(layer)
            if lastLayer == layer then
              return
            end
            -- ponytail: fire-and-forget, no delivery feedback -- if kanata is
            -- down the switch is silently lost until the next layer change.
            lastLayer = layer
            hl.exec_cmd("printf '%s\\n' '{\"ChangeLayer\":{\"new\":\"" .. layer .. "\"}}'"
              .. " | ${lib.getExe pkgs.netcat-openbsd} -N -w1 127.0.0.1 " .. port)
          end

          local function layerFor(class)
            for _, rule in ipairs(rules) do
              if class == rule.class then
                return rule.layer
              end
            end
            return "base"
          end

          hl.on("window.active", function(w)
            if w and w.class then
              send(layerFor(w.class))
            end
          end)
        '';
      };
    };
}
