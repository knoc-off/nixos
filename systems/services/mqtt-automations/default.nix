# MQTT automation framework.
#
# Each automation file in this directory returns a simple attrset:
#   { name, script, description?, pythonPackages?, env? }
#
# The `script` field is inline Python. A prelude is injected that provides:
#   - client        : connected paho MQTT client
#   - publish(topic, payload)  : publish to MQTT (dicts auto-JSON-encoded)
#   - subscribe(topic, cb)     : subscribe with callback(topic, payload)
#   - @on_message(topic)       : decorator form of subscribe
#   - env(key, default?)       : read environment variable
#   - wait_until(datetime)     : sleep until a target time
#   - sleep(seconds)           : interruptible sleep
#   - log(msg)                 : timestamped print
#
# To add a new automation, create a .nix file in this directory and add it
# to the `automations` list below.
{
  lib,
  config,
  pkgs,
  ...
}: let
  # -- Prelude injected into every script ----------------------------------
  mqttPrelude = ''
    import os, sys, json, time, signal
    from datetime import datetime, timedelta, timezone
    import paho.mqtt.client as mqtt

    def log(msg):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

    def env(key, default=None):
        return os.environ.get(key, default)

    _mqtt_host = env("MQTT_HOST", "127.0.0.1")
    _mqtt_port = int(env("MQTT_PORT", "1883"))

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    client.connect(_mqtt_host, _mqtt_port)
    client.loop_start()

    def publish(topic, payload):
        """Publish to an MQTT topic. Dicts are JSON-encoded."""
        if isinstance(payload, dict):
            payload = json.dumps(payload)
        client.publish(topic, payload)
        log(f"-> {topic}: {payload}")

    def subscribe(topic, callback):
        """Subscribe to a topic. callback(topic: str, payload: dict|str)"""
        def _on_message(_client, _userdata, msg):
            try:
                payload = json.loads(msg.payload.decode())
            except (json.JSONDecodeError, UnicodeDecodeError):
                payload = msg.payload.decode()
            callback(msg.topic, payload)
        client.subscribe(topic)
        client.message_callback_add(topic, _on_message)
        log(f"<- subscribed: {topic}")

    def on_message(topic):
        """Decorator: @on_message("zigbee2mqtt/button")"""
        def decorator(func):
            subscribe(topic, func)
            return func
        return decorator

    def sleep(seconds):
        time.sleep(seconds)

    def wait_until(target_dt):
        """Sleep until a datetime. Returns immediately if in the past."""
        now = datetime.now(target_dt.tzinfo or None)
        delta = (target_dt - now).total_seconds()
        if delta > 0:
            log(f"waiting until {target_dt.strftime('%H:%M:%S')} ({delta:.0f}s)")
            time.sleep(delta)

    def _shutdown(sig, frame):
        log("shutting down")
        client.loop_stop()
        client.disconnect()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    log("automation started")
  '';

  # -- mkAutomation: turn an automation definition into a systemd service ---
  mkAutomation = def: let
    python = pkgs.python3.withPackages (ps:
      [ps.paho-mqtt] ++ (def.pythonPackages or (_: []) ) ps);
    scriptFile = pkgs.writeTextFile {
      name = "mqtt-auto-${def.name}.py";
      text = mqttPrelude + def.script;
    };
  in {
    "mqtt-auto-${def.name}" = {
      description = def.description or "MQTT automation: ${def.name}";
      after = ["mosquitto.service" "network-online.target"];
      wants = ["mosquitto.service" "network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${python}/bin/python -u ${scriptFile}";
        Restart = "always";
        RestartSec = "10s";
        Environment = lib.mapAttrsToList (k: v: ''"${k}=${v}"'') (def.env or {});
      } // (def.extraServiceConfig or {});
      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 20;
      };
    };
  };

  # -- mkButtonAction: generate an automation from a button -> action map ---
  #
  # Usage:
  #   mkButtonAction "zigbee2mqtt/button_1/action" {
  #     single = { topic = "zigbee2mqtt/light_1/set"; payload = { state = "TOGGLE"; }; };
  #     double = { topic = "zigbee2mqtt/light_1/set"; payload = { brightness = 254; }; };
  #   }
  #
  # Returns a mkAutomation-compatible attrset.
  mkButtonAction = button: actions: let
    # Derive a service name from the button topic
    safeName = builtins.replaceStrings ["/"] ["-"]
      (lib.removePrefix "zigbee2mqtt/" button);

    # Generate Python dict entries from the actions attrset
    actionLines = lib.concatStringsSep "\n    " (lib.mapAttrsToList
      (payload: action:
        ''"${payload}": ("${action.topic}", ${builtins.toJSON action.payload}),''
      ) actions);
  in {
    name = "button-${safeName}";
    description = "Button handler: ${safeName}";
    script = ''
      ACTIONS = {
          ${actionLines}
      }

      @on_message("${button}")
      def handle(topic, payload):
          if payload in ACTIONS:
              target, data = ACTIONS[payload]
              publish(target, data)

      while True:
          sleep(60)
    '';
  };

  # -- List of automation definitions --------------------------------------
  # Add new automations here by importing their .nix file.
  catDoorbell = import ./cat-doorbell.nix;

  buttonActions = import ./button-actions.nix;

  automations = [
    (import ./sunrise-lights.nix)
    (import ./plug-auto-off.nix)
    (catDoorbell // {
      env = catDoorbell.env // {
        HA_TOKEN_FILE = config.sops.secrets."ha/api_token".path;
      };
    })
  ] ++ (lib.mapAttrsToList mkButtonAction buttonActions);

  # -- Merge all automation services into one attrset ----------------------
  allServices = lib.foldl' (acc: def: acc // (mkAutomation def)) {} automations;
in {
  systemd.services = allServices;
}
