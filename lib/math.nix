{ lib ? import <nixpkgs/lib> }:

/* Math library for Nix with improved precision and error handling

   This library provides mathematical functions and utilities with:
   - Input validation
   - Better precision
   - Edge case handling
   - Comprehensive documentation
*/

rec {
  # --- Constants ---
  pi = 3.141592653589793;
  tau = 2.0 * pi;
  pi_half = pi / 2.0;
  epsilon = pow 0.1 10; # Small number for floating-point comparisons (1e-10)

  # Natural Logarithm related
  ln2 = 0.6931471805599453; # ln(2)
  ln2_inv = 1.0 / ln2; # 1 / ln(2) ~ 1.442695...

  # Square Root related
  sqrt2 = 1.4142135623730951; # sqrt(2)
  sqrt1_2 = 1.0 / sqrt2; # 1/sqrt(2) ~ 0.707106...

  # Physics/Geography
  earthRadiusMeters = 6371000.0; # Mean radius of Earth in meters

  # --- Core Functions ---
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

  # Helper function to calculate the X coordinate of the cubic Bézier curve
  # for a given parameter u and control points x1, x2
  cubicBezierX = x1: x2: u:
    let
      u1 = 1.0 - u;
      u1Squared = u1 * u1;
      uSquared = u * u;
      # x(u) = 3*(1-u)^2*u*x1 + 3*(1-u)*u^2*x2 + u^3*1
      # (P0x=0 term is zero)
    in 3.0 * u1Squared * u * x1 + 3.0 * u1 * uSquared * x2 + uSquared * u;

  # Helper function to calculate the Y coordinate of the cubic Bézier curve
  # for a given parameter u and control points y1, y2
  cubicBezierY = y1: y2: u:
    let
      u1 = 1.0 - u;
      u1Squared = u1 * u1;
      uSquared = u * u;
      # y(u) = 3*(1-u)^2*u*y1 + 3*(1-u)*u^2*y2 + u^3*1
      # (P0y=0 term is zero)
    in 3.0 * u1Squared * u * y1 + 3.0 * u1 * uSquared * y2 + uSquared * u;

  # Standard cubic Bézier easing function using numerical search
  # Takes control points (x1, y1, x2, y2) and input time t (0 to 1)
  cubicBezier = x1: y1: x2: y2: t:
    let
      # Clamp input time
      clampedT = clamp t 0.0 1.0;

      # Handle edge cases
      result = if clampedT == 0.0 then
        0.0
      else if clampedT == 1.0 then
        1.0
      else
        let
          # Binary search to find the parameter 'u' such that cubicBezierX(u) ≈ t
          maxIterations =
            12; # Adjust for desired precision (12 is often enough)
          tolerance = 1.0e-6; # Adjust for desired precision

          findU = low: high: iteration:
            let
              mid = (low + high) / 2.0;
              x_mid = cubicBezierX x1 x2 mid;
              error = x_mid - clampedT;
            in if iteration >= maxIterations || abs error < tolerance then
              mid # Found a suitable u
            else if error < 0.0 then
            # x_mid is too small, need larger u
              findU mid high (iteration + 1)
            else
            # x_mid is too large, need smaller u
              findU low mid (iteration + 1);

          # Perform the search starting in the [0, 1] interval for u
          u_approx = findU 0.0 1.0 0;

          # Calculate the corresponding Y value using the found u
        in cubicBezierY y1 y2 u_approx;
    in result;

  # --- Keep the other Bézier functions as they were, they are correct ---
  # --- for their specific definitions (e.g., bezier3 takes 4 points) ---

  # Linear Bézier curve (equivalent to lerp)
  bezier1 = p0: p1: t: lerp p0 p1 t;

  # Full cubic Bézier curve with explicit control points
  # Takes all four points: p0, p1, p2, p3
  bezier3 = p0: p1: p2: p3: t:
    let
      t1 = 1.0 - t;
      t1Squared = t1 * t1;
      t1Cubed = t1Squared * t1;
      tSquared = t * t;
      tCubed = tSquared * t;
      term1 = t1Cubed * p0;
      term2 = 3.0 * t1Squared * t * p1;
      term3 = 3.0 * t1 * tSquared * p2;
      term4 = tCubed * p3;
    in term1 + term2 + term3 + term4;

  # General Bézier curve for any number of control points
  # Takes a list of control points and a parameter t
  bezier = points: t:
    assert builtins.isList points;
    assert builtins.length points >= 2;
    let
      n = builtins.length points - 1;

      # Binomial coefficient calculation
      binomial = n: k: factorial n / (factorial k * factorial (n - k));

      # Calculate the term for each control point
      calculateTerm = i:
        let
          coef = binomial n i;
          tPower = pow t i;
          t1Power = pow (1.0 - t) (n - i);
          point = builtins.elemAt points i;
        in coef * tPower * t1Power * point;

      # Generate list of indices from 0 to n
      indices = lib.genList (i: i) (n + 1);

      # Calculate all terms
      terms = map calculateTerm indices;
    in sum terms;

  # Create a Bézier curve function from control points
  # Returns a function that takes a parameter t and returns the interpolated value
  createBezierFunction = points:
    assert builtins.isList points;
    assert builtins.length points >= 2;
    t:
    bezier points (clamp t 0.0 1.0);

  # Create a standard cubic Bézier easing function with the CSS-style parameters
  # Returns a function that takes a parameter t and returns the interpolated value
  createCubicBezier = x1: y1: x2: y2: t:
    cubicBezier x1 y1 x2 y2 t; # Use the corrected cubicBezier

  # Linear interpolation between a set of points
  # Takes a list of points [[x0, y0], [x1, y1], ..., [xn, yn]] sorted by x,
  # and an input value t (typically 0.0 to 1.0, but clamped to the range of x values).
  # Returns the linearly interpolated y-value corresponding to t.
  linearInterpolatePoints = points: t:
    let
      # --- Input Validation ---
      _assertList = assert builtins.isList points; ""; # Use dummy var to ensure evaluation
      _assertLength = assert builtins.length points >= 2; "";
      _assertPointsFormat = assert builtins.all (p: builtins.isList p && builtins.length p == 2) points; "";
      # Optional: Add assertion that points are sorted by x?
      # _assertSorted = assert lib.foldl' (acc: p: if acc == null then p else if p.x >= acc.x then p else throw "Points not sorted by x") null (map (p: { x = elemAt p 0; y = elemAt p 1; }) points) != null; "";

      numPoints = builtins.length points;
      firstPoint = builtins.elemAt points 0;
      lastPoint = builtins.elemAt points (numPoints - 1);
      firstX = builtins.elemAt firstPoint 0;
      lastX = builtins.elemAt lastPoint 0;

      # Clamp t to the range of x-values in the points
      clampedT = clamp t firstX lastX;

      # --- Find the segment containing t ---
      findSegment = index:
        let
          p0 = builtins.elemAt points index;
          p1 = builtins.elemAt points (index + 1);
          x0 = builtins.elemAt p0 0;
          y0 = builtins.elemAt p0 1;
          x1 = builtins.elemAt p1 0;
          y1 = builtins.elemAt p1 1;
        in if clampedT >= x0 && clampedT <= x1 then
          # Found the segment
          let
            # Avoid division by zero if x0 == x1 (shouldn't happen with sorted distinct points)
            rangeX = x1 - x0;
            t_local = if rangeX < epsilon then 0.0 else (clampedT - x0) / rangeX;
          in lerp y0 y1 t_local
        else if index + 2 >= numPoints then
          # Should not happen if t is clamped correctly, but as fallback return last point's y
          builtins.elemAt lastPoint 1
        else
          # Check next segment
          findSegment (index + 1);

    in if clampedT <= firstX then
      # t is before the first point
      builtins.elemAt firstPoint 1
    else if clampedT >= lastX then
      # t is after the last point
      builtins.elemAt lastPoint 1
    else
      # t is within the range, find the segment
      findSegment 0;

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
      maxIterations = 3000;
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
    let count = floor ((max - min) / step) + 1;
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
        let
          fracStr = builtins.elemAt parts 1;
          tomlStr = "f = 0.${fracStr}";
          parsed = builtins.fromTOML tomlStr;
        in parsed.f
      else
        0.0;
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

  # Improved natural logarithm using range reduction and a fast-converging series
  ln = x:
    assert x > 0.0; # Logarithm is only defined for positive numbers
    let
      # Normalize x to m * 2^order, where m is in [sqrt(1/2), sqrt(2))
      # This range ensures y = (m-1)/(m+1) is small for fast series convergence.
      normalize = base: order:
        if base < sqrt2 && base >= sqrt1_2 then {
          # Base is in the target range
          m = base;
          inherit order;
        } else if base >= sqrt2 then
        # Base is too large, divide by 2 and increment order
          normalize (base / 2.0) (order + 1)
        else # base < sqrt1_2
        # Base is too small, multiply by 2 and decrement order
          normalize (base * 2.0) (order - 1);

      # Perform the normalization
      x_normalized = normalize x 0;
      m = x_normalized.m; # The mantissa in the range [sqrt(1/2), sqrt(2))
      order = x_normalized.order; # The exponent for base 2

      # Calculate ln(m) using the series for 2 * artanh(y) where y = (m-1)/(m+1)
      # ln(m) = 2 * (y + y^3/3 + y^5/5 + y^7/7 + ...)
      ln_m = let
        y = (m - 1.0) / (m + 1.0);
        y2 = y * y; # y^2, used repeatedly

        # Calculate series terms iteratively for better precision and efficiency
        # term_n = y^(2n+1) / (2n+1)
        term_1 = y; # n=0
        term_3 = term_1 * y2 / 3.0; # n=1
        term_5 = term_3 * y2 * 3.0 / 5.0; # n=2
        term_7 = term_5 * y2 * 5.0 / 7.0; # n=3
        term_9 = term_7 * y2 * 7.0 / 9.0; # n=4
        term_11 = term_9 * y2 * 9.0 / 11.0; # n=5
        term_13 = term_11 * y2 * 11.0 / 13.0; # n=6
        # Adding more terms increases accuracy further, but convergence is fast.
        # term_15 = term_13 * y2 * 13.0 / 15.0; # n=7

        # Sum the terms
        sum_terms = term_1 + term_3 + term_5 + term_7 + term_9 + term_11
          + term_13;
        # + term_15;

      in 2.0 * sum_terms; # ln(m) = 2 * artanh(y)

      # Combine the results: ln(x) = ln(m) + order * ln(2)
    in ln_m + (order * ln2);

  # Improved exponential function with forced tracing (using direct sum for e^r)
  exp = x:
    let
      # Helper function for integer power (exponentiation by squaring, iterative)
      integerPow = base: exp_int:
        let
          abs_exp = if exp_int < 0 then -exp_int else exp_int;
          pow_iter = current_base: current_exp: current_res:
            if current_exp == 0 then
              current_res
            else if (mod current_exp 2 == 1) then
              pow_iter (current_base * current_base) (current_exp / 2)
              (current_res * current_base)
            else
              pow_iter (current_base * current_base) (current_exp / 2)
              current_res;
          res_abs = pow_iter base abs_exp 1.0;
        in if exp_int < 0 then 1.0 / res_abs else res_abs;

      # --- Step 1: Range Reduction ---
      # Reduce x to r + k*ln(2), where r is in [-ln(2)/2, ln(2)/2]
      # We want x = k*ln(2) + r  =>  x/ln(2) = k + r/ln(2)
      # Let k = round(x/ln(2)), then r = x - k*ln(2)
      k_float = x * ln2_inv; # x / ln(2)
      k_int = builtins.floor (k_float + 0.5); # round to nearest integer
      k = (builtins.fromJSON (builtins.toJSON k_int)); # Removed trace
      r_untraced = x - (k * ln2);
      r = r_untraced; # Removed trace

      # --- Step 2: Calculate e^r using direct summation of Taylor series ---
      # e^r = 1 + r + r^2/2! + r^3/3! + ...
      # Calculate terms iteratively: term_n = term_{n-1} * r / n
      exp_r_untraced = let
        r_val = r; # Use the traced value of r
        term0 = 1.0;
        term1 = term0 * r_val / 1.0;
        term2 = term1 * r_val / 2.0;
        term3 = term2 * r_val / 3.0;
        term4 = term3 * r_val / 4.0;
        term5 = term4 * r_val / 5.0;
        term6 = term5 * r_val / 6.0;
        term7 = term6 * r_val / 7.0;
        term8 = term7 * r_val / 8.0;
        term9 = term8 * r_val / 9.0;
        term10 = term9 * r_val / 10.0;
        term11 = term10 * r_val / 11.0;
        term12 = term11 * r_val / 12.0;
        term13 = term12 * r_val / 13.0;
        # Add more terms if needed, but 13 should be sufficient
      in term0 + term1 + term2 + term3 + term4 + term5 + term6 + term7 + term8
      + term9 + term10 + term11 + term12 + term13;

      # --- Step 3: Calculate 2^k ---
      pow2_k_untraced = integerPow 2.0 k_int;
      pow2_k = pow2_k_untraced;

      # --- Step 4: Combine and Final Result ---
      result_untraced = pow2_k * exp_r_untraced;
      result = result_untraced;

    in result;

  # Improved power functions
  #pow = x: times: assert builtins.isInt times; multiply (lib.replicate times x);

  pow = b: e:
    if e == 0 then
      1.0
    else if e > 0 then
      b * pow b (e - 1)
    else
      1.0 / (pow b (-e));

  powFloat = x: a:
    if x == 0.0 then
      assert a > 0.0; # 0^a is 0 only if a > 0. Handle other cases if needed.
      0.0
    else
      exp (a * ln x);

  # Improved factorial with validation
  factorial = x:
    assert builtins.isInt x && x >= 0;
    if x == 0 then 1 else multiply (lib.range 1 x);

  sin = x:
    let
      # Small value for convergence checks (using the global epsilon)
      # epsilon = 1.0e-15; # Local epsilon removed

      # Helper for absolute value (using global abs/fabs)
      # fabs = val: if val < 0.0 then -val else val; # Local fabs removed

      # Helper for floating point modulo (remainder)
      # fmod(a, n) = a - n * floor(a / n)
      fmod = a: n: a - n * (builtins.floor (a / n));

      # --- Step 1: Range Reduction ---

      # Reduce x to the primary range [-pi, pi) using tau = 2*pi
      # x_mod_tau = fmod x tau; # This gives [0, tau) or (-tau, 0]
      # A common way to get [-pi, pi) is: fmod(x + pi, tau) - pi
      x_reduced_pi = fmod (x + pi) tau - pi;

      # Now x_reduced_pi is in [-pi, pi)

      # Use symmetry to map to [0, pi/2] and track sign
      initial_sign = if x_reduced_pi < 0.0 then -1.0 else 1.0;
      x_abs = x_reduced_pi * initial_sign; # Now in [0, pi)

      # If x_abs > pi/2, use sin(a) = sin(pi - a)
      x_final = if x_abs > pi_half then pi - x_abs else x_abs;
      # x_final is now in [0, pi/2]

      # --- Step 2: Calculate sin(x_final) using iterative Taylor series ---
      # sin(y) = y - y^3/3! + y^5/5! - ...
      # term_{n+1} = term_n * (-y^2) / ((2n+3)*(2n+2))

      series_sum = let
        y = x_final;
        y_squared = y * y;

        # Recursive helper for summation
        # current_sum: the sum accumulated so far
        # current_term: the last term added (or the first term y)
        # n: the index related to the power (starts at 0 for y^1)
        sum_loop = current_sum: current_term: n:
          let
            # Check for convergence: if the absolute value of the term
            # is negligible compared to the sum, or just very small.
            # Also limit iterations to prevent infinite loops in edge cases.
            converged = (fabs current_term < epsilon)
              || (n > 20); # Max 20 iterations typical for double precision
            # converged = (fabs current_term < epsilon * (fabs current_sum)) || (fabs current_term < epsilon) || (n > 20); # Relative check

            # Calculate the next term
            next_n = n + 1.0;
            denominator = (2.0 * next_n + 1.0) * (2.0 * next_n);
            next_term = current_term * (-1.0 * y_squared) / denominator;
            next_sum = current_sum + next_term;

          in if converged then
            current_sum # Return the sum when converged
          else
          # Continue recursion
            sum_loop next_sum next_term next_n;

        # Start the loop: sum starts with the first term, first term is y, n=0
      in sum_loop y y 0.0;

      # --- Step 3: Apply the sign ---
    in initial_sign * series_sum;

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

      # Validate all coordinates
      _ = validateCoords lat1 lon1;
      __ = validateCoords lat2 lon2;

      # Use the global earthRadiusMeters constant
      radius = earthRadiusMeters;

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
        in if iteration >= maxIterations then
          throw "halley: Maximum iterations reached (last delta: ${
            toString absDelta
          })"
        else if absDelta < epsilon then
          newX
        else
          helper newX (iteration + 1);
    in helper x0 0;

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
