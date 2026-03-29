# Cat doorbell: sends a phone notification via Home Assistant when the
# motion sensor detects presence. Uses smart filtering to avoid spam:
#   - Only triggers on presence transitions (false -> true)
#   - Only on actual movement (large/small), not static
#   - Cooldown between notifications (default 5 min)
#
# Requires:
#   - HA Companion app on phone (provides notify.mobile_app_<name> service)
#   - A long-lived HA access token stored in sops as "ha/api_token"
#     (HA -> Profile -> Security -> Long-lived access tokens -> Create)
{
  name = "cat-doorbell";
  description = "Notify phone on motion detection (cat doorbell)";
  pythonPackages = ps: [ps.requests];
  env = {
    SENSOR_TOPIC = "zigbee2mqtt/motion_sensor";
    HA_URL = "http://localhost:8123"; # loopback
    # Update this to match your phone's notify service name.
    # Find it in HA -> Developer Tools -> Services -> search "notify"
    NOTIFY_SERVICE = "notify.all_phones";
    COOLDOWN_SECONDS = "300";
    NOTIFICATION_TITLE = "Cat Doorbell";
  };
  # The HA_TOKEN_FILE env is set separately via sops (see rpi-3a-plus.nix)
  script = ''
    import requests as req

    sensor = env("SENSOR_TOPIC")
    ha_url = env("HA_URL", "http://localhost:8123")
    notify_service = env("NOTIFY_SERVICE", "notify.mobile_app_phone")
    cooldown = int(env("COOLDOWN_SECONDS", "300"))
    title = env("NOTIFICATION_TITLE", "Cat Doorbell")

    # Read HA token from file (sops-decrypted at runtime)
    token_file = env("HA_TOKEN_FILE", "")
    ha_token = ""
    if token_file:
        try:
            with open(token_file) as f:
                ha_token = f.read().strip()
            log(f"loaded HA token from {token_file}")
        except Exception as e:
            log(f"WARNING: could not read HA token: {e}")
    else:
        ha_token = env("HA_TOKEN", "")

    if not ha_token:
        log("ERROR: no HA token configured. Set HA_TOKEN_FILE or HA_TOKEN.")

    last_notification = None
    notified_this_session = False  # reset when presence goes false

    def send_notification(message):
        global last_notification
        now = datetime.now()
        if last_notification and (now - last_notification).total_seconds() < cooldown:
            log(f"cooldown active ({cooldown}s), skipping")
            return

        service_path = notify_service.replace(".", "/")
        try:
            resp = req.post(
                f"{ha_url}/api/services/{service_path}",
                headers={
                    "Authorization": f"Bearer {ha_token}",
                    "Content-Type": "application/json",
                },
                json={"message": message, "title": title},
                timeout=10,
            )
            if resp.ok:
                last_notification = now
                log(f"notification sent: {message}")
            else:
                log(f"notification failed: {resp.status_code} {resp.text}")
        except Exception as e:
            log(f"notification error: {e}")

    @on_message(sensor)
    def handle(topic, payload):
        global notified_this_session
        if not isinstance(payload, dict):
            return

        presence = payload.get("presence")
        motion = payload.get("motion_state", "none")

        # Reset when presence ends — ready for next session
        if not presence:
            if notified_this_session:
                log("presence ended, resetting")
            notified_this_session = False
            return

        # Notify once per presence session when real movement is detected.
        # The sensor reports presence:true with motion_state:"none" first,
        # then updates motion_state a moment later — so we wait for actual
        # movement rather than triggering on the presence transition itself.
        if not notified_this_session and motion in ("large", "small"):
            send_notification(f"Movement detected ({motion})")
            notified_this_session = True

    log(f"watching {sensor} (cooldown: {cooldown}s)")

    while True:
        sleep(60)
  '';
}
