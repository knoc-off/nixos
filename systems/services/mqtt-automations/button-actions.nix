# Button -> action mappings.
# Each key is an MQTT topic. Each value maps a button payload to a publish action.
# The framework generates the Python + systemd service automatically.
{
  "zigbee2mqtt/button_1/action" = {
    single = { topic = "zigbee2mqtt/light_1/set"; payload = { state = "TOGGLE"; }; };
    double = { topic = "zigbee2mqtt/light_1/set"; payload = { brightness = 254; }; };
    hold   = { topic = "zigbee2mqtt/light_1/set"; payload = { state = "OFF"; }; };
  };
}
