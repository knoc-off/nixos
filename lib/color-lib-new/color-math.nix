# color-lib/default.nix
{ lib ? import <nixpkgs/lib>, math ? import ../math.nix { inherit lib; } }:

let
  # Small epsilon for safe division and comparisons
  epsilon = 1.0e-8; # Use the one from your lib if preferred
  large_float = 1.0e30; # Approximation for FLT_MAX

  # Sign function
  sgn = x: if x > 0.0 then 1.0 else if x < 0.0 then -1.0 else 0.0;

  # sRGB Transfer Functions (Gamma Correction)
  srgb_transfer_function = a:
    if a <= 0.0031308 then 12.92 * a else 1.055 * (math.powFloat a (1.0 / 2.4)) - 0.055;

  srgb_transfer_function_inv = a:
    if a <= 0.04045 then a / 12.92 else math.powFloat ((a + 0.055) / 1.055) 2.4;

  # Oklab Conversions
  linear_srgb_to_oklab = c: # c = { r, g, b }
    let
      l = 0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b;
      m = 0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b;
      s = 0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b;

      l_ = math.cbrt l;
      m_ = math.cbrt m;
      s_ = math.cbrt s;
    in {
      L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
      a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
      b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;
    }; # Returns { L, a, b }

  oklab_to_linear_srgb = c: # c = { L, a, b }
    let
      l_ = c.L + 0.3963377774 * c.a + 0.2158037573 * c.b;
      m_ = c.L - 0.1055613458 * c.a - 0.0638541728 * c.b;
      s_ = c.L - 0.0894841775 * c.a - 1.2914855480 * c.b;

      l = l_ * l_ * l_;
      m = m_ * m_ * m_;
      s = s_ * s_ * s_;
    in {
      r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
      g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
      b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
    }; # Returns { r, g, b }

  # Gamut Intersection Helpers
  # compute_max_saturation: Finds max saturation S = C/L for a given normalized hue (a, b)
  compute_max_saturation = a: b:
    let
      # Select coefficients based on which channel clips first
      coeffs = if (-1.88170328 * a - 0.80936493 * b > 1.0) then {
        # Red component clips
        k0 = 1.19086277; k1 = 1.76576728; k2 = 0.59662641; k3 = 0.75515197; k4 = 0.56771245;
        wl = 4.0767416621; wm = -3.3077115913; ws = 0.2309699292;
      } else if (1.81444104 * a - 1.19445276 * b > 1.0) then {
        # Green component clips
        k0 = 0.73956515; k1 = -0.45954404; k2 = 0.08285427; k3 = 0.12541070; k4 = 0.14503204;
        wl = -1.2684380046; wm = 2.6097574011; ws = -0.3413193965;
      } else {
        # Blue component clips
        k0 = 1.35733652; k1 = -0.00915799; k2 = -1.15130210; k3 = -0.50559606; k4 = 0.00692167;
        wl = -0.0041960863; wm = -0.7034186147; ws = 1.7076147010;
      };

      # Approximate max saturation using polynomial
      S_initial = coeffs.k0 + coeffs.k1 * a + coeffs.k2 * b + coeffs.k3 * a * a + coeffs.k4 * a * b;

      # One step Halley's method refinement
      k_l = 0.3963377774 * a + 0.2158037573 * b;
      k_m = -0.1055613458 * a - 0.0638541728 * b;
      k_s = -0.0894841775 * a - 1.2914855480 * b;

      # Calculate f, f', f'' for Halley's method
      l_ = 1.0 + S_initial * k_l;
      m_ = 1.0 + S_initial * k_m;
      s_ = 1.0 + S_initial * k_s;

      l = l_ * l_ * l_;
      m = m_ * m_ * m_;
      s = s_ * s_ * s_;

      l_dS = 3.0 * k_l * l_ * l_;
      m_dS = 3.0 * k_m * m_ * m_;
      s_dS = 3.0 * k_s * s_ * s_;

      l_dS2 = 6.0 * k_l * k_l * l_;
      m_dS2 = 6.0 * k_m * k_m * m_;
      s_dS2 = 6.0 * k_s * k_s * s_;

      f = coeffs.wl * l + coeffs.wm * m + coeffs.ws * s;
      f1 = coeffs.wl * l_dS + coeffs.wm * m_dS + coeffs.ws * s_dS;
      f2 = coeffs.wl * l_dS2 + coeffs.wm * m_dS2 + coeffs.ws * s_dS2;

      # Halley's update: S = S - f * f' / (f'^2 - 0.5 * f * f'')
      S_refined = S_initial - f * f1 / (f1 * f1 - 0.5 * f * f2 + epsilon); # Add epsilon for safety

    in S_refined;

  # find_cusp: Finds the L, C coordinates of the sRGB gamut cusp for a given normalized hue (a, b)
  find_cusp = a: b:
    let
      S_cusp = compute_max_saturation a b;
      rgb_at_max = oklab_to_linear_srgb { L = 1.0; a = S_cusp * a; b = S_cusp * b; };
      # Need to handle potential negative values in rgb_at_max before cbrt if L_cusp calc is exact
      max_rgb = math.max rgb_at_max.r (math.max rgb_at_max.g rgb_at_max.b);
      L_cusp = math.cbrt (1.0 / (math.max max_rgb epsilon)); # Ensure max_rgb > 0
      C_cusp = L_cusp * S_cusp;
    in { L = L_cusp; C = C_cusp; }; # Returns { L, C }

  # find_gamut_intersection: Finds intersection parameter t for a line segment
  # from (L0, 0) to (L1, C1) with the sRGB gamut boundary for hue (a, b).
  # Requires pre-computed cusp { L, C } for efficiency.
  find_gamut_intersection_with_cusp = a: b: L1: C1: L0: cusp:
    let
      t_initial = if (((L1 - L0) * cusp.C - (cusp.L - L0) * C1) <= 0.0) then
        # Lower half intersection (triangle approximation is exact)
        cusp.C * L0 / (C1 * cusp.L + cusp.C * (L0 - L1) + epsilon) # Add epsilon for safety
      else
        # Upper half intersection
        let
          # First intersect with the triangle approximation
          t_triangle = cusp.C * (L0 - 1.0) / (C1 * (cusp.L - 1.0) + cusp.C * (L0 - L1) + epsilon);

          # Then one step Halley's method for refinement
          dL = L1 - L0;
          dC = C1;

          k_l = 0.3963377774 * a + 0.2158037573 * b;
          k_m = -0.1055613458 * a - 0.0638541728 * b;
          k_s = -0.0894841775 * a - 1.2914855480 * b;

          l_dt = dL + dC * k_l;
          m_dt = dL + dC * k_m;
          s_dt = dL + dC * k_s;

          # Calculate values at t_triangle
          L = L0 * (1.0 - t_triangle) + t_triangle * L1;
          C = t_triangle * C1;

          l_ = L + C * k_l;
          m_ = L + C * k_m;
          s_ = L + C * k_s;

          l = l_ * l_ * l_;
          m = m_ * m_ * m_;
          s = s_ * s_ * s_;

          ldt = 3.0 * l_dt * l_ * l_;
          mdt = 3.0 * m_dt * m_ * m_;
          sdt = 3.0 * s_dt * s_ * s_;

          ldt2 = 6.0 * l_dt * l_dt * l_;
          mdt2 = 6.0 * m_dt * m_dt * m_;
          sdt2 = 6.0 * s_dt * s_dt * s_;

          # Calculate residuals and derivatives for R, G, B channels going out of gamut ( > 1)
          r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s - 1.0;
          r1 = 4.0767416621 * ldt - 3.3077115913 * mdt + 0.2309699292 * sdt;
          r2 = 4.0767416621 * ldt2 - 3.3077115913 * mdt2 + 0.2309699292 * sdt2;
          u_r_den = r1 * r1 - 0.5 * r * r2;
          u_r = if math.fabs u_r_den < epsilon then 0.0 else r1 / u_r_den; # Avoid division by zero
          t_r = if u_r >= 0.0 then -r * u_r else large_float;

          g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s - 1.0;
          g1 = -1.2684380046 * ldt + 2.6097574011 * mdt - 0.3413193965 * sdt;
          g2 = -1.2684380046 * ldt2 + 2.6097574011 * mdt2 - 0.3413193965 * sdt2;
          u_g_den = g1 * g1 - 0.5 * g * g2;
          u_g = if math.fabs u_g_den < epsilon then 0.0 else g1 / u_g_den;
          t_g = if u_g >= 0.0 then -g * u_g else large_float;

          bb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s - 1.0; # Renamed from b to avoid conflict
          b1 = -0.0041960863 * ldt - 0.7034186147 * mdt + 1.7076147010 * sdt;
          b2 = -0.0041960863 * ldt2 - 0.7034186147 * mdt2 + 1.7076147010 * sdt2;
          u_b_den = b1 * b1 - 0.5 * bb * b2;
          u_b = if math.fabs u_b_den < epsilon then 0.0 else b1 / u_b_den;
          t_b = if u_b >= 0.0 then -bb * u_b else large_float;

          # Update t with the smallest positive step
          t_refined = t_triangle + math.min t_r (math.min t_g t_b);
        in t_refined;
    in t_initial;

  # Wrapper for find_gamut_intersection that calculates the cusp internally
  find_gamut_intersection = a: b: L1: C1: L0:
    let cusp = find_cusp a b;
    in find_gamut_intersection_with_cusp a b L1 C1 L0 cusp;

  # Okhsl/Okhsv Specific Helpers
  # toe function for L_r (perceptual lightness adjustment)
  toe = x:
    let
      k_1 = 0.206;
      k_2 = 0.03;
      k_3 = (1.0 + k_1) / (1.0 + k_2);
      discriminant = (k_3 * x - k_1) * (k_3 * x - k_1) + 4.0 * k_2 * k_3 * x;
    in 0.5 * (k_3 * x - k_1 + math.sqrt (math.max 0.0 discriminant)); # Ensure sqrt input >= 0

  # Inverse toe function
  toe_inv = x:
    let
      k_1 = 0.206;
      k_2 = 0.03;
      k_3 = (1.0 + k_1) / (1.0 + k_2);
    in (x * x + k_1 * x) / (k_3 * (x + k_2) + epsilon); # Add epsilon for safety

  # Convert cusp {L, C} to {S, T} representation
  to_ST = cusp: # cusp = { L, C }
    let
      L = cusp.L;
      C = cusp.C;
    in { S = C / (L + epsilon); T = C / (1.0 - L + epsilon); }; # Returns { S, T }

  # Polynomial approximation for the 'mid' cusp shape (ST_mid)
  get_ST_mid = a_: b_:
    let
      S = 0.11516993 + 1.0 / (
        7.44778970 + 4.15901240 * b_
        + a_ * (-2.19557347 + 1.75198401 * b_
          + a_ * (-2.13704948 - 10.02301043 * b_
            + a_ * (-4.24894561 + 5.38770819 * b_ + 4.69891013 * a_)
          )
        )
      );
      T = 0.11239642 + 1.0 / (
        1.61320320 - 0.68124379 * b_
        + a_ * (0.40370612 + 0.90148123 * b_
          + a_ * (-0.27087943 + 0.61223990 * b_
            + a_ * (0.00299215 - 0.45399568 * b_ - 0.14661872 * a_)
          )
        )
      );
    in { S = S; T = T; }; # Returns { S, T }

  # Calculate C_0, C_mid, C_max for Okhsl interpolation
  get_Cs = L: a_: b_:
    let
      cusp = find_cusp a_ b_;
      # C_max is gamut intersection with C=1 line at lightness L
      C_max = find_gamut_intersection_with_cusp a_ b_ L 1.0 L cusp;
      ST_max = to_ST cusp;

      # Scale factor k
      k_den = math.min (L * ST_max.S) ((1.0 - L) * ST_max.T);
      k = C_max / (k_den + epsilon);

      # Calculate C_mid using soft minimum
      ST_mid = get_ST_mid a_ b_;
      C_a_mid = L * ST_mid.S;
      C_b_mid = (1.0 - L) * ST_mid.T;
      # Using pow(..., 1/4) for 4th root
      C_mid_inv_4 = 1.0 / math.powFloat C_a_mid 4 + 1.0 / math.powFloat C_b_mid 4 + epsilon;
      C_mid = 0.9 * k * math.powFloat C_mid_inv_4 (-0.25); # Equivalent to 1/sqrt(sqrt(C_mid_inv_4))

      # Calculate C_0 using soft minimum (hue independent)
      C_a_0 = L * 0.4;
      C_b_0 = (1.0 - L) * 0.8;
      C_0_inv_2 = 1.0 / (C_a_0 * C_a_0) + 1.0 / (C_b_0 * C_b_0) + epsilon;
      C_0 = math.powFloat C_0_inv_2 (-0.5); # Equivalent to 1/sqrt(C_0_inv_2)

    in { C_0 = C_0; C_mid = C_mid; C_max = C_max; }; # Returns { C_0, C_mid, C_max }

