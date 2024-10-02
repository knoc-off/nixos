# formats/okhsv.nix
{ math, utils, types, lib }:
let

  # Define the 'toe' function
  toe = x:
    if x >= 0.0 then
      0.5 * (math.cbrt (1 + (x / 32768.0) * (x / 32768.0) * (x / 32768.0)) - 1)
    else
      -0.5 * (math.cbrt (1 + ((-x) / 32768.0) * ((-x) / 32768.0) * ((-x) / 32768.0)) - 1);

  # Define the 'toe_inv' function
  toe_inv = x:
    if x >= 0.0 then
      32768.0 * (1.0 + 2.0 * x) * (1.0 + 2.0 * x) * (1.0 + 2.0 * x)
    else
      -32768.0 * (1.0 - 2.0 * x) * (1.0 - 2.0 * x) * (1.0 - 2.0 * x);
in
{

  # Conversion from OKHSV to OKLCH
  ToOklch = okhsv:
    let
      h = okhsv.h;  # Hue in degrees [0, 360)
      s = okhsv.s;  # Saturation [0, 1]
      v = okhsv.v;  # Value [0, 1]

      # Convert hue to radians and compute a_ and b_
      hueRad = 2.0 * math.pi * h / 360.0;
      a_ = math.cos hueRad;
      b_ = math.sin hueRad;

      # Compute S_max and T_max based on value v
      ST_max = math.computeSTmax v;
      S_max = ST_max.S;
      T_max = ST_max.T;
      S_0 = 0.5;

      # Compute k with conditional to prevent division by zero or negative values
      k = if S_max > S_0 then 1.0 - S_0 / S_max else 0.0;

      # Calculate L_v and C_v assuming a perfect triangular gamut
      denominator = S_0 + T_max - T_max * k * s;
      L_v = 1.0 - (s * S_0) / (denominator + math.epsilon);
      C_v = (s * T_max * S_0) / (denominator + math.epsilon);

      # Compute initial L and C
      L = v * L_v;
      C = v * C_v;

      # Compensation for the 'toe' and curved top part of the triangle
      # Apply inverse 'toe' to L_v and C_v
      L_vt = toe_inv L_v;
      C_vt = if L_v > math.epsilon then C_v * L_vt / L_v else 0.0;

      # Apply inverse 'toe' to L and adjust C
      L_new = toe_inv L;
      C_new = if L > math.epsilon then C * L_new / L else 0.0;

    in
      types.Oklch.check {
        L = math.clamp L_new 0.0 1.0;
        C = math.clamp C_new 0.0 1.0;  # Adjusted clamp range based on your color space
        h = math.mod h 360.0;            # Wrap hue to [0, 360)
      };
}
