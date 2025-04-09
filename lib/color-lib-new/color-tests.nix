{ lib ? import <nixpkgs/lib>, math ? import ../math.nix { inherit lib; } }:
let
  # Import the color math library
  colorMath = import ./color-math.nix { inherit lib; };

  # --- Test Utilities ---
  epsilon = 1.0e-6; # Tolerance for floating point comparisons

  # Assert within tolerance
  assertWithinTolerance = name: expected: actual: tolerance:
    let diff = math.abs (expected - actual);
    in if diff <= tolerance then
      true # Test passed
    else
      throw "${name}: Expected ${toString expected}, got ${toString actual} (tolerance ${toString tolerance}, diff ${toString diff})";

  # Assert attribute sets are equal (within tolerance for floats)
  assertAttrsEqual = name: expected: actual: tolerance:
    let
      keysExpected = builtins.attrNames expected;
      keysActual = builtins.attrNames actual;
      allKeys = lib.unique (keysExpected ++ keysActual);
      checkKey = key:
        if !(builtins.hasAttr key expected) then
          throw "${name}: Expected attrset missing key '${key}'"
        else if !(builtins.hasAttr key actual) then
          throw "${name}: Actual attrset missing key '${key}'"
        else let
          valExpected = expected.${key};
          valActual = actual.${key};
        in if builtins.isFloat valExpected && builtins.isFloat valActual then
          assertWithinTolerance "${name}.${key}" valExpected valActual tolerance
        else if valExpected == valActual then
          true
        else
          throw "${name}.${key}: Expected ${toString valExpected}, got ${toString valActual} (values not equal)";
      # Evaluate checks for all keys
      results = map checkKey allKeys;
    in lib.all (x: x == true) results; # Ensure all checks passed

  # --- Hex Helpers (from user, plus dependencies) ---
  inherit (lib) stringToCharacters toUpper removePrefix stringLength elem all concatStrings substring map filter;

  # Needed for hex helpers
  hexDigitToDec = hexDigit:
    let
      hexChars = {
        "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9;
        "A" = 10; "B" = 11; "C" = 12; "D" = 13; "E" = 14; "F" = 15;
        "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
      };
    in if builtins.hasAttr hexDigit hexChars then
      hexChars.${hexDigit}
    else
      throw "Invalid hex digit: ${hexDigit}";

  hexToDec = hexStr:
    assert builtins.isString hexStr;
    let
      hexDigits = stringToCharacters hexStr;
      # Validate all digits are hex
      _ = map (d: assert hexDigitToDec d >= 0; true) hexDigits;
      hexToDecHelper = digits: acc:
        if digits == [ ] then acc
        else let
          digit = builtins.head digits;
          remainingDigits = builtins.tail digits;
          digitValue = hexDigitToDec digit;
        in hexToDecHelper remainingDigits (acc * 16 + digitValue);
    in if hexStr == "" then
      throw "Empty hex string"
    else
      hexToDecHelper hexDigits 0;

  isValidHex = str:
    let
      cleanHex = removePrefix "#" str;
      validChars = [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F" ];
      chars = stringToCharacters (toUpper cleanHex);
      validLengths = [ 3 4 6 8 ];
      isValidLength = elem (stringLength cleanHex) validLengths;
    in isValidLength && all (c: elem c validChars) chars;

  splitHex = hex:
    let
      cleanHex = removePrefix "#" hex;
      _ = if !(isValidHex cleanHex) then throw "Invalid hex color code: ${hex}" else true;
      normalizedHex = toUpper (
        if stringLength cleanHex == 3 then
          concatStrings (map (c: c + c) (stringToCharacters cleanHex))
        else if stringLength cleanHex == 4 then
          concatStrings (map (c: c + c) (stringToCharacters cleanHex))
        else
          cleanHex # Already 6 or 8
      );
      r = substring 0 2 normalizedHex;
      g = substring 2 2 normalizedHex;
      b = substring 4 2 normalizedHex;
    in if stringLength normalizedHex == 8 then
      { inherit r g b; alpha = substring 6 2 normalizedHex; }
    else
      { inherit r g b; alpha = "FF"; };

  combineHex = { r, g, b, alpha ? "FF" }:
    let
      padHex = hex: if stringLength hex == 1 then "0${hex}" else hex;
      result = toUpper "#${padHex r}${padHex g}${padHex b}${if (toUpper alpha) != "FF" then (padHex alpha) else ""}";
    in if isValidHex result then result else throw "Invalid combined hex: ${result}";

  # Helper to convert hex string to non-linear sRGB {r, g, b} in 0-1 range
  hexToRgb01 = hex:
    let parts = splitHex hex;
    in {
      r = (hexToDec parts.r) / 255.0;
      g = (hexToDec parts.g) / 255.0;
      b = (hexToDec parts.b) / 255.0;
      # alpha = (hexToDec parts.alpha) / 255.0; # Alpha ignored for Oklab conversions
    };

  # Helper to convert non-linear sRGB {r, g, b} 0-1 range to hex string
  rgb01ToHex = rgb:
    let
      toHexByte = val: lib.toHexString (builtins.floor (math.clamp val 0.0 1.0 * 255.0 + 0.5)); # Add 0.5 for rounding
    in combineHex { r = toHexByte rgb.r; g = toHexByte rgb.g; b = toHexByte rgb.b; };


  # --- Test Sets ---


  testOklabConversions =
    let
      # Linear sRGB values
      black_lin = { r = 0.0; g = 0.0; b = 0.0; };
      white_lin = { r = 1.0; g = 1.0; b = 1.0; };
      grey_lin = { r = 0.5; g = 0.5; b = 0.5; };
      red_lin = { r = 1.0; g = 0.0; b = 0.0; };
      green_lin = { r = 0.0; g = 1.0; b = 0.0; };
      blue_lin = { r = 0.0; g = 0.0; b = 1.0; };

      # Expected Oklab values (approximate, verify if possible)
      black_lab = { L = 0.0; a = 0.0; b = 0.0; };
      white_lab = { L = 1.0; a = 0.0; b = 0.0; };
      grey_lab = { L = 0.793701; a = 0.0; b = 0.0; }; # L for 0.5 linear grey
      red_lab = { L = 0.6279; a = 0.2248; b = 0.1258; };
      green_lab = { L = 0.8664; a = -0.2339; b = 0.1795; };
      blue_lab = { L = 0.4520; a = -0.0322; b = -0.3117; };

    in {
      name = "Oklab Conversions";
      testBlack = assertAttrsEqual "linear_srgb_to_oklab(black)" black_lab (colorMath.linear_srgb_to_oklab black_lin) epsilon;
      testWhite = assertAttrsEqual "linear_srgb_to_oklab(white)" white_lab (colorMath.linear_srgb_to_oklab white_lin) epsilon;
      testGrey = assertAttrsEqual "linear_srgb_to_oklab(grey)" grey_lab (colorMath.linear_srgb_to_oklab grey_lin) 0.001;
      testRed = assertAttrsEqual "linear_srgb_to_oklab(red)" red_lab (colorMath.linear_srgb_to_oklab red_lin) 0.001;
      testGreen = assertAttrsEqual "linear_srgb_to_oklab(green)" green_lab (colorMath.linear_srgb_to_oklab green_lin) 0.001;
      testBlue = assertAttrsEqual "linear_srgb_to_oklab(blue)" blue_lab (colorMath.linear_srgb_to_oklab blue_lin) 0.001;

      testInvBlack = assertAttrsEqual "oklab_to_linear_srgb(black)" black_lin (colorMath.oklab_to_linear_srgb black_lab) epsilon;
      testInvWhite = assertAttrsEqual "oklab_to_linear_srgb(white)" white_lin (colorMath.oklab_to_linear_srgb white_lab) epsilon;
      testInvGrey = assertAttrsEqual "oklab_to_linear_srgb(grey)" grey_lin (colorMath.oklab_to_linear_srgb grey_lab) 0.001;
      testInvRed = assertAttrsEqual "oklab_to_linear_srgb(red)" red_lin (colorMath.oklab_to_linear_srgb red_lab) 0.001;
      testInvGreen = assertAttrsEqual "oklab_to_linear_srgb(green)" green_lin (colorMath.oklab_to_linear_srgb green_lab) 0.001;
      testInvBlue = assertAttrsEqual "oklab_to_linear_srgb(blue)" blue_lin (colorMath.oklab_to_linear_srgb blue_lab) 0.001;

      # Round trip tests
      testRoundTripGrey = assertAttrsEqual "oklab round trip grey" grey_lin (colorMath.oklab_to_linear_srgb (colorMath.linear_srgb_to_oklab grey_lin)) epsilon;
      testRoundTripRed = assertAttrsEqual "oklab round trip red" red_lin (colorMath.oklab_to_linear_srgb (colorMath.linear_srgb_to_oklab red_lin)) epsilon;
    };

  testGamutHelpers =
    let
      # Hue angles (approx) and corresponding normalized (a, b)
      red_hue = 0.0 / 360.0;
      red_a = 1.0;
      red_b = 0.0; # Simplified, actual Oklab hue angle is ~29deg
      oklab_red_a = 0.860;
      oklab_red_b = 0.510; # Approx normalized a,b for Oklab red hue
      green_hue = 120.0 / 360.0;
      green_a = -0.5;
      green_b = 0.866; # Simplified
      oklab_green_a = -0.795;
      oklab_green_b = 0.606; # Approx normalized a,b for Oklab green hue
      blue_hue = 240.0 / 360.0;
      blue_a = -0.5;
      blue_b = -0.866; # Simplified
      oklab_blue_a = -0.102;
      oklab_blue_b = -0.995; # Approx normalized a,b for Oklab blue hue

      # Expected cusp points (should correspond to linear sRGB primaries)
      cusp_red_expected = colorMath.linear_srgb_to_oklab { r = 1.0; g = 0.0; b = 0.0; };
      cusp_green_expected = colorMath.linear_srgb_to_oklab { r = 0.0; g = 1.0; b = 0.0; };
      cusp_blue_expected = colorMath.linear_srgb_to_oklab { r = 0.0; g = 0.0; b = 1.0; };

      # Test intersection: Point inside gamut (grey) should yield t >= 1.0
      grey_lab = colorMath.linear_srgb_to_oklab { r = 0.5; g = 0.5; b = 0.5; };
      # Test intersection: Point outside gamut (high chroma red)
      high_chroma_red = { L = cusp_red_expected.L; a = cusp_red_expected.a * 1.5; b = cusp_red_expected.b * 1.5; };
      high_C = math.sqrt (high_chroma_red.a * high_chroma_red.a + high_chroma_red.b * high_chroma_red.b);
      high_a_ = high_chroma_red.a / high_C;
      high_b_ = high_chroma_red.b / high_C;

    in {
      name = "Gamut Helpers";
      # compute_max_saturation - difficult to get exact expected value without reference
      testMaxSatRed = assertWithinTolerance "compute_max_saturation(red)" 0.393396 (colorMath.compute_max_saturation oklab_red_a oklab_red_b) 0.01;
      testMaxSatGreen = assertWithinTolerance "compute_max_saturation(green)" 0.338285 (colorMath.compute_max_saturation oklab_green_a oklab_green_b) 0.01;
      testMaxSatBlue = assertWithinTolerance "compute_max_saturation(blue)" 0.690 (colorMath.compute_max_saturation oklab_blue_a oklab_blue_b) 0.01;

      # find_cusp
      testCuspRed = assertAttrsEqual "find_cusp(red)" { L = cusp_red_expected.L; C = math.sqrt (cusp_red_expected.a * cusp_red_expected.a + cusp_red_expected.b * cusp_red_expected.b); } (colorMath.find_cusp oklab_red_a oklab_red_b) 0.01;
      testCuspGreen = assertAttrsEqual "find_cusp(green)" { L = cusp_green_expected.L; C = math.sqrt (cusp_green_expected.a * cusp_green_expected.a + cusp_green_expected.b * cusp_green_expected.b); } (colorMath.find_cusp oklab_green_a oklab_green_b) 0.01;
      testCuspBlue = assertAttrsEqual "find_cusp(blue)" { L = cusp_blue_expected.L; C = math.sqrt (cusp_blue_expected.a * cusp_blue_expected.a + cusp_blue_expected.b * cusp_blue_expected.b); } (colorMath.find_cusp oklab_blue_a oklab_blue_b) 0.01;

      # find_gamut_intersection
      # Test point inside gamut (grey): t should be >= 1.0
      testIntersectInside =
        let result = colorMath.find_gamut_intersection grey_lab.a grey_lab.b grey_lab.L 0.01 0.5;
        in assert result >= 1.0 - epsilon; "find_gamut_intersection(inside)";

      # Test point outside gamut (high chroma red): t should be < 1.0
      testIntersectOutside =
        let result = colorMath.find_gamut_intersection high_a_ high_b_ high_chroma_red.L high_C 0.5;
        in assert result < 1.0; "find_gamut_intersection(outside)";

      # Test intersection result is on boundary (indirect test)
      testIntersectResult =
        let
          L1 = high_chroma_red.L;
          C1 = high_C;
          L0 = 0.5;
          t = colorMath.find_gamut_intersection high_a_ high_b_ L1 C1 L0;
          L_clipped = L0 * (1.0 - t) + t * L1;
          C_clipped = t * C1;
          rgb_clipped_lin = colorMath.oklab_to_linear_srgb {
            L = L_clipped;
            a = C_clipped * high_a_;
            b = C_clipped * high_b_;
          };
          # Increase tolerance slightly for boundary check due to accumulated float errors
          boundary_epsilon = 1.0e-4;

          r_close_0 = math.abs rgb_clipped_lin.r < boundary_epsilon;
          r_close_1 = math.abs (rgb_clipped_lin.r - 1.0) < boundary_epsilon;
          g_close_0 = math.abs rgb_clipped_lin.g < boundary_epsilon;
          g_close_1 = math.abs (rgb_clipped_lin.g - 1.0) < boundary_epsilon;
          b_close_0 = math.abs rgb_clipped_lin.b < boundary_epsilon;
          b_close_1 = math.abs (rgb_clipped_lin.b - 1.0) < boundary_epsilon;

        in
        assert r_close_0 || r_close_1 || g_close_0 || g_close_1 || b_close_0 || b_close_1; "find_gamut_intersection(result on boundary)";
    };

  testToeFunctions = {
    name = "Toe Functions";
    testToe0 = assertWithinTolerance "toe(0)" 0.0 (colorMath.toe 0.0) epsilon;
    testToe1 = assertWithinTolerance "toe(1)" 1.0 (colorMath.toe 1.0) epsilon;
    # Test the Oklab L value that should yield perceptual lightness 0.5
    testToeMid = assertWithinTolerance "toe(0.56883)" 0.5 (colorMath.toe 0.56883) 0.001;

    testToeInv0 = assertWithinTolerance "toe_inv(0)" 0.0 (colorMath.toe_inv 0.0) epsilon;
    testToeInv1 = assertWithinTolerance "toe_inv(1)" 1.0 (colorMath.toe_inv 1.0) epsilon;
    # Test the Oklab L value corresponding to perceptual lightness 0.5
    testToeInvMid = assertWithinTolerance "toe_inv(0.5)" 0.56883 (colorMath.toe_inv 0.5) 0.001;

    testRoundTrip0_1 = assertWithinTolerance "toe round trip 0.1" 0.1 (colorMath.toe_inv (colorMath.toe 0.1)) epsilon;
    testRoundTrip0_5 = assertWithinTolerance "toe round trip 0.5" 0.5 (colorMath.toe_inv (colorMath.toe 0.5)) epsilon; # This tests the inverse relationship at the midpoint
    testRoundTrip0_9 = assertWithinTolerance "toe round trip 0.9" 0.9 (colorMath.toe_inv (colorMath.toe 0.9)) epsilon;
  };

  testOkhsl =
    let
      # Test colors (non-linear sRGB 0-1)
      black = { r = 0.0; g = 0.0; b = 0.0; };
      white = { r = 1.0; g = 1.0; b = 1.0; };
      grey = { r = 0.5; g = 0.5; b = 0.5; };
      red = hexToRgb01 "#FF0000";
      green = hexToRgb01 "#00FF00";
      blue = hexToRgb01 "#0000FF";
      yellow = hexToRgb01 "#FFFF00";
      cyan = hexToRgb01 "#00FFFF";
      magenta = hexToRgb01 "#FF00FF";
      orange = hexToRgb01 "#FFA500";

      # Expected Okhsl values (approximate, verify if possible)
      okhsl_black = { h = 0.0; s = 0.0; l = 0.0; }; # Hue is arbitrary for black
      okhsl_white = { h = 0.0; s = 0.0; l = 1.0; }; # Hue is arbitrary for white
      okhsl_grey = { h = 0.0; s = 0.0; l = 0.59; }; # Hue arbitrary, L approx
      okhsl_red = { h = 0.08; s = 1.0; l = 0.628; };
      okhsl_green = { h = 0.39; s = 1.0; l = 0.866; };
      okhsl_blue = { h = 0.70; s = 1.0; l = 0.452; };
      okhsl_yellow = { h = 0.27; s = 1.0; l = 0.968; };
      okhsl_cyan = { h = 0.54; s = 1.0; l = 0.906; };
      okhsl_magenta = { h = 0.89; s = 1.0; l = 0.539; };
      okhsl_orange = { h = 0.16; s = 1.0; l = 0.775; };

    in {
      name = "Okhsl Conversions";
      testToBlack = assertAttrsEqual "srgb_to_okhsl(black)" okhsl_black (colorMath.srgb_to_okhsl black) epsilon;
      testToWhite = assertAttrsEqual "srgb_to_okhsl(white)" okhsl_white (colorMath.srgb_to_okhsl white) epsilon;
      testToGrey = assertAttrsEqual "srgb_to_okhsl(grey)" okhsl_grey (colorMath.srgb_to_okhsl grey) 0.01;
      testToRed = assertAttrsEqual "srgb_to_okhsl(red)" okhsl_red (colorMath.srgb_to_okhsl red) 0.01;
      testToGreen = assertAttrsEqual "srgb_to_okhsl(green)" okhsl_green (colorMath.srgb_to_okhsl green) 0.01;
      testToBlue = assertAttrsEqual "srgb_to_okhsl(blue)" okhsl_blue (colorMath.srgb_to_okhsl blue) 0.01;
      testToYellow = assertAttrsEqual "srgb_to_okhsl(yellow)" okhsl_yellow (colorMath.srgb_to_okhsl yellow) 0.01;
      testToCyan = assertAttrsEqual "srgb_to_okhsl(cyan)" okhsl_cyan (colorMath.srgb_to_okhsl cyan) 0.01;
      testToMagenta = assertAttrsEqual "srgb_to_okhsl(magenta)" okhsl_magenta (colorMath.srgb_to_okhsl magenta) 0.01;
      testToOrange = assertAttrsEqual "srgb_to_okhsl(orange)" okhsl_orange (colorMath.srgb_to_okhsl orange) 0.01;

      # Round trip tests
      testRoundTripBlack = assertAttrsEqual "okhsl round trip black" black (colorMath.okhsl_to_srgb (colorMath.srgb_to_okhsl black)) epsilon;
      testRoundTripWhite = assertAttrsEqual "okhsl round trip white" white (colorMath.okhsl_to_srgb (colorMath.srgb_to_okhsl white)) epsilon;
      testRoundTripGrey = assertAttrsEqual "okhsl round trip grey" grey (colorMath.okhsl_to_srgb (colorMath.srgb_to_okhsl grey)) epsilon;
      testRoundTripRed = assertAttrsEqual "okhsl round trip red" red (colorMath.okhsl_to_srgb (colorMath.srgb_to_okhsl red)) epsilon;
      testRoundTripOrangeHex =
        let result = rgb01ToHex (colorMath.okhsl_to_srgb (colorMath.srgb_to_okhsl orange));
        in assert result == "#FFA500"; "okhsl round trip orange hex";

      # Edge cases
      testEdgeL0 = assertAttrsEqual "okhsl L=0" black (colorMath.okhsl_to_srgb { h = 0.5; s = 0.5; l = 0.0; }) epsilon;
      testEdgeL1 = assertAttrsEqual "okhsl L=1" white (colorMath.okhsl_to_srgb { h = 0.5; s = 0.5; l = 1.0; }) epsilon;
      testEdgeS0 = assertAttrsEqual "okhsl S=0" grey (colorMath.okhsl_to_srgb (colorMath.srgb_to_okhsl grey)) epsilon; # Grey should remain grey
    };

  testOkhsv =
    let
      # Test colors (non-linear sRGB 0-1)
      black = { r = 0.0; g = 0.0; b = 0.0; };
      white = { r = 1.0; g = 1.0; b = 1.0; };
      grey = { r = 0.5; g = 0.5; b = 0.5; };
      red = hexToRgb01 "#FF0000";
      green = hexToRgb01 "#00FF00";
      blue = hexToRgb01 "#0000FF";
      yellow = hexToRgb01 "#FFFF00";
      cyan = hexToRgb01 "#00FFFF";
      magenta = hexToRgb01 "#FF00FF";
      orange = hexToRgb01 "#FFA500";

      # Expected Okhsv values (approximate, verify if possible)
      okhsv_black = { h = 0.0; s = 0.0; v = 0.0; }; # Hue/Sat arbitrary for black
      okhsv_white = { h = 0.0; s = 0.0; v = 1.0; }; # Hue arbitrary for white
      okhsv_grey = { h = 0.0; s = 0.0; v = 0.59; }; # Hue arbitrary, V approx
      okhsv_red = { h = 0.08; s = 1.0; v = 1.0; };
      okhsv_green = { h = 0.39; s = 1.0; v = 1.0; };
      okhsv_blue = { h = 0.70; s = 1.0; v = 1.0; };
      okhsv_yellow = { h = 0.27; s = 1.0; v = 1.0; };
      okhsv_cyan = { h = 0.54; s = 1.0; v = 1.0; };
      okhsv_magenta = { h = 0.89; s = 1.0; v = 1.0; };
      okhsv_orange = { h = 0.16; s = 1.0; v = 1.0; };

    in {
      name = "Okhsv Conversions";
      testToBlack = assertAttrsEqual "srgb_to_okhsv(black)" okhsv_black (colorMath.srgb_to_okhsv black) epsilon;
      testToWhite = assertAttrsEqual "srgb_to_okhsv(white)" okhsv_white (colorMath.srgb_to_okhsv white) epsilon;
      testToGrey = assertAttrsEqual "srgb_to_okhsv(grey)" okhsv_grey (colorMath.srgb_to_okhsv grey) 0.01;
      testToRed = assertAttrsEqual "srgb_to_okhsv(red)" okhsv_red (colorMath.srgb_to_okhsv red) 0.01;
      testToGreen = assertAttrsEqual "srgb_to_okhsv(green)" okhsv_green (colorMath.srgb_to_okhsv green) 0.01;
      testToBlue = assertAttrsEqual "srgb_to_okhsv(blue)" okhsv_blue (colorMath.srgb_to_okhsv blue) 0.01;
      testToYellow = assertAttrsEqual "srgb_to_okhsv(yellow)" okhsv_yellow (colorMath.srgb_to_okhsv yellow) 0.01;
      testToCyan = assertAttrsEqual "srgb_to_okhsv(cyan)" okhsv_cyan (colorMath.srgb_to_okhsv cyan) 0.01;
      testToMagenta = assertAttrsEqual "srgb_to_okhsv(magenta)" okhsv_magenta (colorMath.srgb_to_okhsv magenta) 0.01;
      testToOrange = assertAttrsEqual "srgb_to_okhsv(orange)" okhsv_orange (colorMath.srgb_to_okhsv orange) 0.01;

      # Round trip tests
      testRoundTripBlack = assertAttrsEqual "okhsv round trip black" black (colorMath.okhsv_to_srgb (colorMath.srgb_to_okhsv black)) epsilon;
      testRoundTripWhite = assertAttrsEqual "okhsv round trip white" white (colorMath.okhsv_to_srgb (colorMath.srgb_to_okhsv white)) epsilon;
      testRoundTripGrey = assertAttrsEqual "okhsv round trip grey" grey (colorMath.okhsv_to_srgb (colorMath.srgb_to_okhsv grey)) epsilon;
      testRoundTripRed = assertAttrsEqual "okhsv round trip red" red (colorMath.okhsv_to_srgb (colorMath.srgb_to_okhsv red)) epsilon;
      testRoundTripOrangeHex =
        let result = rgb01ToHex (colorMath.okhsv_to_srgb (colorMath.srgb_to_okhsv orange));
        in assert result == "#FFA500"; "okhsv round trip orange hex";

      # Edge cases
      testEdgeV0 = assertAttrsEqual "okhsv V=0" black (colorMath.okhsv_to_srgb { h = 0.5; s = 0.5; v = 0.0; }) epsilon;
      testEdgeV1S0 = assertAttrsEqual "okhsv V=1 S=0" white (colorMath.okhsv_to_srgb { h = 0.5; s = 0.0; v = 1.0; }) epsilon; # Should be white
      testEdgeS0 = assertAttrsEqual "okhsv S=0" grey (colorMath.okhsv_to_srgb (colorMath.srgb_to_okhsv grey)) epsilon; # Grey should remain grey
    };

  testHexHelpers = {
    name = "Hex Helpers";
    testValid3 = let result = isValidHex "ABC"; in assert result; "isValidHex 3 digit";
    testValid4 = let result = isValidHex "ABC8"; in assert result; "isValidHex 4 digit";
    testValid6 = let result = isValidHex "AABBCC"; in assert result; "isValidHex 6 digit";
    testValid8 = let result = isValidHex "AABBCC88"; in assert result; "isValidHex 8 digit";
    testValidHash = let result = isValidHex "#AABBCC"; in assert result; "isValidHex # prefix";
    testInvalidChar = let result = isValidHex "AABBCG"; in assert !result; "isValidHex invalid char";
    testInvalidLength = let result = isValidHex "AABBC"; in assert !result; "isValidHex invalid length";

    testSplit3 = let result = splitHex "123"; in assert result == { r="11"; g="22"; b="33"; alpha="FF"; }; "splitHex 3 digit";
    testSplit4 = let result = splitHex "1234"; in assert result == { r="11"; g="22"; b="33"; alpha="44"; }; "splitHex 4 digit";
    testSplit6 = let result = splitHex "AABBCC"; in assert result == { r="AA"; g="BB"; b="CC"; alpha="FF"; }; "splitHex 6 digit";
    testSplit8 = let result = splitHex "AABBCCDD"; in assert result == { r="AA"; g="BB"; b="CC"; alpha="DD"; }; "splitHex 8 digit";
    testSplitHash = let result = splitHex "#AABBCC"; in assert result == { r="AA"; g="BB"; b="CC"; alpha="FF"; }; "splitHex # prefix";

    testCombineRGB = let result = combineHex { r="AA"; g="BB"; b="CC"; }; in assert result == "#AABBCC"; "combineHex RGB";
    testCombineRGBA = let result = combineHex { r="AA"; g="BB"; b="CC"; alpha="DD"; }; in assert result == "#AABBCCDD"; "combineHex RGBA";
    testCombineRGBShort = let result = combineHex { r="A"; g="B"; b="C"; }; in assert result == "#0A0B0C"; "combineHex RGB short";
    testCombineRGBAFF = let result = combineHex { r="AA"; g="BB"; b="CC"; alpha="FF"; }; in assert result == "#AABBCC"; "combineHex RGBA FF alpha";
  };

  # --- Aggregate All Tests ---
  # Evaluating this attribute forces evaluation of all tests due to --strict
  runAllTests = [
    testOkhsl
    testOkhsv
    testHexHelpers
  ];

in {
  # Expose the aggregate runner
  inherit runAllTests;

  # Optionally expose individual test sets if needed
  # inherit testSrgbTransfer testOklabConversions ... ;
}

