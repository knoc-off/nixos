# conversions.nix
{ core, oklab, okhsl, okhsv }:
with core; rec {
  hexToRGB = hex.toRGB;
  rgbToHex = hex.fromRGB;
  rgbToOKLab = oklab.linearSRGBToOklab;
  oklabToRGB = oklab.oklabToLinearSRGB;
  rgbToOKHSL = okhsl.fromRGB;
  okhslToRGB = okhsl.toRGB;
  rgbToOKHSV = okhsv.fromRGB;
  okhsvToRGB = okhsv.toRGB;
  hexToOKHSL = hexStr:
    okhsl.fromRGB (hex.toRGB hexStr) // {
      alpha = (hex.toRGB hexStr).alpha;
    };
  okhslToHex = hsl: hex.fromRGB (okhsl.toRGB hsl);
  hexToOKHSV = hexStr:
    okhsv.fromRGB (hex.toRGB hexStr) // {
      alpha = (hex.toRGB hexStr).alpha;
    };
  okhsvToHex = hsv: hex.fromRGB (okhsv.toRGB hsv);
  hexToOKLab = hexStr: oklab.linearSRGBToOklab (hex.toRGB hexStr);
}