in rec {
  inherit
    srgb_transfer_function
    srgb_transfer_function_inv
    linear_srgb_to_oklab
    oklab_to_linear_srgb
    compute_max_saturation
    find_cusp
    find_gamut_intersection
    toe
    toe_inv
    to_ST
    get_ST_mid
    get_Cs
    ;

  # Final Conversion Functions

  okhsl_to_srgb = hsl: # hsl = { h, s, l }
    if hsl.l >= 1.0 then { r = 1.0; g = 1.0; b = 1.0; }
    else if hsl.l <= 0.0 then { r = 0.0; g = 0.0; b = 0.0; }
    else let
      h = hsl.h;
      s = math.clamp hsl.s 0.0 1.0; # Clamp saturation
      l = hsl.l;

      a_ = math.cos (2.0 * math.pi * h);
      b_ = math.sin (2.0 * math.pi * h);
      L = toe_inv l;

      cs = get_Cs L a_ b_;
      C_0 = cs.C_0;
      C_mid = cs.C_mid;
      C_max = cs.C_max;

      mid = 0.8;
      mid_inv = 1.25;

      C = if s < mid then
        let
          t = mid_inv * s;
          k_1 = mid * C_0;
          k_2 = (1.0 - k_1 / (C_mid + epsilon));
        in t * k_1 / (1.0 - k_2 * t + epsilon)
      else
        let
          t = (s - mid) / (1.0 - mid);
          k_0 = C_mid;
          k_1 = (1.0 - mid) * C_mid * C_mid * mid_inv * mid_inv / (C_0 + epsilon);
          k_2 = (1.0 - k_1 / (C_max - C_mid + epsilon));
        in k_0 + t * k_1 / (1.0 - k_2 * t + epsilon);

      rgb_linear = oklab_to_linear_srgb { L = L; a = C * a_; b = C * b_; };
    in {
      r = srgb_transfer_function rgb_linear.r;
      g = srgb_transfer_function rgb_linear.g;
      b = srgb_transfer_function rgb_linear.b;
    }; # Returns { r, g, b } (non-linear sRGB)

  srgb_to_okhsl = rgb: # rgb = { r, g, b } (non-linear sRGB)
    let
      rgb_linear = {
        r = srgb_transfer_function_inv rgb.r;
        g = srgb_transfer_function_inv rgb.g;
        b = srgb_transfer_function_inv rgb.b;
      };
      lab = linear_srgb_to_oklab rgb_linear;
      L = lab.L;
      l = toe L;

      C_cand = math.sqrt (lab.a * lab.a + lab.b * lab.b);

      # Handle grey axis
      h = if C_cand < epsilon then 0.0 else
        let
          # Standard hue calculation: atan2(y, x) -> atan2(b, a)
          h_atan = math.atan2 lab.b lab.a; # Range [-pi, pi]
          h_norm = h_atan / (2.0 * math.pi); # Range [-0.5, 0.5]
        in if h_norm < 0.0 then h_norm + 1.0 else h_norm; # Range [0, 1]
      s = if C_cand < epsilon then 0.0 else
        let
          C = C_cand; # Use actual chroma now
          a_ = lab.a / C;
          b_ = lab.b / C;
          cs = get_Cs L a_ b_;
          C_0 = cs.C_0;
          C_mid = cs.C_mid;
          C_max = cs.C_max;

          mid = 0.8;
          mid_inv = 1.25;

          # Inverse interpolation (unchanged logic, just moved inside else)
          s_calc = if C < C_mid then
            let
              k_1 = mid * C_0;
              k_2 = (1.0 - k_1 / (C_mid + epsilon));
              t = C / (k_1 + k_2 * C + epsilon);
            in t * mid
          else
            let
              k_0 = C_mid;
              k_1 = (1.0 - mid) * C_mid * C_mid * mid_inv * mid_inv / (C_0 + epsilon);
              k_2 = (1.0 - k_1 / (C_max - C_mid + epsilon));
              t = (C - k_0) / (k_1 + k_2 * (C - k_0) + epsilon);
            in mid + (1.0 - mid) * t;
        in s_calc; # End of saturation calculation for non-grey colors

    in { h = h; s = math.clamp s 0.0 1.0; l = l; }; # Returns { h, s, l }
# --- Okhsl section before this point is modified ---
# --- Okhsv section starts below ---


  okhsv_to_srgb = hsv: # hsv = { h, s, v }
    let
      h = hsv.h;
      s = math.clamp hsv.s 0.0 1.0; # Clamp saturation
      v = math.clamp hsv.v 0.0 1.0; # Clamp value

      a_ = math.cos (2.0 * math.pi * h);
      b_ = math.sin (2.0 * math.pi * h);

      cusp = find_cusp a_ b_;
      ST_max = to_ST cusp;
      S_max = ST_max.S;
      T_max = ST_max.T;
      S_0 = 0.5;
      k = 1.0 - S_0 / (S_max + epsilon);

      # Calculate L_v, C_v (gamut is perfect triangle)
      den_v = S_0 + T_max - T_max * k * s + epsilon;
      L_v = 1.0 - s * S_0 / den_v;
      C_v = s * T_max * S_0 / den_v;

      # Apply value v
      L = v * L_v;
      C = v * C_v;

      # Compensate for toe and curved top
      L_vt = toe_inv L_v;
      C_vt = C_v * L_vt / (L_v + epsilon);

      L_new = toe_inv L;
      C_new = C * L_new / (L + epsilon);
      L_final = L_new;
      C_final = C_new;

      # Rescale based on cusp projection
      rgb_scale = oklab_to_linear_srgb { L = L_vt; a = a_ * C_vt; b = b_ * C_vt; };
      max_rgb_scale = math.max rgb_scale.r (math.max rgb_scale.g (math.max rgb_scale.b 0.0));
      scale_L = math.cbrt (1.0 / (max_rgb_scale + epsilon));

      L_scaled = L_final * scale_L;
      C_scaled = C_final * scale_L;

      rgb_linear = oklab_to_linear_srgb { L = L_scaled; a = C_scaled * a_; b = C_scaled * b_; };
    in {
      r = srgb_transfer_function rgb_linear.r;
      g = srgb_transfer_function rgb_linear.g;
      b = srgb_transfer_function rgb_linear.b;
    }; # Returns { r, g, b } (non-linear sRGB)

  srgb_to_okhsv = rgb: # rgb = { r, g, b } (non-linear sRGB)
    let
      rgb_linear = {
        r = srgb_transfer_function_inv rgb.r;
        g = srgb_transfer_function_inv rgb.g;
        b = srgb_transfer_function_inv rgb.b;
      };
      lab = linear_srgb_to_oklab rgb_linear;
      L_orig = lab.L;

      C_cand = math.sqrt (lab.a * lab.a + lab.b * lab.b);

      # Handle grey axis
      h = if C_cand < epsilon then 0.0 else
        let
          # Standard hue calculation: atan2(y, x) -> atan2(b, a)
          h_atan = math.atan2 lab.b lab.a; # Range [-pi, pi]
          h_norm = h_atan / (2.0 * math.pi); # Range [-0.5, 0.5]
        in if h_norm < 0.0 then h_norm + 1.0 else h_norm; # Range [0, 1]
      s = if C_cand < epsilon then 0.0 else
        let
          C_orig = C_cand; # Use actual chroma
          a_ = lab.a / C_orig;
          b_ = lab.b / C_orig;

          cusp = find_cusp a_ b_;
          ST_max = to_ST cusp;
          S_max = ST_max.S;
          T_max = ST_max.T;
          S_0 = 0.5;
          k = 1.0 - S_0 / (S_max + epsilon);

          # Find L_v, C_v
          t_den = C_orig + L_orig * T_max + epsilon;
          t = T_max / t_den;
          L_v = t * L_orig;
          C_v = t * C_orig;

          # Find L_vt, C_vt
          L_vt = toe_inv L_v;
          C_vt = C_v * L_vt / (L_v + epsilon);

          # Invert the scaling step
          rgb_scale = oklab_to_linear_srgb { L = L_vt; a = a_ * C_vt; b = b_ * C_vt; };
          max_rgb_scale = math.max rgb_scale.r (math.max rgb_scale.g (math.max rgb_scale.b 0.0));
          scale_L = math.cbrt (1.0 / (max_rgb_scale + epsilon));

          L_unscaled = L_orig / scale_L;
          C_unscaled = C_orig / scale_L;

          # Invert the toe compensation
          L_final = toe L_unscaled;
          C_final = C_unscaled * L_final / (L_unscaled + epsilon);

          # Compute final s (v is computed outside this 'else')
          s_den = (T_max * S_0) + T_max * k * C_v + epsilon;
          s_calc = (S_0 + T_max) * C_v / s_den;
        in s_calc; # End of saturation calculation for non-grey colors

      # Compute final v
      v = if C_cand < epsilon then
            # Approximate v for grey colors using perceptual lightness
            toe L_orig
          else
            # Calculate v using the derived L_final and L_v for chromatic colors
            let
              # Need L_v from the 's' calculation block above
              C_orig = C_cand;
              a_ = lab.a / C_orig;
              b_ = lab.b / C_orig;
              cusp = find_cusp a_ b_;
              ST_max = to_ST cusp;
              T_max = ST_max.T;
              t_den = C_orig + L_orig * T_max + epsilon;
              t = T_max / t_den;
              L_v = t * L_orig;
              # Need L_final from the 's' calculation block above
              S_max = ST_max.S;
              S_0 = 0.5;
              k = 1.0 - S_0 / (S_max + epsilon);
              C_v = t * C_orig;
              L_vt = toe_inv L_v;
              C_vt = C_v * L_vt / (L_v + epsilon);
              rgb_scale = oklab_to_linear_srgb { L = L_vt; a = a_ * C_vt; b = b_ * C_vt; };
              max_rgb_scale = math.max rgb_scale.r (math.max rgb_scale.g (math.max rgb_scale.b 0.0));
              scale_L = math.cbrt (1.0 / (max_rgb_scale + epsilon));
              L_unscaled = L_orig / scale_L;
              L_final = toe L_unscaled;
            in L_final / (L_v + epsilon);

    in { h = h; s = math.clamp s 0.0 1.0; v = math.clamp v 0.0 1.0; }; # Returns { h, s, v }
# --- srgb_to_okhsv section before this point is modified ---

}
      S_max = ST_max.S;
      T_max = ST_max.T;
      S_0 = 0.5;
      k = 1.0 - S_0 / (S_max + epsilon);

      # Find L_v, C_v
      t_den = C_orig + L_orig * T_max + epsilon;
      t = T_max / t_den;
      L_v = t * L_orig;
      C_v = t * C_orig;

      # Find L_vt, C_vt
      L_vt = toe_inv L_v;
      C_vt = C_v * L_vt / (L_v + epsilon);

      # Invert the scaling step
      rgb_scale = oklab_to_linear_srgb { L = L_vt; a = a_ * C_vt; b = b_ * C_vt; };
      max_rgb_scale = math.max rgb_scale.r (math.max rgb_scale.g (math.max rgb_scale.b 0.0));
      scale_L = math.cbrt (1.0 / (max_rgb_scale + epsilon));

      L_unscaled = L_orig / scale_L;
      C_unscaled = C_orig / scale_L;

      # Invert the toe compensation
      L_final = toe L_unscaled;
      C_final = C_unscaled * L_final / (L_unscaled + epsilon);

      # Compute final v and s
      v = L_final / (L_v + epsilon);
      s_den = (T_max * S_0) + T_max * k * C_v + epsilon;
      s = (S_0 + T_max) * C_v / s_den;

    in { h = h; s = math.clamp s 0.0 1.0; v = math.clamp v 0.0 1.0; }; # Returns { h, s, v }

}
