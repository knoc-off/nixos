{
  lib ? import <nixpkgs/lib>,
}:

# Math functions actually used by lib/color-lib/*.nix and theme.nix:
# abs, atan2, cbrt, clamp, cos, fabs, fmod, max, min, pi, powFloat, sin, sqrt.
# Everything below is either one of those or a dependency of one of those
# (e.g. powFloat needs exp+ln, sin needs fmod, exp needs mod).

rec {
  # --- Constants ---
  pi = 3.141592653589793;
  tau = 2.0 * pi;
  pi_half = pi / 2.0;
  epsilon = 1.0e-10; # Small number for floating-point comparisons

  # Natural Logarithm related
  ln2 = 0.6931471805599453; # ln(2)
  ln2_inv = 1.0 / ln2; # 1 / ln(2) ~ 1.442695...

  # Square Root related
  sqrt2 = 1.4142135623730951; # sqrt(2)
  sqrt1_2 = 1.0 / sqrt2; # 1/sqrt(2) ~ 0.707106...

  inherit (builtins) floor;

  # Improved min/max functions with type checking
  min =
    a: b:
    assert builtins.isFloat a || builtins.isInt a;
    assert builtins.isFloat b || builtins.isInt b;
    if a < b then a else b;

  max =
    a: b:
    assert builtins.isFloat a || builtins.isInt a;
    assert builtins.isFloat b || builtins.isInt b;
    if a > b then a else b;

  # Improved clamp function that handles min > max case
  clamp =
    x: a: b:
    let
      sorted = lib.sort (x: y: x < y) [
        a
        b
      ];
      minVal = builtins.elemAt sorted 0;
      maxVal = builtins.elemAt sorted 1;
    in
    max minVal (min maxVal x);

  # Absolute value functions
  abs = x: if x < 0 then 0 - x else x;
  fabs = abs;

  # Improved cube root with iteration limit and validation
  cbrt =
    x:
    let
      maxIterations = 3000;
      absX = abs x + 0.0;

      helper =
        guess: iteration:
        let
          newGuess = (2 * guess + absX / (guess * guess)) / 3;
          delta = abs (newGuess - guess);
        in
        if iteration >= maxIterations then
          abort "cbrt: Maximum iterations reached"
        else if delta < epsilon then
          newGuess
        else
          helper newGuess (iteration + 1);

      initialGuess = if absX < 1 then absX else absX / 3;
      result = helper initialGuess 0;
    in
    if x == 0 then
      0
    else if x < 0 then
      -result
    else
      result;

  # Improved modulo operation
  mod =
    a: b:
    assert b != 0;
    if b < 0 then
      0 - mod (0 - a) (0 - b)
    else if a < 0 then
      mod (b - mod (0 - a) b) b
    else
      a - b * (floor (1.0 * a / b));

  fmod = x: y: x - y * floor (x / y);

  # Improved natural logarithm using range reduction and a fast-converging series
  ln =
    x:
    assert x > 0.0; # Logarithm is only defined for positive numbers
    let
      # Normalize x to m * 2^order, where m is in [sqrt(1/2), sqrt(2))
      # This range ensures y = (m-1)/(m+1) is small for fast series convergence.
      normalize =
        base: order:
        if base < sqrt2 && base >= sqrt1_2 then
          {
            # Base is in the target range
            m = base;
            inherit order;
          }
        else if base >= sqrt2 then
          # Base is too large, divide by 2 and increment order
          normalize (base / 2.0) (order + 1)
        # base < sqrt1_2
        else
          # Base is too small, multiply by 2 and decrement order
          normalize (base * 2.0) (order - 1);

      # Perform the normalization
      x_normalized = normalize x 0;
      m = x_normalized.m; # The mantissa in the range [sqrt(1/2), sqrt(2))
      order = x_normalized.order; # The exponent for base 2

      # Calculate ln(m) using the series for 2 * artanh(y) where y = (m-1)/(m+1)
      # ln(m) = 2 * (y + y^3/3 + y^5/5 + y^7/7 + ...)
      ln_m =
        let
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

          # Sum the terms
          sum_terms = term_1 + term_3 + term_5 + term_7 + term_9 + term_11 + term_13;

        in
        2.0 * sum_terms; # ln(m) = 2 * artanh(y)

      # Combine the results: ln(x) = ln(m) + order * ln(2)
    in
    ln_m + (order * ln2);

  # Improved exponential function (using direct sum for e^r)
  exp =
    x:
    let
      # Helper function for integer power (exponentiation by squaring, iterative)
      integerPow =
        base: exp_int:
        let
          abs_exp = if exp_int < 0 then -exp_int else exp_int;
          pow_iter =
            current_base: current_exp: current_res:
            if current_exp == 0 then
              current_res
            else if (mod current_exp 2 == 1) then
              pow_iter (current_base * current_base) (current_exp / 2) (current_res * current_base)
            else
              pow_iter (current_base * current_base) (current_exp / 2) current_res;
          res_abs = pow_iter base abs_exp 1.0;
        in
        if exp_int < 0 then 1.0 / res_abs else res_abs;

      # --- Step 1: Range Reduction ---
      # Reduce x to r + k*ln(2), where r is in [-ln(2)/2, ln(2)/2]
      # x = k*ln(2) + r  =>  x/ln(2) = k + r/ln(2)
      # Let k = round(x/ln(2)), then r = x - k*ln(2)
      k_float = x * ln2_inv; # x / ln(2)
      k_int = builtins.floor (k_float + 0.5); # round to nearest integer
      k = (builtins.fromJSON (builtins.toJSON k_int));
      r = x - (k * ln2);

      # --- Step 2: Calculate e^r using direct summation of Taylor series ---
      # e^r = 1 + r + r^2/2! + r^3/3! + ...
      exp_r =
        let
          term0 = 1.0;
          term1 = term0 * r / 1.0;
          term2 = term1 * r / 2.0;
          term3 = term2 * r / 3.0;
          term4 = term3 * r / 4.0;
          term5 = term4 * r / 5.0;
          term6 = term5 * r / 6.0;
          term7 = term6 * r / 7.0;
          term8 = term7 * r / 8.0;
          term9 = term8 * r / 9.0;
          term10 = term9 * r / 10.0;
          term11 = term10 * r / 11.0;
          term12 = term11 * r / 12.0;
          term13 = term12 * r / 13.0;
        in
        term0
        + term1
        + term2
        + term3
        + term4
        + term5
        + term6
        + term7
        + term8
        + term9
        + term10
        + term11
        + term12
        + term13;

      # --- Step 3: Calculate 2^k, then combine ---
      pow2_k = integerPow 2.0 k_int;
    in
    pow2_k * exp_r;

  powFloat =
    x: a:
    if x == 0.0 then
      assert a > 0.0; # 0^a is 0 only if a > 0.
      0.0
    else
      exp (a * ln x);

  sin =
    x:
    let
      # --- Step 1: Range Reduction ---
      # Reduce x to the primary range [-pi, pi) using tau = 2*pi
      x_reduced_pi = fmod (x + pi) tau - pi;

      # Use symmetry to map to [0, pi/2] and track sign
      initial_sign = if x_reduced_pi < 0.0 then -1.0 else 1.0;
      x_abs = x_reduced_pi * initial_sign; # Now in [0, pi)

      # If x_abs > pi/2, use sin(a) = sin(pi - a)
      x_final = if x_abs > pi_half then pi - x_abs else x_abs;
      # x_final is now in [0, pi/2]

      # --- Step 2: Calculate sin(x_final) using iterative Taylor series ---
      # sin(y) = y - y^3/3! + y^5/5! - ...
      # term_{n+1} = term_n * (-y^2) / ((2n+3)*(2n+2))
      series_sum =
        let
          y = x_final;
          y_squared = y * y;

          sum_loop =
            current_sum: current_term: n:
            let
              converged = (fabs current_term < epsilon) || (n > 20); # Max 20 iterations typical for double precision
              next_n = n + 1.0;
              denominator = (2.0 * next_n + 1.0) * (2.0 * next_n);
              next_term = current_term * (-1.0 * y_squared) / denominator;
              next_sum = current_sum + next_term;
            in
            if converged then current_sum else sum_loop next_sum next_term next_n;
        in
        sum_loop y y 0.0;

      # --- Step 3: Apply the sign ---
    in
    initial_sign * series_sum;

  cos = x: sin (0.5 * pi - x);

  # Improved inverse trigonometric functions
  atan =
    x:
    let
      arctanPart =
        x:
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
        in
        x * (builtins.foldl' (a: b: a * xx + b) 0 coefficients);

      arctanPositive = x: if x <= 1.0 then arctanPart x else pi / 2 - arctanPart (1.0 / x);
    in
    if x >= 0.0 then arctanPositive x else (-1.0) * arctanPositive (-x);

  # Improved atan2 with complete quadrant handling
  atan2 =
    y: x:
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
  sqrt =
    x:
    assert x >= 0;
    let
      maxIterations = 50;
      helper =
        tmp: iteration:
        let
          value = (tmp + 1.0 * x / tmp) / 2;
          delta = fabs (value - tmp);
        in
        if iteration >= maxIterations then
          abort "sqrt: Maximum iterations reached"
        else if delta < epsilon then
          value
        else
          helper value (iteration + 1);
    in
    if x < epsilon then 0 else helper (1.0 * x) 0;
}
