# types.nix
{ }:

let
  isBetween = value: min: max:
     value >= min && value <= max;

  isIntBetween = value: min: max:
    builtins.isInt value && value >= min && value <= max;

  Types = rec {
    Hex = {
      name = "Hex";
      requiredAttrs = ["r" "g" "b"];
      check = color:
        let
          isValidHexPair = value:
            builtins.isString value &&
            builtins.stringLength value == 2 &&
            builtins.match "[0-9A-Fa-f]{2}" value != null;
        in
        if builtins.isAttrs color &&
           builtins.all (attr: builtins.hasAttr attr color && isValidHexPair color.${attr}) ["r" "g" "b"] &&
           (! builtins.hasAttr "a" color || isValidHexPair color.a)
        then
          if builtins.hasAttr "meta" color && color.meta.type == "Hex"
          then color
          else color // { meta = { type = "Hex"; }; }
        else
          throw "Invalid Hex color: ${builtins.toJSON color}";
    };

    RGB = {
      name = "RGB";
      requiredAttrs = ["r" "g" "b"];
      check = color:
        if builtins.isAttrs color &&
           builtins.all (attr:
             builtins.hasAttr attr color &&
             isBetween color.${attr} 0.0 1.0
           ) ["r" "g" "b"]
        then
          if builtins.hasAttr "meta" color && color.meta.type == "RGB"
          then color
          else color // { meta = { type = "RGB"; }; }
        else
          throw "Invalid RGB color: ${builtins.toJSON color}";
    };

    sRGB = {
      name = "sRGB";
      requiredAttrs = ["r" "g" "b"];
      check = color:
        if builtins.isAttrs color &&
           builtins.all (attr:
             builtins.hasAttr attr color &&
             isBetween color.${attr} 0.0 1.0
           ) ["r" "g" "b"]
        then
          if builtins.hasAttr "meta" color && color.meta.type == "sRGB"
          then color
          else color // { meta = { type = "sRGB"; }; }
        else
          throw "Invalid sRGB color: ${builtins.toJSON color}";
    };

    linearRGB = let
      validateAttrs = color: builtins.all (attr:
        builtins.hasAttr attr color && isBetween color.${attr} 0.0 1.0
      ) ["r" "g" "b"];

      errorMsg = color: "Invalid linear RGB color: ${builtins.toJSON color}";

      checkAndUpdate = check: color:
        if builtins.isAttrs color && validateAttrs color
        then check color
        else throw (errorMsg color);

    in {
      name = "linearRGB";
      requiredAttrs = ["r" "g" "b"];

      strictCheck = checkAndUpdate (color:
        if color.meta.type == "linearRGB" then color
        else throw (errorMsg color)
      );

      softCheck = checkAndUpdate (color:
        if builtins.hasAttr "meta" color && color.meta.type == "linearRGB"
        then color
        else color // { meta = { type = "linearRGB"; }; }
      );
    };

    HSL = {
      name = "HSL";
      requiredAttrs = ["h" "s" "l"];
      check = color:
        if builtins.isAttrs color &&
           builtins.all (attr:
             builtins.hasAttr attr color &&
             isBetween color.${attr} 0.0 1.0
           ) ["h" "s" "l"]
        then
          if builtins.hasAttr "meta" color && color.meta.type == "HSL"
          then color
          else color // { meta = { type = "HSL"; }; }
        else
          throw "Invalid HSL color: ${builtins.toJSON color}";
    };

    Oklab = {
      name = "Oklab";
      requiredAttrs = ["L" "a" "b"];
      check = color:
        if builtins.isAttrs color &&
           builtins.all (attr: builtins.hasAttr attr color) ["L" "a" "b"] &&
           color.L >= 0 && color.L <= 1 &&
           color.a >= -0.5 && color.a <= 0.5 &&
           color.b >= -0.5 && color.b <= 0.5
        then
          if builtins.hasAttr "meta" color && color.meta.type == "Oklab"
          then color
          else color // { meta = { type = "Oklab"; }; }
        else
          throw "Invalid Oklab color: ${builtins.toJSON color}";
    };

    Okhsl = {
      name = "Okhsl";
      requiredAttrs = ["h" "s" "l"];
      check = color:
        if builtins.isAttrs color &&
           builtins.all (attr:
             builtins.hasAttr attr color &&
             isBetween color.${attr} 0.0 1.0
           ) ["h" "s" "l"]
        then
          if builtins.hasAttr "meta" color && color.meta.type == "Okhsl"
          then color
          else color // { meta = { type = "Okhsl"; }; }
        else
          throw "Invalid Okhsl color: ${builtins.toJSON color}";
    };

    Oklch = {
      name = "Oklch";
      requiredAttrs = ["L" "C" "h"];
      check = color:
        if builtins.isAttrs color &&
           builtins.hasAttr "L" color && isBetween color.L 0.0 1.0 &&
           builtins.hasAttr "C" color && builtins.isFloat color.C &&
           builtins.hasAttr "h" color && builtins.isFloat color.h
        then
          if builtins.hasAttr "meta" color && color.meta.type == "Oklch"
          then color
          else color // { meta = { type = "Oklch"; }; }
        else
          throw "Invalid Oklch color: ${builtins.toJSON color}";
    };
    XYZ = {
      name = "XYZ";
      requiredAttrs = ["X" "Y" "Z"];
      check = color:
        if builtins.isAttrs color &&
           builtins.all (attr:
             builtins.hasAttr attr color &&
             isBetween color.${attr} 0.0 1.0
           ) ["X" "Y" "Z"]
        then
          if builtins.hasAttr "meta" color && color.meta.type == "XYZ"
          then color
          else color // { meta = { type = "XYZ"; }; }
        else
          throw "Invalid XYZ color: ${builtins.toJSON color}";
    };


    # You can add more types as needed
  };
in
  Types
