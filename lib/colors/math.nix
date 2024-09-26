let

  functions = rec {
    abs = x: if x < 0 then (-1) * x else x;

    remainder = n: d: n - d * (n / d);

    pow = n: e:
      let
        result =
          if e == 0 then 1
          else if e == 1 then n
          else n * (pow n (e - 1));
      in
      assert e >= 0;
      assert e > 0 -> (abs result) >= (abs n);
      result;

    sin = x:
      let
        x1 = x;
        x3 = x * x * x;
        x5 = x3 * x * x;
        x7 = x5 * x * x;
        x9 = x7 * x * x;
        x11 = x9 * x * x;
      in
        x1
        - x3 / 6.0
        + x5 / 120.0
        - x7 / 5040.0
        + x9 / 362880.0
        - x11 / 39916800.0;

    # Approximate cosine using Taylor series up to x^10 term
    cos = x:
      let
        x2 = x * x;
        x4 = x2 * x2;
        x6 = x4 * x2;
        x8 = x6 * x2;
        x10 = x8 * x2;
      in
        1.0
        - x2 / 2.0
        + x4 / 24.0
        - x6 / 720.0
        + x8 / 40320.0
        - x10 / 3628800.0;

    sqrt = x:
    let
      epsilon = 0.0000000001;  # 1e-10 written out explicitly
      guess0 = if x < 1.0 then 1.0 else x / 2.0;

      sqrtIter = guess: iter:
        let
          nextGuess = (guess + x / guess) / 2.0;
          delta = abs (nextGuess - guess);
        in
          if delta < epsilon || iter >= 100 then nextGuess
          else sqrtIter nextGuess (iter + 1);
    in
      if x < 0 then throw "Cannot compute square root of a negative number"
      else if x == 0 then 0.0
      else sqrtIter guess0 0;
  };
  in functions



