# formats/okhsl.nix
{ math, utils, lib }:

{
  # Convert OkLab to OkHSL
  oklabToOkhsl = { L, a, b, alpha ? 1 }: let
    C = math.sqrt (a * a + b * b);
    h = math.atan2 b a;
    # Ensure h is in the range [0, tau)
    h' = if h < 0 then h + math.tau else h;
    # Calculate saturation based on Lightness and Chroma
    denominator = 1 - math.abs (2 * L - 1);
    S = if denominator > 0 then C / denominator else 0;
  in {
    h = h';  # Hue in radians
    S = utils.clamp S 0 1;  # Ensure S is within [0, 1]
    L = L;
    alpha = alpha;
  };

  # Convert OkHSL back to OkLab
  okhslToOklab = { h, S, L, alpha ? 1 }: let
    # Calculate Chroma from Saturation and Lightness
    C = if (1 - math.abs (2 * L - 1)) > 0 then S * (1 - math.abs (2 * L - 1)) else 0;
    a = C * math.cos h;
    b = C * math.sin h;
  in {
    L = L;
    a = a;
    b = b;
    alpha = alpha;
  };
}
