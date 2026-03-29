# Gradually ramps a light from 0% to 100% around sunrise.
# Calculates real sunrise time daily using astral.
{
  name = "sunrise-lights";
  description = "Gradually turn on lights at sunrise";
  pythonPackages = ps: [ps.astral];
  env = {
    LIGHT_TOPIC = "zigbee2mqtt/light_3/set";
    LATITUDE = "52.52";
    LONGITUDE = "13.405";
    RAMP_MINUTES = "60"; # how long the ramp takes (0% -> 100%)
    OFFSET_MINUTES = "0"; # start this many minutes before sunrise (0 = at sunrise)
    UPDATE_INTERVAL = "30"; # seconds between brightness updates
    COLOR_TEMP_START = "454"; # mired: warm candle (~2200K)
    COLOR_TEMP_END = "250"; # mired: neutral white (~4000K)
  };
  script = ''
    from astral.sun import sun
    from astral import LocationInfo
    import zoneinfo

    lat = float(env("LATITUDE"))
    lon = float(env("LONGITUDE"))
    city = LocationInfo("Home", "", "Europe/Berlin", lat, lon)
    tz = zoneinfo.ZoneInfo("Europe/Berlin")

    topic = env("LIGHT_TOPIC")
    ramp_minutes = float(env("RAMP_MINUTES", "30"))
    offset_minutes = float(env("OFFSET_MINUTES", "0"))
    interval = float(env("UPDATE_INTERVAL", "30"))
    ct_start = int(env("COLOR_TEMP_START", "454"))
    ct_end = int(env("COLOR_TEMP_END", "250"))

    while True:
        now = datetime.now(tz)
        today_sun = sun(city.observer, date=now.date(), tzinfo=tz)
        sunrise = today_sun["sunrise"]

        ramp_start = sunrise - timedelta(minutes=offset_minutes + ramp_minutes)
        ramp_end = sunrise - timedelta(minutes=offset_minutes)

        # If we've already passed today's ramp, schedule for tomorrow
        if now > ramp_end + timedelta(minutes=5):
            tomorrow = now.date() + timedelta(days=1)
            tomorrow_sun = sun(city.observer, date=tomorrow, tzinfo=tz)
            sunrise = tomorrow_sun["sunrise"]
            ramp_start = sunrise - timedelta(minutes=offset_minutes + ramp_minutes)
            ramp_end = sunrise - timedelta(minutes=offset_minutes)

        log(f"next sunrise: {sunrise.strftime('%H:%M')}, ramp: {ramp_start.strftime('%H:%M')} -> {ramp_end.strftime('%H:%M')}")

        # Sleep until ramp starts
        wait_until(ramp_start)

        # Turn on at minimum brightness to start
        publish(topic, {"state": "ON", "brightness": 1, "color_temp": ct_start})
        ramp_duration = (ramp_end - ramp_start).total_seconds()

        # Ramp loop: continuously update brightness + color temp
        while True:
            now = datetime.now(tz)
            elapsed = (now - ramp_start).total_seconds()
            progress = min(max(elapsed / ramp_duration, 0.0), 1.0)

            brightness = max(1, int(progress * 254))
            color_temp = int(ct_start + progress * (ct_end - ct_start))

            publish(topic, {
                "brightness": brightness,
                "color_temp": color_temp,
            })

            if progress >= 1.0:
                log("ramp complete")
                break

            sleep(interval)

        # Wait a bit before recalculating for the next day
        sleep(60)
  '';
}
