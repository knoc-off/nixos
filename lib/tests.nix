{ lib ? import <nixpkgs/lib>, color-lib ? import ./color-lib { }
, math ? import ./math.nix { inherit lib; } }:

let
  inherit (color-lib)
    hexToRGB rgbToHex rgbToOKLab oklabToRGB rgbToOKHSL okhslToRGB rgbToOKHSV
    okhsvToRGB;

  testColor = color:
    let
      rgb = hexToRGB color;
      okLab = rgbToOKLab rgb;
      okHsl = rgbToOKHSL rgb;
      okHsv = rgbToOKHSV rgb;

      okLabValue = oklabToRGB okLab;
      okHslValue = okhslToRGB okHsl;
      okHsvValue = okhsvToRGB okHsv;

      roundtrip = {
        hex = rgbToHex rgb;
        lab = rgbToHex (oklabToRGB okLab);
        hsl = rgbToHex (okhslToRGB okHsl);
        hsv = rgbToHex (okhsvToRGB okHsv);
      };

      conversions = [
        {
          from = "hex";
          to = "rgb";
          test = rgb == hexToRGB (rgbToHex rgb);
        }
        {
          from = "rgb";
          to = "OKLab";
          test = lib.nearest rgb (oklabToRGB (rgbToOKLab rgb));
        }
        {
          from = "OKLab";
          to = "rgb";
          test = lib.nearest rgb (oklabToRGB (rgbToOKLab rgb));
        }
        {
          from = "rgb";
          to = "OKHSL";
          test = lib.nearest rgb (okhslToRGB (rgbToOKHSL rgb));
        }
        {
          from = "OKHSL";
          to = "rgb";
          test = lib.nearest rgb (okhslToRGB (rgbToOKHSL rgb));
        }
        {
          from = "rgb";
          to = "OKHSV";
          test = lib.nearest rgb (okhsvToRGB (rgbToOKHSV rgb));
        }
        {
          from = "OKHSV";
          to = "rgb";
          test = lib.nearest rgb (okhsvToRGB (rgbToOKHSV rgb));
        }
      ];

      lib.nearest = a: b:
        let eps = math.pow 0.1 4;
        in math.abs (a.r - b.r) < eps && math.abs (a.g - b.g) < eps && math.abs (a.b - b.b)
        < eps;

    in {
      inherit rgb okLab okHsl okHsv okLabValue okHslValue okHsvValue roundtrip;
      tests = map (c: c // { result = if c.test then "PASS" else "FAIL"; })
        conversions;
    };

  colors = {
    black = "#000000";
    red = "#ff0000";
  };

  colorTests = lib.mapAttrs (name: color: testColor color) colors;

in {
  inherit colorTests;
  summary = lib.mapAttrs (_: v: {
    passed = lib.count (t: t.result == "PASS") v.tests;
    total = lib.length v.tests;
  }) colorTests;
}
