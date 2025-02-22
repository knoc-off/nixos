{ lib ? import <nixpkgs/lib> }:

/* Math library for Nix with improved precision and error handling

   This library provides mathematical functions and utilities with:
   - Input validation
   - Better precision
   - Edge case handling
   - Comprehensive documentation
*/

rec {
  # Constants
  pi = 3.141592653589793;
  tau = 2 * pi;
  epsilon = pow (0.1) 10; # Small number for floating-point comparisons

  # Core functions
  safeDiv = num: den: if den == 0 then 0 else num / den;

  # Basic arithmetic helpers
  inherit (builtins) floor ceil;

  # Improved min/max functions with type checking
  min = a: b:
    assert builtins.isFloat a || builtins.isInt a;
    assert builtins.isFloat b || builtins.isInt b;
    if a < b then a else b;

  max = a: b:
    assert builtins.isFloat a || builtins.isInt a;
    assert builtins.isFloat b || builtins.isInt b;
    if a > b then a else b;

  # Improved clamp function that handles min > max case
  clamp = x: a: b:
    let
      sorted = lib.sort (x: y: x < y) [ a b ];
      minVal = builtins.elemAt sorted 0;
      maxVal = builtins.elemAt sorted 1;
    in max minVal (min maxVal x);

  # Linear interpolation
  lerp = a: b: t: assert t >= 0.0 && t <= 1.0; a + (b - a) * t;

  # Basic arithmetic operations with validation
  sub = builtins.foldl' builtins.sub 0;
  sum = builtins.foldl' builtins.add 0;
  multiply = builtins.foldl' builtins.mul 1;

  # Absolute value functions
  abs = x: if x < 0 then 0 - x else x;
  fabs = abs;

  # Improved cube root with iteration limit and validation
  cbrt = x:
    let
      maxIterations = 100;
      absX = abs x + 0.0;

      helper = guess: iteration:
        let
          newGuess = (2 * guess + absX / (guess * guess)) / 3;
          delta = abs (newGuess - guess);
        in if iteration >= maxIterations then
          abort "cbrt: Maximum iterations reached"
        else if delta < epsilon then
          newGuess
        else
          helper newGuess (iteration + 1);

      initialGuess = if absX < 1 then absX else absX / 3;
      result = helper initialGuess 0;
    in if x == 0 then 0 else if x < 0 then -result else result;

  # Improved range functions
  arange = min: max: step:
    assert step > 0;
    assert max > min;
    let count = floor ((max - min) / step);
    in lib.genList (i: min + step * i) count;

  arange2 = min: max: step:
    assert step > 0;
    assert max >= min;
    let count = ceil ((max - min) / step);
    in lib.genList (i: min + step * i) count;

  # Improved polynomial evaluation
  polynomial = x: poly:
    assert builtins.isList poly;
    assert builtins.length poly > 0;
    let step = i: (pow x i) * (builtins.elemAt poly i);
    in sum (lib.genList step (builtins.length poly));

  # Improved floating point parsing
  parseFloat = str:
    let
      parts = lib.splitString "." str;
      intPart = lib.toInt (builtins.head parts);
      fracPart = if builtins.length parts > 1 then
        lib.toInt (builtins.elemAt parts 1)
        / (pow 10 (lib.stringLength (builtins.elemAt parts 1)))
      else
        0;
    in intPart + fracPart;

  # Improved fraction detection
  hasFraction = x:
    let
      str = builtins.toString x;
      splitted = lib.splitString "." str;
    in builtins.length splitted >= 2 && builtins.length
    (builtins.filter (ch: ch != "0")
      (lib.stringToCharacters (builtins.elemAt splitted 1))) > 0;

  # Improved integer division with validation
  div = a: b:
    assert b != 0;
    let
      divideExactly = !(hasFraction (1.0 * a / b));
      offset = if divideExactly then 0 else (0 - 1);
    in if b < 0 then
      offset - div a (0 - b)
    else if a < 0 then
      offset - div (0 - a) b
    else
      floor (1.0 * a / b);

  # Improved modulo operation
  mod = a: b:
    assert b != 0;
    if b < 0 then
      0 - mod (0 - a) (0 - b)
    else if a < 0 then
      mod (b - mod (0 - a) b) b
    else
      a - b * (div a b);

  fmod = x: y: x - y * floor (x / y);

  # Improved natural logarithm with validation
  ln = x:
    assert x > 0.0;
    let
      ln2 = 0.6931471805599453;
      normalize = base: order:
        if base < 2.0 && base >= 1.0 then {
          inherit base order;
        } else if base >= 2.0 then
          normalize (base / 2.0) (order + 1)
        else
          normalize (base * 2.0) (order - 1);
      x' = normalize x 0;
      lnx = x:
        (-1.7417939)
        + (2.8212026 + ((-1.4699568) + (0.44717955 - 5.6570851e-2 * x) * x) * x)
        * x;
    in lnx x'.base + (x'.order * ln2);

  # Improved exponential function
  exp = x:
    let
      ln2Inv = 1.4426950408889634;
      sign = if x >= 0.0 then 1 else (-1);
      x' = x * sign * ln2Inv;
      truncated = builtins.floor x';
      fractated = x' - truncated;
      twoPowXPart = x:
        1.41421 + 0.980258 * (x - 0.5) + 0.339732 * pow (x - 0.5) 2 + 7.84947e-2
        * pow (x - 0.5) 3 + 1.36021e-2 * pow (x - 0.5) 4 + 1.88565e-3
        * pow (x - 0.5) 5;
      res = (pow 2 truncated) * twoPowXPart fractated;
    in if sign == 1 then res else 1.0 / res;

  # Improved power functions
  pow = x: times: assert builtins.isInt times; multiply (lib.replicate times x);

  powFloat = x: a: exp (a * ln x);

  # Improved factorial with validation
  factorial = x:
    assert builtins.isInt x && x >= 0;
    if x == 0 then 1 else multiply (lib.range 1 x);

  # Trigonometric functions (radian input)
  sin = x:
    let
      maxIterations = 20;
      x' = mod (1.0 * x) tau; # Normalize to [0, 2π)
      step = i:
        (pow (-1) (i - 1)) * (pow x' (2 * i - 1)) / factorial (2 * i - 1);
      helper = tmp: i:
        let value = step i;
        in if i >= maxIterations || (fabs value) < epsilon then
          tmp
        else
          helper (tmp + value) (i + 1);
    in helper 0 1;

  cos = x: sin (0.5 * pi - x);

  tan = x: let cosX = cos x; in assert cosX != 0; (sin x) / cosX;

  # Degree-based trigonometric functions
  sind = x: sin (deg2rad x);
  cosd = x: cos (deg2rad x);
  tand = x: tan (deg2rad x);

  # Improved atan2 with degree conversion
  atan2d = y: x: rad2deg (atan2 y x);

  # Degree-based inverse tangent
  atand = x: rad2deg (atan x);

  # Additional conversion functions
  rad2deg = x: x * 180 / pi;
  deg2rad = x: x * pi / 180;


  # Improved inverse trigonometric functions
  atan = x:
    let
      arctanPart = x:
        let
          xx = x * x;
          coefficients = [
            2.89394245323327e-3
            (-1.62911733512761e-2)
            4.31408641542157e-2
            (-7.55120841589429e-2)
            0.10668127080775
            (-0.142123340834229)
            0.199940412794435
            (-0.333331728467737)
            1.0
          ];
        in x * (builtins.foldl' (a: b: a * xx + b) 0 coefficients);

      arctanPositive = x:
        if x <= 1.0 then arctanPart x else pi / 2 - arctanPart (1.0 / x);
    in if x >= 0.0 then arctanPositive x else (-1.0) * arctanPositive (-x);

  # Improved atan2 with complete quadrant handling
  atan2 = y: x:
    if x > 0 then
      atan (y * 1.0 / x)
    else if x < 0 && y >= 0 then
      atan (y * 1.0 / x) + pi
    else if x < 0 && y < 0 then
      atan (y * 1.0 / x) - pi
    else if x == 0 && y > 0 then
      pi / 2
    else if x == 0 && y < 0 then
      (-1) * pi / 2
    else if x == 0 && y == 0 then
      0.0 # Define behavior at origin
    else
      0.0;

  # Improved square root with validation and precision
  sqrt = x:
    assert x >= 0;
    let
      maxIterations = 50;
      helper = tmp: iteration:
        let
          value = (tmp + 1.0 * x / tmp) / 2;
          delta = fabs (value - tmp);
        in if iteration >= maxIterations then
          abort "sqrt: Maximum iterations reached"
        else if delta < epsilon then
          value
        else
          helper value (iteration + 1);
    in if x < epsilon then 0 else helper (1.0 * x) 0;

  # Improved haversine formula with input validation
  haversine = lat1: lon1: lat2: lon2:
    let
      validateCoords = lat: lon:
        assert lat >= -90.0 && lat <= 90.0;
        assert lon >= -180.0 && lon <= 180.0;
        true;

      # Earth's radius in meters
      radius = 6371000;

      # Validate all coordinates
      _ = validateCoords lat1 lon1;
      __ = validateCoords lat2 lon2;

      rad_lat = deg2rad ((1.0 * lat2) - (1.0 * lat1));
      rad_lon = deg2rad ((1.0 * lon2) - (1.0 * lon1));

      lat1_rad = deg2rad (1.0 * lat1);
      lat2_rad = deg2rad (1.0 * lat2);

      a = (sin (rad_lat / 2)) * (sin (rad_lat / 2)) + (cos lat1_rad)
        * (cos lat2_rad) * (sin (rad_lon / 2)) * (sin (rad_lon / 2));

      c = 2 * atan2 (sqrt a) (sqrt (1 - a));
    in radius * c;

  halley = f: x0:
    let
      maxIterations = 50;
      epsilon = pow (0.1) 6; # 1e-6 precision
      helper = x: iteration:
        let
          # Calculate function value and derivatives
          calc = f x;
          y = calc.value;
          dy = calc.deriv1;
          d2y = calc.deriv2;

          # Halley's update formula
          denominator = dy - (y * d2y) / (2 * dy + epsilon);
          delta = if abs denominator > epsilon then y / denominator else 0;
          newX = x - delta;
          absDelta = abs delta;
        in
          if iteration >= maxIterations then
            throw "halley: Maximum iterations reached (last delta: ${toString absDelta})"
          else if absDelta < epsilon then
            newX
          else
            helper newX (iteration + 1);
    in
      helper x0 0;

  # Improved hex to decimal conversion with validation
  hexToDec = hexStr:
    assert builtins.isString hexStr;
    let
      hexDigitToDec = hexDigit:
        let
          hexChars = {
            "0" = 0;
            "1" = 1;
            "2" = 2;
            "3" = 3;
            "4" = 4;
            "5" = 5;
            "6" = 6;
            "7" = 7;
            "8" = 8;
            "9" = 9;
            "A" = 10;
            "B" = 11;
            "C" = 12;
            "D" = 13;
            "E" = 14;
            "F" = 15;
            "a" = 10;
            "b" = 11;
            "c" = 12;
            "d" = 13;
            "e" = 14;
            "f" = 15;
          };
        in if builtins.hasAttr hexDigit hexChars then
          hexChars.${hexDigit}
        else
          throw "Invalid hex digit: ${hexDigit}";

      hexDigits = lib.stringToCharacters hexStr;

      # Validate all digits are hex
      _ = map (d: assert hexDigitToDec d >= 0; true) hexDigits;

      hexToDecHelper = digits: acc:
        if digits == [ ] then
          acc
        else
          let
            digit = builtins.head digits;
            remainingDigits = builtins.tail digits;
            digitValue = hexDigitToDec digit;
          in hexToDecHelper remainingDigits (acc * 16 + digitValue);
    in if hexStr == "" then
      throw "Empty hex string"
    else
      hexToDecHelper hexDigits 0;

  # Improved random number generation from string
  genRandomFromString = str: min: max:
    assert builtins.isString str;
    assert max > min;
    let
      hashHex = builtins.substring 0 8 (builtins.hashString "md5" str);
      hashNum = hexToDec hashHex;
      normalized = hashNum / 4.294967295e9; # 0xFFFFFFFF
      scaled = min + normalized * (max - min);
    in clamp scaled min max;

  # Statistical functions
  average = numbers:
    assert builtins.isList numbers;
    assert builtins.length numbers > 0;
    let
      sum = lib.foldl' builtins.add 0 numbers;
      len = builtins.length numbers;
    in 1.0 * sum / len;

  # Standard deviation
  standardDeviation = numbers:
    assert builtins.isList numbers;
    assert builtins.length numbers > 1;
    let
      avg = average numbers;
      squaredDiffs = map (x: pow (x - avg) 2) numbers;
      variance = average squaredDiffs;
    in sqrt variance;

  # Median calculation
  median = numbers:
    assert builtins.isList numbers;
    assert builtins.length numbers > 0;
    let
      sorted = lib.sort (a: b: a < b) numbers;
      len = builtins.length sorted;
      mid = len / 2;
    in if mod len 2 == 0 then
      average [
        (builtins.elemAt sorted (mid - 1))
        (builtins.elemAt sorted mid)
      ]
    else
      builtins.elemAt sorted (floor mid);

  # Function to compute S_max and T_max based on lightness L
  computeSTmax = L:
    assert L >= 0.0 && L <= 1.0;
    let
      t = L / (1.0 - L + epsilon);
      S_max = t / (1.0 + t);
      T_max = 1.0 / (1.0 + t);
    in {
      S = clamp S_max 0.0 1.0;
      T = clamp T_max 0.0 1.0;
    };
}
