# formats/oklab.nix
{ math, lib, utils, types, linearRgb }:

rec {

  # CIE XYZ to Oklab conversion
  ToOklab = { X, Y, Z, alpha ? 1, meta ? {} }@xyz: let
    l = 0.8189330101 * xyz.X + 0.3618667424 * xyz.Y - 0.1288597137 * xyz.Z;
    m = 0.0329845436 * xyz.X + 0.9293118715 * xyz.Y + 0.0361456387 * xyz.Z;
    s = 0.0482003018 * xyz.X + 0.2643662691 * xyz.Y + 0.6338517070 * xyz.Z;

    l_ = math.cbrt l;
    m_ = math.cbrt m;
    s_ = math.cbrt s;

    L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
    a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
    b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
  in types.Oklab.check {
    inherit L a b;
    alpha = xyz.alpha;
  };

  # CIE XYZ to Linear RGB conversion
  ToLinearRgb = { X, Y, Z, alpha ? 1, meta ? {} }@xyz: types.linearRgb.check {
    r = math.clamp ( 3.2404542 * xyz.X - 1.5371385 * xyz.Y - 0.4985314 * xyz.Z  ) 0 1 ;
    g = math.clamp ( -0.9692660 * xyz.X + 1.8760108 * xyz.Y + 0.0415560 * xyz.Z ) 0 1 ;
    b = math.clamp ( 0.0556434 * xyz.X - 0.2040259 * xyz.Y + 1.0572252 * xyz.Z  ) 0 1 ;
    a = xyz.alpha;
  };
}
