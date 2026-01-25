{
  config,
  pkgs,
  ...
}: let
  slzb06Ip = "192.168.178.32";
in {
  imports = [
    ./home-automations/dnd.nix
  ];

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;

        # Allow local anonymous clients (Z2M + HA)
        settings = {
          allow_anonymous = true;
        };

        acl = [
          "topic readwrite #"
        ];
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://localhost:1883";
      };

      frontend = {
        enabled = true;
        port = 7768;
        host = "0.0.0.0";
      };

      serial = {
        port = "tcp://${slzb06Ip}:6638";
        adapter = "zstack";
      };
    };
  };

  services.home-assistant = {
    enable = true;

    # Only add things you really need here
    extraComponents = [
      "default_config"
      "met"
      "mqtt" # optional, default_config already includes it
    ];

    config = {
      input_select = {
        plug_auto_off = {
          name = "Plug auto-off timer";
          options = [
            "30 minutes"
            "1 hour"
            "2 hours"
            "8 hours"
          ];
          initial = "1 hour";
        };
      };

      automation = [
        {
          id = "plug_auto_off_with_selectable_timer";
          alias = "Plug auto off (selectable timer)";
          mode = "restart";

          trigger = [
            {
              platform = "state";
              entity_id = "switch.bedroom_plug";
              to = "on";
            }
          ];

          action = [
            {
              choose = [
                {
                  # 30 minutes
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_select.plug_auto_off";
                      state = "30 minutes";
                    }
                  ];
                  sequence = [
                    {delay = {minutes = 30;};}
                    {
                      condition = "state";
                      entity_id = "switch.bedroom_plug";
                      state = "on";
                    }
                    {
                      service = "switch.turn_off";
                      target = {entity_id = "switch.bedroom_plug";};
                    }
                  ];
                }
                {
                  # 1 hour
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_select.plug_auto_off";
                      state = "1 hour";
                    }
                  ];
                  sequence = [
                    {delay = {hours = 1;};}
                    {
                      condition = "state";
                      entity_id = "switch.bedroom_plug";
                      state = "on";
                    }
                    {
                      service = "switch.turn_off";
                      target = {entity_id = "switch.bedroom_plug";};
                    }
                  ];
                }
                {
                  # 2 hours
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_select.plug_auto_off";
                      state = "2 hours";
                    }
                  ];
                  sequence = [
                    {delay = {hours = 2;};}
                    {
                      condition = "state";
                      entity_id = "switch.bedroom_plug";
                      state = "on";
                    }
                    {
                      service = "switch.turn_off";
                      target = {entity_id = "switch.bedroom_plug";};
                    }
                  ];
                }
                {
                  # 8 hours
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_select.plug_auto_off";
                      state = "8 hours";
                    }
                  ];
                  sequence = [
                    {delay = {hours = 2;};}
                    {
                      condition = "state";
                      entity_id = "switch.bedroom_plug";
                      state = "on";
                    }
                    {
                      service = "switch.turn_off";
                      target = {entity_id = "switch.bedroom_plug";};
                    }
                  ];
                }
              ];

              # if fall back to just turn off
              default = [
                {delay = {seconds = 30;};}
                {
                  service = "switch.turn_off";
                  target = {entity_id = "switch.bedroom_plug";};
                }
              ];
            }
          ];
        }
        {
          id = "bedroom_sunrise_0700";
          alias = "Bedroom sunrise 07:00 (stepped ramp 2h)";
          mode = "restart";

          trigger = [
            {
              platform = "time";
              at = "07:00:00";
            }
          ];

          action = [
            {
              service = "light.turn_on";
              target = {entity_id = "light.bedroom_light";};
              data = {
                brightness = 1;
                color_temp = 400;
              };
            }

            {
              repeat = {
                count = 60;
                sequence = [
                  {delay = "00:01:00";}
                  {
                    service = "light.turn_on";
                    target = {entity_id = "light.bedroom_light";};
                    data = {
                      brightness_step = 1;
                      transition = 1;
                      color_temp = 400;
                    };
                  }
                ];
              };
            }

            {
              repeat = {
                count = 60;
                sequence = [
                  {delay = "00:01:00";}
                  {
                    service = "light.turn_on";
                    target = {entity_id = "light.bedroom_light";};
                    data = {
                      brightness_step = 4;
                      transition = 1;
                      color_temp = 250;
                    };
                  }
                ];
              };
            }
          ];
        }

        {
          id = "button_a_bedroom_light_toggle_and_bedtime";
          alias = "Button A: toggle + bedtime fade";
          mode = "restart";

          trigger = [
            {
              platform = "mqtt";
              topic = "zigbee2mqtt/Button A/action";
              payload = "single";
              id = "single";
            }
            {
              platform = "mqtt";
              topic = "zigbee2mqtt/Button A/action";
              payload = "hold";
              id = "hold";
            }
          ];

          action = [
            {
              choose = [
                # SINGLE press -> toggle
                {
                  conditions = [
                    {
                      condition = "trigger";
                      id = "single";
                    }
                  ];
                  sequence = [
                    {
                      service = "light.toggle";
                      target = {entity_id = "light.bedroom_light";};
                    }
                  ];
                }

                {
                  conditions = [
                    {
                      condition = "trigger";
                      id = "hold";
                    }
                  ];
                  sequence = [
                    {
                      service = "light.turn_on";
                      target = {entity_id = "light.bedroom_light";};
                      data = {brightness_pct = 10;};
                    }

                    # small pause so the "set to 10%" takes effect before starting transition
                    {delay = {seconds = 1;};}

                    {
                      service = "light.turn_off";
                      target = {entity_id = "light.bedroom_light";};
                      data = {
                        transition = 1800; # 30 minutes
                      };
                    }
                  ];
                }
              ];
            }
          ];
        }
      ];

      default_config = {};

      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
      };

      homeassistant = {
        name = "Home";
        unit_system = "metric";
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123 # Home Assistant
    7768 # Zigbee2MQTT frontend
  ];
}
