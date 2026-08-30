{ ... }: {
  home =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.easyeffects;
      jsonFormat = pkgs.formats.json { };

      # Preset definitions
      #
      # Each preset is a named attrset containing a full easyeffects JSON preset.
      # The top-level key (input/output) determines which pipeline it targets.
      # Presets are placed as separate files in ~/.local/share/easyeffects/{input,output}/
      # and referenced by name from autoload profiles.

      # Input presets

      inputPresets = {
        mic-denoise = {
          input = {
            blocklist = [ ];
            plugins_order = [ "rnnoise#0" ];
            "rnnoise#0" = {
              bypass = false;
              "enable-vad" = true;
              "input-gain" = 0.0;
              "model-path" = "";
              "output-gain" = 0.0;
              release = 20.0;
              "vad-thres" = 50.0;
              wet = 0.0;
            };
          };
        };
      };

      # Output presets

      outputPresets = {
        # Framework 13 speaker correction -- measured by Kieran Levin (Framework engineer).
        # Source: https://github.com/ceiphr/ee-framework-presets (kieran_levin.json)
        framework-speakers = {
          output = {
            blocklist = [ ];
            plugins_order = [ "equalizer#0" ];
            "equalizer#0" =
              let
                mkBand =
                  {
                    freq,
                    gain,
                    q,
                    type ? "Bell",
                    mute ? false,
                  }:
                  {
                    frequency = freq;
                    inherit gain mute q;
                    mode = "RLC (BT)";
                    slope = "x1";
                    solo = false;
                    inherit type;
                  };
                bands = {
                  band0 = mkBand {
                    freq = 80.0;
                    gain = 0.0;
                    q = 4.36;
                    type = "Hi-pass";
                  };
                  band1 = mkBand {
                    freq = 600.0;
                    gain = -8.0;
                    q = 4.0;
                    type = "Notch";
                  };
                  band2 = mkBand {
                    freq = 1250.0;
                    gain = -3.49;
                    q = 4.17;
                  };
                  band3 = mkBand {
                    freq = 2016.0;
                    gain = 4.85;
                    q = 0.67;
                  };
                  band4 = mkBand {
                    freq = 5272.0;
                    gain = 3.83;
                    q = 2.64;
                    type = "Notch";
                  };
                  band5 = mkBand {
                    freq = 6000.0;
                    gain = 4.85;
                    q = 4.36;
                    type = "Hi-shelf";
                    mute = true;
                  };
                };
              in
              {
                balance = 0.0;
                bypass = false;
                "input-gain" = 0.0;
                left = bands;
                right = bands;
                mode = "IIR";
                "num-bands" = 6;
                "output-gain" = 0.0;
                "pitch-left" = 0.0;
                "pitch-right" = 0.0;
                "split-channels" = false;
              };
          };
        };
      };

      # Passthrough preset (empty plugin chain)
      passthrough = direction: {
        ${direction} = {
          blocklist = [ ];
          plugins_order = [ ];
        };
      };

      # Collect all preset names referenced by autoload profiles, so we know which
      # preset files to generate.

      autoloadCfg = cfg.autoload;

      referencedOutputPresets = lib.unique (lib.mapAttrsToList (_: v: v.preset) autoloadCfg.output);
      referencedInputPresets = lib.unique (lib.mapAttrsToList (_: v: v.preset) autoloadCfg.input);

      # Resolve a preset name to its JSON data
      resolvePreset =
        direction: name:
        if name == "passthrough" then
          passthrough direction
        else if direction == "output" then
          outputPresets.${name} or (throw "easyeffects: unknown output preset '${name}'")
        else
          inputPresets.${name} or (throw "easyeffects: unknown input preset '${name}'");

      # Generate xdg.dataFile entries

      # Preset files: ~/.local/share/easyeffects/{input,output}/<name>.json
      outputPresetFiles = lib.listToAttrs (
        map (
          name:
          lib.nameValuePair "easyeffects/output/${name}.json" {
            source = jsonFormat.generate "output-${name}.json" (resolvePreset "output" name);
          }
        ) referencedOutputPresets
      );

      inputPresetFiles = lib.listToAttrs (
        map (
          name:
          lib.nameValuePair "easyeffects/input/${name}.json" {
            source = jsonFormat.generate "input-${name}.json" (resolvePreset "input" name);
          }
        ) referencedInputPresets
      );

      # Autoload profiles: ~/.local/share/easyeffects/autoload/{input,output}/<node:route>.json
      mkAutoloadFile =
        direction: key: value:
        let
          # key is "node.name:route_description"
          parts = lib.splitString ":" key;
          device = lib.head parts;
          route = lib.concatStringsSep ":" (lib.tail parts);
          # Slashes in device/route names get replaced with underscores in filenames
          safeName = lib.replaceStrings [ "/" ] [ "_" ] key;
        in
        lib.nameValuePair "easyeffects/autoload/${direction}/${safeName}.json" {
          source = jsonFormat.generate "autoload-${direction}-${safeName}.json" {
            inherit device;
            "device-description" = value.description;
            "device-profile" = route;
            "preset-name" = value.preset;
          };
        };

      outputAutoloadFiles = lib.mapAttrs' (mkAutoloadFile "output") autoloadCfg.output;
      inputAutoloadFiles = lib.mapAttrs' (mkAutoloadFile "input") autoloadCfg.input;

      hasAutoload = autoloadCfg.output != { } || autoloadCfg.input != { };

      # Autoload submodule type

      autoloadEntryType = lib.types.submodule {
        options = {
          preset = lib.mkOption {
            type = lib.types.str;
            description = "Name of the preset to load for this device.";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Human-readable device description (informational only).";
          };
        };
      };
    in
    {
      options.services.easyeffects = {
        autoload = {
          output = lib.mkOption {
            type = lib.types.attrsOf autoloadEntryType;
            default = { };
            description = ''
              Map PipeWire output devices to presets. Keys are "node.name:route_description".
              Available presets: framework-speakers, passthrough.
            '';
            example = lib.literalExpression ''
              {
                "alsa_output.pci-0000_c1_00.6.analog-stereo:Speakers" = {
                  preset = "framework-speakers";
                  description = "Built-in speakers";
                };
              }
            '';
          };

          input = lib.mkOption {
            type = lib.types.attrsOf autoloadEntryType;
            default = { };
            description = ''
              Map PipeWire input devices to presets. Keys are "node.name:route_description".
              Available presets: mic-denoise, passthrough.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          # Place preset files and autoload profiles
          (lib.mkIf hasAutoload {
            xdg.dataFile = outputPresetFiles // inputPresetFiles // outputAutoloadFiles // inputAutoloadFiles;

            # Autoload profiles handle everything -- easyeffects watches PipeWire for
            # device/route changes and loads the matching preset automatically, including
            # on initial startup when it first sees the active devices.
            # No ExecStartPost needed (and --load-preset is broken in service mode anyway).
          })
        ]
      );
    };
}
