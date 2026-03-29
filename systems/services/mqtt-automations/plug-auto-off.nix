# Auto-sets the plug's built-in countdown timer whenever it turns on.
# The countdown runs on the plug firmware — works even if Z2M/Pi go down.
{
  name = "plug-auto-off";
  description = "Auto-set 1hr countdown when plug turns on";
  env = {
    PLUG_TOPIC = "zigbee2mqtt/plug_1";
    COUNTDOWN_SECONDS = "3600"; # one hour.
  };
  script = ''
    plug = env("PLUG_TOPIC")
    countdown = int(env("COUNTDOWN_SECONDS", "3600"))
    last_state = None

    @on_message(plug)
    def handle(topic, payload):
        global last_state
        if isinstance(payload, dict):
            state = payload.get("state")
            if state == "ON" and last_state != "ON":
                log(f"plug turned on, setting {countdown}s countdown")
                publish(f"{plug}/set", {"countdown": countdown})
            last_state = state

    while True:
        sleep(60)
  '';
}
