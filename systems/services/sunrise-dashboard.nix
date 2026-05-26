# Secondary Lovelace dashboard for sunrise/color-temp visualization.
# Uses apexcharts-card data_generator to draw predicted curves from
# the current slider values — redraws instantly when you adjust settings.
{pkgs, ...}: let
  dashboardYaml = pkgs.writeText "sunrise-dashboard.yaml" (builtins.toJSON {
    views = [
      {
        title = "Sunrise";
        icon = "mdi:weather-sunset-up";
        cards = [
          {
            type = "entities";
            title = "Controls";
            entities = [
              "input_number.sunrise_delay_minutes"
              "input_number.sunrise_max_brightness"
              "input_number.sunrise_ramp_speed"
              "input_boolean.lights_follow_hue"
            ];
          }

          {
            type = "custom:apexcharts-card";
            header = {show = true; title = "Next sunrise brightness";};
            graph_span = "12h";
            yaxis = [{id = "bri"; min = 0; max = 100;}];
            series = [
              {
                entity = "sun.sun";
                name = "Brightness (%)";
                type = "line";
                curve = "smooth";
                stroke_width = 3;
                color = "#FFB347";
                yaxis_id = "bri";
                data_generator = ''
                  const gamma = parseFloat(hass.states['input_number.sunrise_ramp_speed'].state);
                  const maxBri = parseFloat(hass.states['input_number.sunrise_max_brightness'].state);
                  const delayMin = parseFloat(hass.states['input_number.sunrise_delay_minutes'].state);
                  const attrs = hass.states['sun.sun'].attributes;
                  const sunrise = new Date(attrs.next_rising);
                  const noon = new Date(attrs.next_noon);
                  const rampStart = new Date(sunrise.getTime() + delayMin * 60000);
                  const pts = [];
                  const chartStart = new Date(sunrise.getTime() - 3600000);
                  pts.push([chartStart.getTime(), 0]);
                  pts.push([rampStart.getTime(), 0]);
                  const total = noon.getTime() - rampStart.getTime();
                  if (total > 0) {
                    for (let i = 1; i <= 50; i++) {
                      const t = i / 50;
                      const bri = Math.pow(t, gamma) * maxBri;
                      pts.push([rampStart.getTime() + t * total, Math.round(bri * 10) / 10]);
                    }
                  }
                  pts.push([noon.getTime(), maxBri]);
                  const chartEnd = new Date(noon.getTime() + 3600000);
                  pts.push([chartEnd.getTime(), maxBri]);
                  return pts;
                '';
              }
            ];
          }

          {
            type = "custom:apexcharts-card";
            header = {show = true; title = "Daylight color temperature";};
            graph_span = "18h";
            yaxis = [{id = "ct"; min = 200; max = 500; apex_config.reversed = true;}];
            series = [
              {
                entity = "sun.sun";
                name = "Color temp (mireds)";
                type = "line";
                curve = "smooth";
                stroke_width = 3;
                color = "#FF8A65";
                yaxis_id = "ct";
                data_generator = ''
                  const ctWarm = 454, ctCool = 250;
                  const attrs = hass.states['sun.sun'].attributes;
                  const sunrise = new Date(attrs.next_rising);
                  const noon = new Date(attrs.next_noon);
                  const dusk = new Date(attrs.next_dusk);
                  const sunset = new Date(noon.getTime() + (noon.getTime() - sunrise.getTime()));
                  const pts = [];
                  const chartStart = new Date(sunrise.getTime() - 3600000);
                  pts.push([chartStart.getTime(), ctWarm]);
                  pts.push([sunrise.getTime(), ctWarm]);
                  const total = sunset.getTime() - sunrise.getTime();
                  if (total > 0) {
                    for (let i = 1; i < 50; i++) {
                      const t = i / 50;
                      const factor = Math.sin(Math.PI * t);
                      const ct = ctWarm - factor * (ctWarm - ctCool);
                      pts.push([sunrise.getTime() + t * total, Math.round(ct)]);
                    }
                  }
                  pts.push([sunset.getTime(), ctWarm]);
                  const chartEnd = new Date(sunset.getTime() + 3600000);
                  pts.push([chartEnd.getTime(), ctWarm]);
                  return pts;
                '';
              }
            ];
          }
        ];
      }
    ];
  });
in {
  services.home-assistant.config.lovelace.dashboards.sunrise-lights = {
    mode = "yaml";
    title = "Sunrise";
    icon = "mdi:weather-sunset-up";
    show_in_sidebar = true;
    filename = "sunrise.yaml";
  };

  systemd.tmpfiles.rules = [
    "L+ /var/lib/hass/sunrise.yaml - - - - ${dashboardYaml}"
  ];
}
