{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.easyeffects;
  presets = cfg.presets;
  jsonFormat = pkgs.formats.json {};

  # ===========================================================================
  # Preset definitions
  #
  # Each preset is a named attrset containing a full easyeffects JSON preset.
  # The top-level key (input/output) determines which pipeline it targets.
  # Presets are placed as separate files in ~/.local/share/easyeffects/{input,output}/
  # and referenced by name from autoload profiles.
  # ===========================================================================

  # --- Input presets ---------------------------------------------------------

  inputPresets = {
    mic-denoise = {
      input = {
        blocklist = [];
        plugins_order = ["rnnoise#0"];
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

    # NPR broadcast-quality voice chain (includes noise removal).
    # Source: https://gist.github.com/jtrv/47542c8be6345951802eebcf9dc7da31
    # Chain: rnnoise -> deepfilternet -> gate -> EQ -> compressor -> deesser -> limiter
    npr-voice = {
      input = {
        blocklist = [];
        plugins_order = [
          "rnnoise#0"
          "deepfilternet#0"
          "gate#0"
          "equalizer#0"
          "compressor#0"
          "deesser#0"
          "limiter#0"
        ];

        "rnnoise#0" = {
          bypass = false;
          "enable-vad" = false;
          "input-gain" = 0.0;
          "model-name" = "\"\"";
          "output-gain" = 0.0;
          release = 20.0;
          "use-standard-model" = true;
          "vad-thres" = 30.0;
          wet = 0.0;
        };

        "deepfilternet#0" = {
          "attenuation-limit" = 100.0;
          bypass = false;
          "input-gain" = 0.0;
          "max-df-processing-threshold" = 20.0;
          "max-erb-processing-threshold" = 30.0;
          "min-processing-buffer" = 0;
          "min-processing-threshold" = 5.0;
          "output-gain" = 0.0;
          "post-filter-beta" = 0.019999999552965164;
        };

        "gate#0" = {
          attack = 5.0;
          bypass = false;
          "curve-threshold" = -50.0;
          "curve-zone" = -2.0;
          dry = -80.01;
          "hpf-frequency" = 10.0;
          "hpf-mode" = "Off";
          hysteresis = true;
          "hysteresis-threshold" = -3.0;
          "hysteresis-zone" = -1.0;
          "input-gain" = 0.0;
          "lpf-frequency" = 20000.0;
          "lpf-mode" = "Off";
          makeup = 1.0;
          "output-gain" = 0.0;
          reduction = -12.0;
          release = 250.0;
          sidechain = {
            lookahead = 0.0;
            mode = "RMS";
            preamp = 0.0;
            reactivity = 10.0;
            source = "Middle";
            "stereo-split-source" = "Left/Right";
            type = "Internal";
          };
          "stereo-split" = false;
          wet = -1.0;
        };

        "equalizer#0" = let
          bands = {
            band0 = {frequency = 80.0; gain = 0.0; mode = "RLC (BT)"; mute = false; q = 0.7; slope = "x2"; solo = false; type = "Hi-pass"; width = 4.0;};
            band1 = {frequency = 220.0; gain = -2.0; mode = "RLC (MT)"; mute = false; q = 0.7; slope = "x1"; solo = false; type = "Bell"; width = 4.0;};
            band2 = {frequency = 350.0; gain = -2.0; mode = "BWC (MT)"; mute = false; q = 1.2; slope = "x2"; solo = false; type = "Bell"; width = 4.0;};
            band3 = {frequency = 3500.0; gain = 2.0; mode = "BWC (BT)"; mute = false; q = 0.9; slope = "x2"; solo = false; type = "Bell"; width = 4.0;};
            band4 = {frequency = 10000.0; gain = 2.0; mode = "LRX (MT)"; mute = false; q = 0.7; slope = "x1"; solo = false; type = "Hi-shelf"; width = 4.0;};
          };
        in {
          balance = 0.1; bypass = false; "input-gain" = 0.0;
          left = bands; right = bands;
          mode = "IIR"; "num-bands" = 5; "output-gain" = 0.0;
          "pitch-left" = 0.0; "pitch-right" = 0.0; "split-channels" = false;
        };

        "compressor#0" = {
          attack = 15.0; "boost-amount" = 0.0; "boost-threshold" = -72.0;
          bypass = false; dry = -80.01; "hpf-frequency" = 10.0; "hpf-mode" = "Off";
          "input-gain" = 0.0; knee = -6.0; "lpf-frequency" = 20000.0; "lpf-mode" = "Off";
          makeup = 3.0; mode = "Downward"; "output-gain" = 0.0; ratio = 3.0;
          release = 200.0; "release-threshold" = -40.0;
          sidechain = {
            lookahead = 0.0; mode = "RMS"; preamp = 0.0; reactivity = 10.0;
            source = "Middle"; "stereo-split-source" = "Left/Right"; type = "Feed-forward";
          };
          "stereo-split" = false; threshold = -18.0; wet = 0.0;
        };

        "deesser#0" = {
          bypass = false; detection = "RMS"; "f1-freq" = 4000.0; "f1-level" = -6.0;
          "f2-freq" = 8000.0; "f2-level" = -6.0; "f2-q" = 1.5; "input-gain" = 0.0;
          laxity = 15; makeup = 0.0; mode = "Split"; "output-gain" = 0.0;
          ratio = 3.0; "sc-listen" = false; threshold = -22.0;
        };

        "limiter#0" = {
          alr = false; "alr-attack" = 5.0; "alr-knee" = 0.0; "alr-release" = 50.0;
          attack = 2.0; bypass = false; dithering = "16bit"; "gain-boost" = false;
          "input-gain" = 0.0; lookahead = 2.0; mode = "Herm Wide"; "output-gain" = 0.0;
          oversampling = "None"; release = 5.0; "sidechain-preamp" = 0.0;
          "sidechain-type" = "Internal"; "stereo-link" = 100.0; threshold = -1.5;
        };
      };
    };
  };

  # --- Output presets --------------------------------------------------------

  outputPresets = {
    # Framework 13 speaker correction — measured by Kieran Levin (Framework engineer).
    # Source: https://github.com/ceiphr/ee-framework-presets (kieran_levin.json)
    framework-speakers = {
      output = {
        blocklist = [];
        plugins_order = ["equalizer#0"];
        "equalizer#0" = let
          mkBand = {freq, gain, q, type ? "Bell", mute ? false}: {
            frequency = freq; inherit gain mute q;
            mode = "RLC (BT)"; slope = "x1"; solo = false; inherit type;
          };
          bands = {
            band0 = mkBand {freq = 80.0; gain = 0.0; q = 4.36; type = "Hi-pass";};
            band1 = mkBand {freq = 600.0; gain = -8.0; q = 4.0; type = "Notch";};
            band2 = mkBand {freq = 1250.0; gain = -3.49; q = 4.17;};
            band3 = mkBand {freq = 2016.0; gain = 4.85; q = 0.67;};
            band4 = mkBand {freq = 5272.0; gain = 3.83; q = 2.64; type = "Notch";};
            band5 = mkBand {freq = 6000.0; gain = 4.85; q = 4.36; type = "Hi-shelf"; mute = true;};
          };
        in {
          balance = 0.0; bypass = false; "input-gain" = 0.0;
          left = bands; right = bands;
          mode = "IIR"; "num-bands" = 6; "output-gain" = 0.0;
          "pitch-left" = 0.0; "pitch-right" = 0.0; "split-channels" = false;
        };
      };
    };

    # Loudness equalizer — ISO 226 equal-loudness contour approximation.
    # Source: Digitalone1/EasyEffects-Presets
    loudness-equalizer = {
      output = {
        blocklist = [];
        plugins_order = [
          "gate#0" "compressor#0" "multiband_compressor#0" "equalizer#0" "limiter#0"
        ];

        "gate#0" = {
          attack = 2000.0; bypass = false; "curve-threshold" = -40.0; "curve-zone" = -40.0;
          dry = -80.01; "hpf-frequency" = 10.0; "hpf-mode" = "Off"; hysteresis = false;
          "hysteresis-threshold" = -12.0; "hysteresis-zone" = -6.0; "input-gain" = 0.0;
          "lpf-frequency" = 20000.0; "lpf-mode" = "Off"; makeup = 0.0; "output-gain" = 0.0;
          reduction = -30.0; release = 2000.0;
          sidechain = {
            lookahead = 0.0; mode = "Peak"; preamp = 0.0; reactivity = 10.0;
            source = "Middle"; "stereo-split-source" = "Left/Right"; type = "Internal";
          };
          "stereo-split" = false; wet = 0.0;
        };

        "compressor#0" = {
          attack = 130.0; "boost-amount" = 6.0; "boost-threshold" = -60.0;
          bypass = false; dry = -80.01; "hpf-frequency" = 10.0; "hpf-mode" = "Off";
          "input-gain" = 0.0; knee = -24.0; "lpf-frequency" = 20000.0; "lpf-mode" = "Off";
          makeup = 0.0; mode = "Upward"; "output-gain" = 0.0; ratio = 5.0;
          release = 600.0; "release-threshold" = -80.01;
          sidechain = {
            lookahead = 0.0; mode = "RMS"; preamp = 0.0; reactivity = 10.0;
            source = "Middle"; "stereo-split-source" = "Left/Right"; type = "Feed-forward";
          };
          "stereo-split" = false; threshold = -10.0; wet = 0.0;
        };

        "multiband_compressor#0" = let
          mkBand = {attackTime, releaseTime, enable ? true, splitFreq ? null, hcFreq ? 20000.0, lcFreq ? 10.0}:
            {
              "attack-threshold" = -30.0; "attack-time" = attackTime; "boost-amount" = 6.0;
              "boost-threshold" = -72.0; "compression-mode" = "Downward"; "compressor-enable" = true;
              "knee" = -24.0; "makeup" = 0.0; "mute" = false; "ratio" = 1.7;
              "release-threshold" = -80.01; "release-time" = releaseTime;
              "sidechain-custom-highcut-filter" = false; "sidechain-custom-lowcut-filter" = false;
              "sidechain-highcut-frequency" = hcFreq; "sidechain-lookahead" = 0.0;
              "sidechain-lowcut-frequency" = lcFreq; "sidechain-mode" = "RMS";
              "sidechain-preamp" = 0.0; "sidechain-reactivity" = 10.0;
              "sidechain-source" = "Middle"; "sidechain-type" = "Internal";
              "solo" = false; "stereo-split-source" = "Left/Right";
            }
            // lib.optionalAttrs (splitFreq != null) {"split-frequency" = splitFreq; "enable-band" = enable;};
        in {
          band0 = mkBand {attackTime = 50.0; releaseTime = 600.0; hcFreq = 250.0;};
          band1 = mkBand {attackTime = 30.0; releaseTime = 450.0; splitFreq = 250.0; hcFreq = 1250.0; lcFreq = 250.0;};
          band2 = mkBand {attackTime = 10.0; releaseTime = 250.0; splitFreq = 1250.0; hcFreq = 5000.0; lcFreq = 1250.0;};
          band3 = mkBand {attackTime = 5.0; releaseTime = 100.0; splitFreq = 5000.0; hcFreq = 20000.0; lcFreq = 5000.0;};
          band4 = mkBand {attackTime = 20.0; releaseTime = 100.0; enable = false; splitFreq = 4000.0; hcFreq = 8000.0; lcFreq = 4000.0;};
          band5 = mkBand {attackTime = 20.0; releaseTime = 100.0; enable = false; splitFreq = 8000.0; hcFreq = 12000.0; lcFreq = 8000.0;};
          band6 = mkBand {attackTime = 20.0; releaseTime = 100.0; enable = false; splitFreq = 12000.0; hcFreq = 16000.0; lcFreq = 12000.0;};
          band7 = mkBand {attackTime = 20.0; releaseTime = 100.0; enable = false; splitFreq = 16000.0; hcFreq = 20000.0; lcFreq = 16000.0;};
          bypass = false; "compressor-mode" = "Modern"; dry = -80.01;
          "envelope-boost" = "None"; "input-gain" = 0.0; "output-gain" = 0.0;
          "stereo-split" = false; wet = 0.0;
        };

        "equalizer#0" = let
          mkBand = freq: gain: {
            frequency = freq; inherit gain; mode = "RLC (BT)"; mute = false;
            q = 1.6; slope = "x1"; solo = false; type = "Bell"; width = 4.0;
          };
          bands = {
            band0 = mkBand 32.0 3.5; band1 = mkBand 64.0 2.0; band2 = mkBand 128.0 1.0;
            band3 = mkBand 256.0 0.0; band4 = mkBand 512.0 (-0.5); band5 = mkBand 1024.0 (-1.5);
            band6 = mkBand 2048.0 (-0.25); band7 = mkBand 4096.0 1.25;
            band8 = mkBand 8192.0 2.75; band9 = mkBand 16384.0 3.0;
          };
        in {
          balance = 0.0; bypass = false; "input-gain" = 0.0;
          left = bands; right = bands;
          mode = "IIR"; "num-bands" = 10; "output-gain" = 0.0;
          "pitch-left" = 0.0; "pitch-right" = 0.0; "split-channels" = false;
        };

        "limiter#0" = {
          alr = false; "alr-attack" = 5.0; "alr-knee" = 0.0; "alr-knee-smooth" = -5.0;
          "alr-release" = 50.0; attack = 5.0; bypass = false; dithering = "None";
          "gain-boost" = false; "input-gain" = 0.0; lookahead = 5.0; mode = "Herm Thin";
          "output-gain" = 0.0; oversampling = "True Peak/16 bit"; release = 10.0;
          "sidechain-preamp" = 0.0; "sidechain-type" = "Internal"; "stereo-link" = 100.0;
          threshold = -1.0;
        };
      };
    };
  };

  # --- Passthrough preset (empty plugin chain) -------------------------------
  passthrough = direction: {
    ${direction} = {
      blocklist = [];
      plugins_order = [];
    };
  };

  # ===========================================================================
  # Collect all preset names referenced by autoload profiles, so we know which
  # preset files to generate.
  # ===========================================================================

  autoloadCfg = cfg.autoload;

  referencedOutputPresets = lib.unique (lib.mapAttrsToList (_: v: v.preset) autoloadCfg.output);
  referencedInputPresets = lib.unique (lib.mapAttrsToList (_: v: v.preset) autoloadCfg.input);

  # Resolve a preset name to its JSON data
  resolvePreset = direction: name:
    if name == "passthrough"
    then passthrough direction
    else if direction == "output"
    then outputPresets.${name} or (throw "easyeffects: unknown output preset '${name}'")
    else inputPresets.${name} or (throw "easyeffects: unknown input preset '${name}'");

  # ===========================================================================
  # Generate xdg.dataFile entries
  # ===========================================================================

  # Preset files: ~/.local/share/easyeffects/{input,output}/<name>.json
  outputPresetFiles = lib.listToAttrs (map (name:
    lib.nameValuePair "easyeffects/output/${name}.json" {
      source = jsonFormat.generate "output-${name}.json" (resolvePreset "output" name);
    }
  ) referencedOutputPresets);

  inputPresetFiles = lib.listToAttrs (map (name:
    lib.nameValuePair "easyeffects/input/${name}.json" {
      source = jsonFormat.generate "input-${name}.json" (resolvePreset "input" name);
    }
  ) referencedInputPresets);

  # Autoload profiles: ~/.local/share/easyeffects/autoload/{input,output}/<node:route>.json
  mkAutoloadFile = direction: key: value: let
    # key is "node.name:route_description"
    parts = lib.splitString ":" key;
    device = lib.head parts;
    route = lib.concatStringsSep ":" (lib.tail parts);
    # Slashes in device/route names get replaced with underscores in filenames
    safeName = lib.replaceStrings ["/"] ["_"] key;
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

  hasAutoload = autoloadCfg.output != {} || autoloadCfg.input != {};

  # ===========================================================================
  # Autoload submodule type
  # ===========================================================================

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

in {
  options.services.easyeffects = {
    presets = {
      # Input (microphone)
      mic-denoise = lib.mkEnableOption "RNNoise deep-learning noise suppression on microphone input";
      npr-voice = lib.mkEnableOption "NPR broadcast-quality voice chain (includes noise removal, EQ, compression, de-essing)";

      # Output (speakers)
      loudness-equalizer = lib.mkEnableOption "ISO 226 loudness equalizer on speaker output";
      framework-13 = lib.mkEnableOption "Framework 13 speaker correction (Kieran Levin's measured EQ)";
    };

    autoload = {
      output = lib.mkOption {
        type = lib.types.attrsOf autoloadEntryType;
        default = {};
        description = ''
          Map PipeWire output devices to presets. Keys are "node.name:route_description".
          Available presets: framework-speakers, loudness-equalizer, passthrough.
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
        default = {};
        description = ''
          Map PipeWire input devices to presets. Keys are "node.name:route_description".
          Available presets: mic-denoise, npr-voice, passthrough.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Place preset files and autoload profiles
    (lib.mkIf hasAutoload {
      xdg.dataFile = outputPresetFiles // inputPresetFiles // outputAutoloadFiles // inputAutoloadFiles;

      # Autoload profiles handle everything — easyeffects watches PipeWire for
      # device/route changes and loads the matching preset automatically, including
      # on initial startup when it first sees the active devices.
      # No ExecStartPost needed (and --load-preset is broken in service mode anyway).
    })
  ]);
}
