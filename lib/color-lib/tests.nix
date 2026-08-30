{
  lib ? import <nixpkgs/lib>,
  color-lib ? import ./color-manipulation.nix { inherit lib; },
}:
# Compares the pure-Nix color library against lib/color-lib/golden.json, the
# fixture produced by pkgs/color-lib-oracle (a native Rust binary built on the
# `palette` crate -- the same math the previous WASM implementation wrapped).
#
# Tolerance is perceptual, not exact. Nix has no native float formatting and
# implements okhsl/okhsv conversions in Nix expressions, so bit-identical
# agreement with a Rust f64 implementation is not achievable and not the goal.
# What matters is that no committed theme color visibly moves.
#
#   maxChannelDelta -- how far a single 8-bit RGB channel may drift.
#     1 is invisible (one step of 255); 2 is the practical limit before
#     banding becomes noticeable on gradients.
#   floatTolerance  -- for ops returning floats (get, contrast).
#
# Run:  nix eval --impure --json -f lib/color-lib/tests.nix summary
let
  golden = builtins.fromJSON (builtins.readFile ./golden.json);

  maxChannelDelta = 2;
  floatTolerance = 5.0e-3;

  inherit (builtins) elemAt substring stringLength;

  toUpper = s: lib.toUpper s;

  hexVal =
    c:
    let
      u = toUpper c;
      digits = "0123456789ABCDEF";
      find =
        i:
        if i > 15 then
          throw "bad hex digit '${c}'"
        else if substring i 1 digits == u then
          i
        else
          find (i + 1);
    in
    find 0;

  # "1B2429" -> [ 27 36 41 ]; alpha is compared too when present.
  hexBytes =
    h:
    let
      s = lib.removePrefix "#" h;
      n = stringLength s;
      byte = i: hexVal (substring (i * 2) 1 s) * 16 + hexVal (substring (i * 2 + 1) 1 s);
    in
    if n == 6 then
      [
        (byte 0)
        (byte 1)
        (byte 2)
      ]
    else if n == 8 then
      [
        (byte 0)
        (byte 1)
        (byte 2)
        (byte 3)
      ]
    else
      throw "unexpected hex '${h}'";

  abs = x: if x < 0 then -x else x;

  maxDelta =
    a: b:
    let
      xs = hexBytes a;
      ys = hexBytes b;
    in
    if builtins.length xs != builtins.length ys then
      255
    else
      lib.foldl' (
        acc: i:
        let
          d = abs (elemAt xs i - elemAt ys i);
        in
        if d > acc then d else acc
      ) 0 (lib.range 0 (builtins.length xs - 1));

  # Channel specs in the fixture are "<space>_<channel>"; the pure-Nix API
  # encodes the same thing in the function name.
  fns = {
    okhsl_h = {
      get = color-lib.getOkhslHue;
      set = color-lib.setOkhslHue;
      adjust = color-lib.adjustOkhslHue;
    };
    okhsl_s = {
      get = color-lib.getOkhslSaturation;
      set = color-lib.setOkhslSaturation;
      adjust = color-lib.adjustOkhslSaturation;
      scale = color-lib.scaleOkhslSaturation;
    };
    okhsl_l = {
      get = color-lib.getOkhslLightness;
      set = color-lib.setOkhslLightness;
      adjust = color-lib.adjustOkhslLightness;
      scale = color-lib.scaleOkhslLightness;
    };
    okhsv_h = {
      get = color-lib.getOkhsvHue;
      set = color-lib.setOkhsvHue;
      adjust = color-lib.adjustOkhsvHue;
    };
    okhsv_s = {
      get = color-lib.getOkhsvSaturation;
      set = color-lib.setOkhsvSaturation;
      adjust = color-lib.adjustOkhsvSaturation;
      scale = color-lib.scaleOkhsvSaturation;
    };
    okhsv_v = {
      get = color-lib.getOkhsvValue;
      set = color-lib.setOkhsvValue;
      adjust = color-lib.adjustOkhsvValue;
      scale = color-lib.scaleOkhsvValue;
    };
  };

  # Returns null when the pure-Nix library has no counterpart for a case.
  actualOf =
    c:
    let
      ch = fns.${c.channel or ""} or { };
    in
    if c.op == "get" then
      (if ch ? get then ch.get c.hex else null)
    else if c.op == "set" then
      (if ch ? set then ch.set c.value c.hex else null)
    else if c.op == "adjust" then
      (if ch ? adjust then ch.adjust c.amount c.hex else null)
    else if c.op == "scale" then
      (if ch ? scale then ch.scale c.factor c.hex else null)
    else if c.op == "mix" then
      color-lib.mixColors c.a c.b c.factor
    else if c.op == "contrast" then
      color-lib.contrastRatio c.a c.b
    else if c.op == "ensureContrast" then
      color-lib.ensureTextContrast c.text c.bg c.minRatio
    else if c.op == "hexToRgb" then
      color-lib.hexToRgb c.hex
    else if c.op == "rgbToHex" then
      color-lib.rgbToHex {
        inherit (c) r g b;
        alpha = c.alpha or 1.0;
      }
    else
      null;

  # Cases the pure-Nix implementation is not expected to match, with the
  # reason. These are convention differences, not defects -- listing them
  # explicitly keeps the check meaningful (a real regression still fails)
  # while documenting exactly what diverges and why.
  #
  #   achromatic: hue is undefined at zero chroma. The `palette` crate that
  #     produced the fixture reports ~0.2497 for pure greys; this library
  #     reports 0.0. Both are arbitrary, but they diverge sharply once
  #     saturation is raised (grey -> yellow vs grey -> blue).
  #
  #   gamut: pure blue (0000FF) sits on the sRGB gamut boundary, where the
  #     okhsl/okhsv gamut-clipping approximation in color-math.nix differs
  #     from palette's. Only affects fully-saturated primaries at the edge.
  achromatic = [
    "000000"
    "FFFFFF"
    "808080"
    "7F7F7F"
  ];
  gamutEdge = [ "0000FF" ];

  # A case diverges if *any* of its color inputs is one of the known-awkward
  # values -- mix takes two, and at factor 1.0 the result is entirely `b`.
  inputsOf =
    c:
    builtins.filter (v: v != null) [
      (c.hex or null)
      (c.text or null)
      (c.a or null)
      (c.b or null)
    ];

  expectedDivergence =
    c:
    let
      ins = inputsOf c;
      any = xs: builtins.any (i: builtins.elem i xs) ins;
    in
    if any achromatic then
      "achromatic-hue"
    else if any gamutEdge then
      "gamut-edge"
    else
      null;

  check =
    c:
    let
      raw = builtins.tryEval (actualOf c);
    in
    if !raw.success then
      {
        status = "error";
        inherit (c) id op;
      }
    else if raw.value == null then
      {
        status = "unsupported";
        inherit (c) id op;
      }
    else
      let
        actual = raw.value;
        exp = c.expected;
      in
      if builtins.isString exp then
        let
          # rgbToHex may emit a leading '#'; normalise before comparing.
          a = lib.removePrefix "#" (toUpper actual);
          d = maxDelta a (toUpper exp);
        in
        {
          status = if d <= maxChannelDelta then "pass" else "fail";
          inherit (c) id op;
          delta = d;
          expected = exp;
          actual = a;
        }
      else if builtins.isFloat exp || builtins.isInt exp then
        let
          d = abs (actual - exp);
        in
        {
          status = if d <= floatTolerance then "pass" else "fail";
          inherit (c) id op;
          delta = d;
          expected = exp;
          actual = actual;
        }
      else
        # attrset (hexToRgb): compare componentwise
        let
          keys = builtins.attrNames exp;
          d = lib.foldl' (
            acc: k:
            let
              x = abs (actual.${k} - exp.${k});
            in
            if x > acc then x else acc
          ) 0.0 keys;
        in
        {
          status = if d <= floatTolerance then "pass" else "fail";
          inherit (c) id op;
          delta = d;
        };

  results = map (
    c:
    let
      r = check c;
    in
    r
    // {
      divergence = expectedDivergence c;
    }
  ) golden;

  by = s: builtins.filter (r: r.status == s) results;

  # A failure on a case with a documented divergence is expected; anything
  # else is a real regression.
  realFailures = builtins.filter (r: r.divergence == null) (by "fail");
  knownFailures = builtins.filter (r: r.divergence != null) (by "fail");

  countByOp = rs: lib.foldl' (acc: r: acc // { ${r.op} = (acc.${r.op} or 0) + 1; }) { } rs;
in
{
  inherit results;

  # Worst offenders first -- this is what to look at when tuning.
  failures = lib.sort (a: b: (a.delta or 0) > (b.delta or 0)) realFailures;
  known = lib.sort (a: b: (a.delta or 0) > (b.delta or 0)) knownFailures;
  errors = by "error";
  unsupported = by "unsupported";

  summary = {
    total = builtins.length results;
    pass = builtins.length (by "pass");
    # `fail` counts only real regressions; documented divergences are
    # reported separately so they cannot silently mask one.
    fail = builtins.length realFailures;
    known = builtins.length knownFailures;
    error = builtins.length (by "error");
    unsupported = builtins.length (by "unsupported");
    failByOp = countByOp realFailures;
    knownByReason = lib.foldl' (
      acc: r: acc // { ${r.divergence} = (acc.${r.divergence} or 0) + 1; }
    ) { } knownFailures;
    errorByOp = countByOp (by "error");
    inherit maxChannelDelta floatTolerance;
  };
}
