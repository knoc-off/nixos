# check.nix
{ lib ? import <nixpkgs/lib>
, math ? import ../math.nix { inherit lib; }
, core ? import ./core.nix { inherit lib math; }
, oklab ? import ./oklab.nix { inherit core math; }
, okhsv ? import ./okhsv.nix { inherit core math oklab; }
}:

let
  inherit (core) hex srgbTransferInv;
  inherit (math) sqrt epsilon;
  inherit (oklab) linearSRGBToOklab findCusp;

  # Function to check a specific hex color
  checkColor = hexStr:
    let
      # Step 1: Hex to sRGB
      rgb = hex.toRGB hexStr;

      # Step 2: Linearize sRGB
      linearRGB = {
        r = srgbTransferInv rgb.r;
        g = srgbTransferInv rgb.g;
        b = srgbTransferInv rgb.b;
        alpha = rgb.alpha;
      };

      # Step 3: Convert to Oklab
      lab = linearSRGBToOklab linearRGB;

      # Step 4: Compute chroma and normalized components
      C = sqrt (lab.a * lab.a + lab.b * lab.b);
      a_norm = if C == 0.0 then 0.0 else lab.a / C;
      b_norm = if C == 0.0 then 0.0 else lab.b / C;

      # Step 5: Find the cusp
      cusp = findCusp a_norm b_norm;

      # Step 6: Compute T_max and related values
      T_max = cusp.C / (1 - cusp.L);
      t = if T_max == 0.0 then 1.0 else T_max / (C + lab.L * T_max + epsilon);
      L_v = t * lab.L;
      C_v = t * C;

      # Step 7: Final OKHSV conversion
      finalHSV = okhsv.fromRGB rgb;

    in {
      # Input
      input = {
        hex = hexStr;
        rgb = rgb;
      };

      # Intermediate values
      intermediate = {
        # Linear RGB values
        linearRGB = linearRGB;

        # Oklab values
        lab = lab;

        # Chroma and normalized components
        chroma = {
          C = C;
          a_norm = a_norm;
          b_norm = b_norm;
        };

        # Cusp and related values
        cusp = {
          inherit cusp;
          T_max = T_max;
          t = t;
          L_v = L_v;
          C_v = C_v;
        };
      };

      # Final output
      output = finalHSV;
    };

in {
  # Function to check any hex color
  inherit checkColor;

  # Pre-computed examples
  example1 = checkColor "2a6d6d";  # Your test case
  example2 = checkColor "27292b";  # Dark gray
  example3 = checkColor "FFF";     # White
  example4 = checkColor "F00";     # Pure red
}

