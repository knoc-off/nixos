{ lib ? import <nixpkgs/lib> }:
rec {
  # taken from:
  # https://github.com/xddxdd/nix-math/blob/0750f9a2d52b266a8b2461e1dc31a541bc22655e/default.nix
  inherit (builtins) floor ceil;



  clamp = x: min: max:
    if x < min then min
    else if x > max then max
    else x;
  #clamp = x: min: max: builtins.floor (lib.min max (lib.max min x) + 0.5);

  pi = 3.14159265358979323846264338327950288;
  epsilon = pow (0.1) 10;

  sub = builtins.foldl' builtins.sub 0;
  sum = builtins.foldl' builtins.add 0;
  multiply = builtins.foldl' builtins.mul 1;

  # Absolute value of `x`
  abs = x:
    if x < 0
    then 0 - x
    else x;

  # Absolute value of `x`
  fabs = abs;

  # Accurate cube root implementation
  cbrt = x: let
    absX = abs x + 0.0;
    helper = guess: let
      newGuess = (2 * guess + absX / (guess * guess)) / 3;
    in
      if abs (newGuess - guess) < epsilon
      then newGuess
      else helper newGuess;
    initialGuess = if absX < 1 then absX else absX / 3;
    result = helper initialGuess;
  in
    if x == 0 then 0 else if x < 0 then -result else result;

  # Create a list of numbers from `min` (inclusive) to `max` (exclusive), adding `step` each time.
  arange = min: max: step: let
    count = floor ((max - min) / step);
  in
    lib.genList (i: min + step * i) count;

  # Create a list of numbers from `min` (inclusive) to `max` (inclusive), adding `step` each time.
  arange2 = min: max: step: arange min (max + step) step;

  # Calculate x^0*poly[0] + x^1*poly[1] + ... + x^n*poly[n]
  polynomial = x: poly: let
    step = i: (pow x i) * (builtins.elemAt poly i);
  in
    sum (lib.genList step (builtins.length poly));

  parseFloat = builtins.fromJSON;

  hasFraction = x: let
    splitted = lib.splitString "." (builtins.toString x);
  in
    builtins.length splitted >= 2 && builtins.length (builtins.filter (ch: ch != "0") (lib.stringToCharacters (builtins.elemAt splitted 1))) > 0;

  # Divide `a` by `b` with no remainder.
  div = a: b: let
    divideExactly = !(hasFraction (1.0 * a / b));
    offset =
      if divideExactly
      then 0
      else (0 - 1);
  in
    if b < 0
    then offset - div a (0 - b)
    else if a < 0
    then offset - div (0 - a) b
    else floor (1.0 * a / b);

  # Modulos of dividing `a` by `b`.
  mod = a: b:
    if b < 0
    then 0 - mod (0 - a) (0 - b)
    else if a < 0
    then mod (b - mod (0 - a) b) b
    else a - b * (div a b);


  ln = x: let
    ln2 = 0.6931471805599453094172321214581765680755001343602552541206800094;
    normalize = base: order:
      if base < 2.0 && base >= 1.0 then { inherit base order; } else
      if base >= 2.0 then normalize (base / 2.0) (order + 1) else
      normalize (base * 2.0) (order - 1);
    x' = normalize x 0;
    lnx = x: (-1.7417939) + (2.8212026 + ((-1.4699568) + (0.44717955 - 0.056570851 * x) * x) * x) * x;
  in
    if x <= 0.0 then abort "x must be > 0.0" else
    lnx x'.base + (x'.order * ln2);

  # Returns `a` to the power of `b`. **Only supports integer for `b`!**
  exp = x: let
    ln2Inv = 1.4426950408889634073599246810018921374266459541529859341354494069;
    sign = if x >= 0.0 then 1 else (-1);
    x' = x * sign * ln2Inv;
    truncated = builtins.floor x';
    fractated = x' - truncated;
    twoPowXPart = x:
      1.41421
      + 0.980258 * (x - 0.5)
      + 0.339732 * pow (x - 0.5) 2
      + 0.0784947 * pow (x - 0.5) 3
      + 0.0136021 * pow (x - 0.5) 4
      + 0.00188565 * pow (x - 0.5) 5;
    res = (pow 2 truncated) * twoPowXPart fractated;
  in
    if sign == 1 then res else 1.0 / res;

  pow = x: times: multiply (lib.replicate times x);
  powFloat = x: a: exp (a * ln x);

  # Returns factorial of `x`. `x` is an integer, `x >= 0`.
  factorial = x: multiply (lib.range 1 x);

  # Trigonometric function. Takes radian as input.
  # Taylor series: for x >= 0, sin(x) = x - x^3/3! + x^5/5! - ...
  sin = x: let
    x' = mod (1.0 * x) (2 * pi);
    step = i: (pow (0 - 1) (i - 1)) * multiply (lib.genList (j: x' / (j + 1)) (i * 2 - 1));
    helper = tmp: i: let
      value = step i;
    in
      if (fabs value) < epsilon
      then tmp
      else helper (tmp + value) (i + 1);
  in
    if x < 0
    then -sin (0 - x)
    else helper 0 1;

  # Trigonometric function. Takes radian as input.
  cos = x: sin (0.5 * pi - x);

  # Trigonometric function. Takes radian as input.
  tan = x: (sin x) / (cos x);

  tau = 2 * pi;

  atan = x: let
    arctanPart = x: let
      xx = x * x;
      a = [ 0.00289394245323327 (-0.0162911733512761) 0.0431408641542157
        (-0.0755120841589429) 0.10668127080775 (-0.142123340834229)
        0.199940412794435 (-0.333331728467737) 1.0 ];
    in
      x * (builtins.foldl' (a: b: a * xx + b) 0 a);
    arctanPositive = x:
      if x <= 1.0 then arctanPart x else pi / 2 - arctanPart (1.0 / x);
  in
    if x >= 0.0 then arctanPositive x else (-1.0) * arctanPositive (-x);

  atan2 = y: x:
    if x > 0 then atan (y * 1.0 / x) else
    if x < 0 && y >= 0 then atan (y * 1.0 / x) + pi else
    if x < 0 && y < 0 then atan (y * 1.0 / x) - pi else
    if x == 0 && y > 0 then pi / 2 else
    if x == 0 && y < 0 then (-1) * pi / 2 else
    0.0;

  # Degrees to radian.
  deg2rad = x: x * pi / 180;

  # Square root of `x`. `x >= 0`.
  sqrt = x: let
    helper = tmp: let
      value = (tmp + 1.0 * x / tmp) / 2;
    in
      if (fabs (value - tmp)) < epsilon
      then value
      else helper value;
  in
    if x < epsilon
    then 0
    else helper (1.0 * x);

  # Returns distance of two points on Earth for the given latitude/longitude.
  # https://stackoverflow.com/questions/27928/calculate-distance-between-two-latitude-longitude-points-haversine-formula
  haversine = lat1: lon1: lat2: lon2: let
    radius = 6371000;
    rad_lat = deg2rad ((1.0 * lat2) - (1.0 * lat1));
    rad_lon = deg2rad ((1.0 * lon2) - (1.0 * lon1));
    a = (sin (rad_lat / 2)) * (sin (rad_lat / 2)) + (cos (deg2rad (1.0 * lat1))) * (cos (deg2rad (1.0 * lat2))) * (sin (rad_lon / 2)) * (sin (rad_lon / 2));
    c = 2 * atan ((sqrt a) / (sqrt (1 - a)));
  in
    radius * c;
}
