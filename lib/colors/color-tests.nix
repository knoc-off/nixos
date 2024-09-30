# color-lib-test.nix
{ pkgs ? import <nixpkgs> {} }:
let
  colorLib = import ./color-lib.nix { inherit (pkgs) lib; };
  math = import ./math.nix { inherit (pkgs) lib; };

  # Helper function to compare two hex colors
  hexColorClose = hex1: hex2:
    let
      rgb1 = colorLib.hexToRgb hex1;
      rgb2 = colorLib.hexToRgb hex2;
      diff = color: math.abs (rgb1.${color} - rgb2.${color});
    in
      (diff "r" < 0.01) && (diff "g" < 0.01) && (diff "b" < 0.01);

  # Test function
  testColorConversions = inputHex:
    let
      # Conversion chain
      rgb = colorLib.hexToRgb inputHex;
      srgb = colorLib.rgbToSrgb rgb;
      rgbFromSrgb = colorLib.srgbToRgb srgb;
      hsl = colorLib.rgbToHsl rgb;
      rgbFromHsl = colorLib.hslToRgb hsl;
      oklab = colorLib.rgbToOklab rgb;
      rgbFromOklab = colorLib.oklabToRgb oklab;
      okhsl = colorLib.rgbToOkhsl rgb;
      rgbFromOkhsl = colorLib.okhslToRgb okhsl;
      oklch = colorLib.rgbToOklch rgb;
      rgbFromOklch = colorLib.oklchToRgb oklch;

      # Convert back to hex
      hexFromRgb = colorLib.rgbToHex rgb;
      hexFromSrgb = colorLib.rgbToHex rgbFromSrgb;
      hexFromHsl = colorLib.rgbToHex rgbFromHsl;
      hexFromOklab = colorLib.rgbToHex rgbFromOklab;
      hexFromOkhsl = colorLib.rgbToHex rgbFromOkhsl;
      hexFromOklch = colorLib.rgbToHex rgbFromOklch;

      # Check results
      results = {
        rgb = hexColorClose inputHex hexFromRgb;
        srgb = hexColorClose inputHex hexFromSrgb;
        hsl = hexColorClose inputHex hexFromHsl;
        oklab = hexColorClose inputHex hexFromOklab;
        okhsl = hexColorClose inputHex hexFromOkhsl;
        oklch = hexColorClose inputHex hexFromOklch;
      };

      allPassed = pkgs.lib.all (x: x) (pkgs.lib.attrValues results);
    in
    {
      inputColor = inputHex;
      passed = allPassed;
      results = results;
    };

  # Run tests with multiple colors
  runTests = c: map testColorConversions (colors ++ c);

  colors = [
    "#FF0000"  # Red
    "#00FF00"  # Green
    "#0000FF"  # Blue
    "#FFFF00"  # Yellow
    "#00FFFF"  # Cyan
    "#FF00FF"  # Magenta
    "#FFFFFF"  # White
    "#000000"  # Black
    "#808080"  # Gray
    "#123456"
  ];

  # Function to generate text output from test results
  generateTextOutput = results:
    let
      header = "Color  Overall RGB sRGB HSL Oklab Okhsl Oklch\n";
      separator = "------------------------------------------------\n";

      resultToString = result:
        let
          overall = if result.passed then "Pass  " else "Fail  ";
          boolToString = b: if b then "Pass " else "Fail ";
        in
        "${result.inputColor} ${overall} ${boolToString result.results.rgb}${boolToString result.results.srgb}${boolToString result.results.hsl}${boolToString result.results.oklab}${boolToString result.results.okhsl}${boolToString result.results.oklch}\n";

      rows = pkgs.lib.concatMapStrings resultToString results;
    in
    header + separator + rows;

  # Function to write text output to a file
  writeTextFile = filename: results:
    builtins.toFile filename (generateTextOutput results);
  result = writeTextFile "tests" (runTests []);

in
pkgs.runCommand "color-test-results" {} ''
  cp ${result} $out
''
