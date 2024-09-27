# formats/rgb.nix
{ math, utils }:
{
  # Linear RGB to sRGB
  linearRgbToSrgb = rgb: {
    r = utils.srgbTransferFunction rgb.r;
    g = utils.srgbTransferFunction rgb.g;
    b = utils.srgbTransferFunction rgb.b;
  };

  # sRGB to Linear RGB
  srgbToLinearRgb = rgb: {
    r = utils.srgbTransferFunctionInv rgb.r;
    g = utils.srgbTransferFunctionInv rgb.g;
    b = utils.srgbTransferFunctionInv rgb.b;
  };
}
