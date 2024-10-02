# types.nix
{ }:

let
  # Helper functions to validate value ranges
  isBetween = value: min: max: value >= min && value <= max;

  # Helper to create type definitions with per-attribute validators
  createType = { name, requiredAttrs, optionalAttrs ? {} }:

    let
      # Function to validate required attributes
      checkRequired = color:
        builtins.all (attr:
          builtins.hasAttr attr color &&
          requiredAttrs.${attr} (color.${attr})
        ) (builtins.attrNames requiredAttrs);

      # Function to validate optional attributes
      checkOptional = color:
        builtins.all (attr:
          (! builtins.hasAttr attr color) || optionalAttrs.${attr} (color.${attr})
        ) (builtins.attrNames optionalAttrs);

      # Combined validation
      isValid = color:
        builtins.isAttrs color && checkRequired color && checkOptional color;

      # Update meta.type if necessary
      updateMeta = color:
        if builtins.hasAttr "meta" color && color.meta.type == name
        then color
        else color // { meta = { type = name; }; };

      # Strict check: ensures meta.type is exactly `name`
      strictCheck = color:
        if isValid color && builtins.hasAttr "meta" color && color.meta.type == name
        then color
        else if isValid color
        then throw "Invalid ${name} color type: ${builtins.toJSON color}"
        else throw "Invalid ${name} color: ${builtins.toJSON color}";

      # Soft check: updates meta.type if not present or incorrect
      softCheck = color:
        if isValid color
        then updateMeta color
        else throw "Invalid ${name} color: ${builtins.toJSON color}";

    in {
      name = name;
      requiredAttrs = builtins.attrNames requiredAttrs;
      check = softCheck;
      strictCheck = strictCheck;
      softCheck = softCheck;
    };

  # Validation functions
  hexValidate = v:
    builtins.isString v && builtins.stringLength v == 2 && builtins.match "^[0-9A-Fa-f]{2}$" v != null;

  floatValidate = v: (builtins.isFloat v || builtins.isInt v);

  floatBetween0And1 = v:
    floatValidate v && isBetween v 0.0 1.0;

  Types = rec {
    # Hex color type
    Hex = createType {
      name = "Hex";
      requiredAttrs = {
        r = hexValidate;
        g = hexValidate;
        b = hexValidate;
      };
      optionalAttrs = {
        a = hexValidate;
      };
    };

    gammaRgb = createType {
      name = "gammaRgb"; # Non Gamma ??
      requiredAttrs = {
        r = floatBetween0And1;
        g = floatBetween0And1;
        b = floatBetween0And1;
      };
      optionalAttrs = {
        a = floatBetween0And1;
      };
    };

    # linearRGB color type
    linearRgb = createType {
      name = "linearRGB"; # GammaRGB
      requiredAttrs = {
        r = floatBetween0And1;
        g = floatBetween0And1;
        b = floatBetween0And1;
      };
      optionalAttrs = {
        a = floatBetween0And1;
      };
    };

    # HSL color type
    HSL = createType {
      name = "HSL";
      requiredAttrs = {
        h = floatBetween0And1;
        s = floatBetween0And1;
        l = floatBetween0And1;
      };
      optionalAttrs = {};
    };

    # Oklab color type
    Oklab = createType {
      name = "Oklab";
      requiredAttrs = {
        L = v: floatValidate v && isBetween v 0.0 1.0;
        a = v: floatValidate v && isBetween v (-0.5) 0.5;
        b = v: floatValidate v && isBetween v (-0.5) 0.5;
      };
      optionalAttrs = {
        alpha = floatBetween0And1;
      };
    };

    # Okhsl color type
    Okhsl = createType {
      name = "Okhsl";
      requiredAttrs = {
        h = v: isBetween v 0 360;
        s = floatBetween0And1;
        l = floatBetween0And1;
      };
      optionalAttrs = {};
    };

    Okhsv = createType {
      name = "Okhsv";
      requiredAttrs = {
        h = v: isBetween v 0 360;
        s = floatBetween0And1;
        v = floatBetween0And1;
      };
      optionalAttrs = {};
    };

    # Oklch color type
    Oklch = createType {
      name = "Oklch";
      requiredAttrs = {
        L = v: floatValidate v && isBetween v 0.0 1.0;
        C = v: floatValidate v && isBetween v 0 360;
        h = floatValidate;
      };
      optionalAttrs = {};
    };

    # XYZ color type
    XYZ = createType {
      name = "XYZ";
      requiredAttrs = {
        X = v: isBetween v 0 0.95048;
        Y = v: isBetween v 0 1.00001;
        Z = v: isBetween v 0 1.08906;
      };
      optionalAttrs = {
        a = isBetween 0 1.0;

      };
    };
  };

in
  Types
