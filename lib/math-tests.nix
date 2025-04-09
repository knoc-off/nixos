# Comprehensive tests for math.nix and equations.nix
{ lib ? import <nixpkgs/lib> }:

let
  math = import ./math.nix { inherit lib; };
  equations = import ./equations.nix { inherit lib math; };

  # Helper to check if two floats are close enough
  assertWithinTolerance = name: expected: actual: tolerance:
    assert lib.assertMsg (math.abs (expected - actual) < tolerance)
      "${name}: Expected ${toString expected}, got ${toString actual} (tolerance ${toString tolerance})";
    true;

  # Define a standard tolerance for float comparisons
  epsilon = math.epsilon; # Use the epsilon defined in math.nix

  # Define all the test sets in a separate attribute set
  testSets = rec {
    # --- Tests for math.nix ---

    testConstants = {
      # Test pi
      testPi = assertWithinTolerance "pi" 3.141592653589793 math.pi epsilon;
      # Test tau
      testTau = assertWithinTolerance "tau" (2 * 3.141592653589793) math.tau epsilon;
      # Test epsilon
      testEpsilon = assertWithinTolerance "epsilon" (math.pow 0.1 10) math.epsilon (math.pow 0.1 15); # Test epsilon with smaller tolerance
    };

    testCoreFunctions = {
      # Test safeDiv
      testSafeDivNormal = assertWithinTolerance "safeDiv (normal)" 2.0 (math.safeDiv 6.0 3.0) epsilon;
      testSafeDivByZero = assert (math.safeDiv 5.0 0.0 == 0); true;
    };

    testBasicArithmeticHelpers = {
      # Test floor
      testFloorPositive = assert (math.floor 3.7 == 3); true;
      testFloorNegative = assert (math.floor (-2.3) == -3); true;
      # Test ceil
      testCeilPositive = assert (math.ceil 3.2 == 4); true;
      testCeilNegative = assert (math.ceil (-2.8) == -2); true;
    };

    testMinMax = {
      # Test min
      testMinInt = assert (math.min 5 3 == 3); true;
      testMinFloat = assert (math.min 5.5 3.2 == 3.2); true;
      testMinMixed = assert (math.min 5 3.2 == 3.2); true;
      # Test max
      testMaxInt = assert (math.max 5 3 == 5); true;
      testMaxFloat = assert (math.max 5.5 3.2 == 5.5); true;
      testMaxMixed = assert (math.max 5.0 8 == 8); true;
    };

    testClamp = {
      # Test clamp
      testClampInside = assert (math.clamp 5 0 10 == 5); true;
      testClampBelow = assert (math.clamp (-2) 0 10 == 0); true;
      testClampAbove = assert (math.clamp 15 0 10 == 10); true;
      testClampFloat = assertWithinTolerance "clamp (float)" 5.5 (math.clamp 5.5 0.0 10.0) epsilon;
      testClampMinMaxSwapped = assert (math.clamp 5 10 0 == 5); true; # Handles swapped min/max
    };

    testLerp = {
      # Test lerp
      testLerpStart = assertWithinTolerance "lerp (start)" 10.0 (math.lerp 10.0 20.0 0.0) epsilon;
      testLerpEnd = assertWithinTolerance "lerp (end)" 20.0 (math.lerp 10.0 20.0 1.0) epsilon;
      testLerpMid = assertWithinTolerance "lerp (mid)" 15.0 (math.lerp 10.0 20.0 0.5) epsilon;
    };

    testBasicArithmeticOps = {
      # Test sum
      testSum = assert (math.sum [ 1 2 3 4 ] == 10); true;
      testSumFloat = assertWithinTolerance "sum (float)" 10.5 (math.sum [ 1.0 2.5 3.0 4.0 ]) epsilon;
      # Test multiply
      testMultiply = assert (math.multiply [ 2 3 4 ] == 24); true;
      testMultiplyFloat = assertWithinTolerance "multiply (float)" 25.0 (math.multiply [ 2.0 2.5 5.0 ]) epsilon;
    };

    testAbs = {
      # Test abs (int)
      testAbsPositiveInt = assert (math.abs 5 == 5); true;
      testAbsNegativeInt = assert (math.abs (-5) == 5); true;
      testAbsZeroInt = assert (math.abs 0 == 0); true;
      # Test fabs (float)
      testFabsPositive = assertWithinTolerance "fabs (positive)" 5.5 (math.fabs 5.5) epsilon;
      testFabsNegative = assertWithinTolerance "fabs (negative)" 5.5 (math.fabs (-5.5)) epsilon;
      testFabsZero = assertWithinTolerance "fabs (zero)" 0.0 (math.fabs 0.0) epsilon;
    };

    testCbrt = {
      # Test cbrt
      testCbrtPositive = assertWithinTolerance "cbrt (positive)" 3.0 (math.cbrt 27.0) epsilon;
      testCbrtNegative = assertWithinTolerance "cbrt (negative)" (-3.0) (math.cbrt (-27.0)) epsilon;
      testCbrtZero = assertWithinTolerance "cbrt (zero)" 0.0 (math.cbrt 0.0) epsilon;
      testCbrtFraction = assertWithinTolerance "cbrt (fraction)" 0.5 (math.cbrt 0.125) epsilon;
    };

    testArange = {
      # Test arange (exclusive end)
      testArange1 = assert (math.arange 0 5 1 == [ 0 1 2 3 4 ]); true;
      testArange2 = assert (math.arange 1.0 3.0 0.5 == [ 1.0 1.5 2.0 2.5 ]); true;
      # Test arange2 (inclusive end)
      testArange2_1 = assert (math.arange2 0 5 1 == [ 0 1 2 3 4 5 ]); true;
      testArange2_2 = assert (math.arange2 1.0 3.0 0.5 == [ 1.0 1.5 2.0 2.5 3.0 ]); true;
      testArange2_3 = assert (math.arange2 1 5 2 == [ 1 3 5 ]); true;
    };

    testPolynomial = {
      # Test polynomial: 3x^2 + 2x + 1 at x=2 => 3*4 + 2*2 + 1 = 12 + 4 + 1 = 17
      testPoly = assert (math.polynomial 2 [ 1 2 3 ] == 17); true;
      # Test polynomial: 0.5x + 4 at x=3 => 0.5*3 + 4 = 1.5 + 4 = 5.5
      testPolyFloat = assertWithinTolerance "polynomial (float)" 5.5 (math.polynomial 3.0 [ 4.0 0.5 ]) epsilon;
    };

    testParseFloat = {
      # Test parseFloat
      testParseFloatInt = assertWithinTolerance "parseFloat (int)" 123.0 (math.parseFloat "123") epsilon;
      testParseFloatDecimal = assertWithinTolerance "parseFloat (decimal)" 123.45 (math.parseFloat "123.45") epsilon;
      testParseFloatLeadingZero = assertWithinTolerance "parseFloat (leading zero)" 0.5 (math.parseFloat "0.5") epsilon;
    };

    testHasFraction = {
      # Test hasFraction
      testHasFractionTrue = assert (math.hasFraction 12.34 == true); true;
      testHasFractionFalseInt = assert (math.hasFraction 12 == false); true;
      testHasFractionFalseFloat = assert (math.hasFraction 12.0 == false); true;
      testHasFractionTrailingZeros = assert (math.hasFraction 12.300 == true); true; # Checks for non-zero fractional digits
    };

    testDivMod = {
      # Test div (integer division)
      testDivPositive = assert (math.div 7 3 == 2); true;
      testDivNegativeNum = assert (math.div (-7) 3 == -3); true; # Floor behavior
      testDivNegativeDen = assert (math.div 7 (-3) == -3); true; # Floor behavior
      testDivBothNegative = assert (math.div (-7) (-3) == 2); true;
      testDivExact = assert (math.div 6 3 == 2); true;
      # Test mod
      testModPositive = assert (math.mod 7 3 == 1); true;
      testModNegativeNum = assert (math.mod (-7) 3 == 2); true; # Result has same sign as divisor
      testModNegativeDen = assert (math.mod 7 (-3) == -2); true; # Result has same sign as divisor
      testModBothNegative = assert (math.mod (-7) (-3) == -1); true;
      testModZero = assert (math.mod 6 3 == 0); true;
      # Test fmod (float modulo) - Result has the same sign as the dividend (x)
      testFmodPositive = assertWithinTolerance "fmod (positive)" 1.0 (math.fmod 7.0 3.0) epsilon; # 7.0 - 3.0 * floor(7.0/3.0) = 7.0 - 3.0 * 2.0 = 1.0
      testFmodNegativeNum = assertWithinTolerance "fmod (negative num)" 2.0 (math.fmod (-7.0) 3.0) epsilon; # -7.0 - 3.0 * floor(-7.0/3.0) = -7.0 - 3.0 * (-3.0) = -7.0 + 9.0 = 2.0
      testFmodNegativeDen = assertWithinTolerance "fmod (negative den)" (-2.0) (math.fmod 7.0 (-3.0)) epsilon; # 7.0 - (-3.0) * floor(7.0/-3.0) = 7.0 - (-3.0) * (-3.0) = 7.0 - 9.0 = -2.0
      testFmodBothNegative = assertWithinTolerance "fmod (both negative)" (-1.0) (math.fmod (-7.0) (-3.0)) epsilon; # -7.0 - (-3.0) * floor(-7.0/-3.0) = -7.0 - (-3.0) * 2.0 = -7.0 + 6.0 = -1.0
    };

    testLogExp = {
      # Test ln
      testLnE = assertWithinTolerance "ln(e)" 1.0 (math.ln 2.718281828459045) epsilon;
      testLn1 = assertWithinTolerance "ln(1)" 0.0 (math.ln 1.0) epsilon;
      testLn2 = assertWithinTolerance "ln(2)" 0.6931471805599453 (math.ln 2.0) epsilon;
      # Test exp
      testExp0 = assertWithinTolerance "exp(0)" 1.0 (math.exp 0.0) epsilon;
      testExp1 = assertWithinTolerance "exp(1)" 2.718281828459045 (math.exp 1.0) epsilon;
      testExpLn2 = assertWithinTolerance "exp(ln(2))" 2.0 (math.exp (math.ln 2.0)) epsilon;
      testExpNegative = assertWithinTolerance "exp(-1)" (1.0 / 2.718281828459045) (math.exp (-1.0)) epsilon;
    };

    testPow = {
      # Test pow (integer exponent)
      testPowIntPositive = assert (math.pow 2 3 == 8); true;
      testPowIntZero = assert (math.pow 5 0 == 1); true;
      testPowIntNegativeBase = assert (math.pow (-2) 3 == -8); true;
      testPowIntNegativeBaseEven = assert (math.pow (-2) 4 == 16); true;
      # Test powFloat
      testPowFloat = assertWithinTolerance "powFloat" 8.0 (math.powFloat 2.0 3.0) epsilon;
      testPowFloatFractional = assertWithinTolerance "powFloat (fractional)" (math.sqrt 2.0) (math.powFloat 2.0 0.5) epsilon;
      testPowFloatNegativeExp = assertWithinTolerance "powFloat (negative exp)" 0.25 (math.powFloat 2.0 (-2.0)) epsilon;
    };

    testFactorial = {
      # Test factorial
      testFactorial0 = assert (math.factorial 0 == 1); true;
      testFactorial1 = assert (math.factorial 1 == 1); true;
      testFactorial5 = assert (math.factorial 5 == 120); true;
    };

    testTrigonometric = {
      # Test sin (radians)
      testSin0 = assertWithinTolerance "sin(0)" 0.0 (math.sin 0.0) epsilon;
      testSinPiOver2 = assertWithinTolerance "sin(pi/2)" 1.0 (math.sin (math.pi / 2.0)) epsilon;
      testSinPi = assertWithinTolerance "sin(pi)" 0.0 (math.sin math.pi) epsilon;
      testSin3PiOver2 = assertWithinTolerance "sin(3pi/2)" (-1.0) (math.sin (3.0 * math.pi / 2.0)) epsilon;
      testSin2Pi = assertWithinTolerance "sin(2pi)" 0.0 (math.sin math.tau) epsilon;
      # Test cos (radians)
      testCos0 = assertWithinTolerance "cos(0)" 1.0 (math.cos 0.0) epsilon;
      testCosPiOver2 = assertWithinTolerance "cos(pi/2)" 0.0 (math.cos (math.pi / 2.0)) epsilon;
      testCosPi = assertWithinTolerance "cos(pi)" (-1.0) (math.cos math.pi) epsilon;
      # Test tan (radians)
      testTan0 = assertWithinTolerance "tan(0)" 0.0 (math.tan 0.0) epsilon;
      testTanPiOver4 = assertWithinTolerance "tan(pi/4)" 1.0 (math.tan (math.pi / 4.0)) epsilon;
      # Test sind (degrees)
      testSind0 = assertWithinTolerance "sind(0)" 0.0 (math.sind 0.0) epsilon;
      testSind90 = assertWithinTolerance "sind(90)" 1.0 (math.sind 90.0) epsilon;
      # Test cosd (degrees)
      testCosd0 = assertWithinTolerance "cosd(0)" 1.0 (math.cosd 0.0) epsilon;
      testCosd90 = assertWithinTolerance "cosd(90)" 0.0 (math.cosd 90.0) epsilon;
      # Test tand (degrees)
      testTand0 = assertWithinTolerance "tand(0)" 0.0 (math.tand 0.0) epsilon;
      testTand45 = assertWithinTolerance "tand(45)" 1.0 (math.tand 45.0) epsilon;
    };

    testInverseTrigonometric = {
      # Test atan (radians)
      testAtan0 = assertWithinTolerance "atan(0)" 0.0 (math.atan 0.0) epsilon;
      testAtan1 = assertWithinTolerance "atan(1)" (math.pi / 4.0) (math.atan 1.0) epsilon;
      testAtanNegative1 = assertWithinTolerance "atan(-1)" (-(math.pi / 4.0)) (math.atan (-1.0)) epsilon;
      # Test atan2 (radians)
      testAtan2_1_0 = assertWithinTolerance "atan2(0, 1)" 0.0 (math.atan2 0.0 1.0) epsilon; # x>0, y=0
      testAtan2_1_1 = assertWithinTolerance "atan2(1, 1)" (math.pi / 4.0) (math.atan2 1.0 1.0) epsilon; # x>0, y>0
      testAtan2_0_1 = assertWithinTolerance "atan2(1, 0)" (math.pi / 2.0) (math.atan2 1.0 0.0) epsilon; # x=0, y>0
      testAtan2_neg1_1 = assertWithinTolerance "atan2(1, -1)" (3.0 * math.pi / 4.0) (math.atan2 1.0 (-1.0)) epsilon; # x<0, y>0
      testAtan2_neg1_0 = assertWithinTolerance "atan2(0, -1)" math.pi (math.atan2 0.0 (-1.0)) epsilon; # x<0, y=0
      testAtan2_neg1_neg1 = assertWithinTolerance "atan2(-1, -1)" (-(3.0 * math.pi / 4.0)) (math.atan2 (-1.0) (-1.0)) epsilon; # x<0, y<0
      testAtan2_0_neg1 = assertWithinTolerance "atan2(-1, 0)" (-(math.pi / 2.0)) (math.atan2 (-1.0) 0.0) epsilon; # x=0, y<0
      testAtan2_1_neg1 = assertWithinTolerance "atan2(-1, 1)" (-(math.pi / 4.0)) (math.atan2 (-1.0) 1.0) epsilon; # x>0, y<0
      testAtan2_0_0 = assertWithinTolerance "atan2(0, 0)" 0.0 (math.atan2 0.0 0.0) epsilon; # Origin
      # Test atand (degrees)
      testAtand0 = assertWithinTolerance "atand(0)" 0.0 (math.atand 0.0) epsilon;
      testAtand1 = assertWithinTolerance "atand(1)" 45.0 (math.atand 1.0) epsilon;
      # Test atan2d (degrees)
      testAtan2d_1_1 = assertWithinTolerance "atan2d(1, 1)" 45.0 (math.atan2d 1.0 1.0) epsilon;
      testAtan2d_1_neg1 = assertWithinTolerance "atan2d(1, -1)" 135.0 (math.atan2d 1.0 (-1.0)) epsilon;
    };

    testConversions = {
      # Test rad2deg
      testRad2DegPi = assertWithinTolerance "rad2deg(pi)" 180.0 (math.rad2deg math.pi) epsilon;
      # Test deg2rad
      testDeg2Rad180 = assertWithinTolerance "deg2rad(180)" math.pi (math.deg2rad 180.0) epsilon;
    };

    testSqrt = {
      # Test sqrt
      testSqrt4 = assertWithinTolerance "sqrt(4)" 2.0 (math.sqrt 4.0) epsilon;
      testSqrt2 = assertWithinTolerance "sqrt(2)" 1.41421356237 (math.sqrt 2.0) epsilon;
      testSqrt0 = assertWithinTolerance "sqrt(0)" 0.0 (math.sqrt 0.0) epsilon;
    };

    testHaversine = {
      # Test haversine (Paris to New York ~5837km)
      testHaversineParisNYC = assertWithinTolerance "haversine (Paris-NYC)" 5837000.0 (math.haversine 48.8566 2.3522 40.7128 (-74.0060)) 5000.0; # Tolerance 5km
      # Test haversine (Same point)
      testHaversineSamePoint = assertWithinTolerance "haversine (same point)" 0.0 (math.haversine 50.0 5.0 50.0 5.0) epsilon;
    };

    testHexToDec = {
      # Test hexToDec
      testHexToDec0 = assert (math.hexToDec "0" == 0); true;
      testHexToDecF = assert (math.hexToDec "F" == 15); true;
      testHexToDec10 = assert (math.hexToDec "10" == 16); true;
      testHexToDecFF = assert (math.hexToDec "FF" == 255); true;
      testHexToDecABC = assert (math.hexToDec "ABC" == 2748); true;
      testHexToDecLower = assert (math.hexToDec "ff" == 255); true;
    };

    testGenRandomFromString = {
      # Test genRandomFromString (output should be deterministic and within range)
      testRandom1 = let r = math.genRandomFromString "seed1" 10 20; in assert (r >= 10 && r <= 20); true;
      testRandom2 = let r = math.genRandomFromString "seed2" 0.0 1.0; in assert (r >= 0.0 && r <= 1.0); true;
      testRandomDeterministic = assert (math.genRandomFromString "same_seed" 0 100 == math.genRandomFromString "same_seed" 0 100); true;
    };

    testStatistics = {
      # Test average
      testAverage = assertWithinTolerance "average" 3.0 (math.average [ 1 2 3 4 5 ]) epsilon;
      testAverageFloat = assertWithinTolerance "average (float)" 3.5 (math.average [ 1.5 2.5 3.5 4.5 5.5 ]) epsilon;
      # Test standardDeviation
      testStdDev = assertWithinTolerance "standardDeviation" (math.sqrt 2.0) (math.standardDeviation [ 1 2 3 4 5 ]) epsilon;
      # Test median
      testMedianOdd = assert (math.median [ 1 3 2 5 4 ] == 3); true;
      testMedianEven = assertWithinTolerance "median (even)" 3.5 (math.median [ 1 3 2 5 4 6 ]) epsilon;
      testMedianFloat = assertWithinTolerance "median (float)" 3.3 (math.median [ 1.1 3.3 2.2 5.5 4.4 ]) epsilon;
    };

    testComputeSTmax = {
      # Test computeSTmax
      testSTmaxL0 =
        let r = math.computeSTmax 0.0;
        in assert assertWithinTolerance "S_max (L=0)" 0.0 r.S epsilon;
           assert assertWithinTolerance "T_max (L=0)" 1.0 r.T epsilon;
           true;
      testSTmaxL0_5 =
        let r = math.computeSTmax 0.5;
        in assert assertWithinTolerance "S_max (L=0.5)" 0.5 r.S epsilon;
           assert assertWithinTolerance "T_max (L=0.5)" 0.5 r.T epsilon;
           true;
      testSTmaxL1 =
        let r = math.computeSTmax 1.0;
        in assert assertWithinTolerance "S_max (L=1)" 1.0 r.S (epsilon * 10);
           assert assertWithinTolerance "T_max (L=1)" 0.0 r.T (epsilon * 10);
           true;
    };

    # --- Tests for equations.nix ---

    testCoordinateSystems = {
      # Test cartesianToPolar
      testCartToPolar1 =
        let p = equations.cartesianToPolar 1.0 1.0;
        in assert assertWithinTolerance "cartToPolar.r (1,1)" (math.sqrt 2.0) p.r epsilon;
           assert assertWithinTolerance "cartToPolar.theta (1,1)" (math.pi / 4.0) p.theta epsilon;
           true;
      testCartToPolar2 =
        let p = equations.cartesianToPolar (-1.0) 0.0;
        in assert assertWithinTolerance "cartToPolar.r (-1,0)" 1.0 p.r epsilon;
           assert assertWithinTolerance "cartToPolar.theta (-1,0)" math.pi p.theta epsilon;
           true;
      # Test polarToCartesian
      testPolarToCart1 =
        let c = equations.polarToCartesian (math.sqrt 2.0) (math.pi / 4.0);
        in assert assertWithinTolerance "polarToCart.x (sqrt2, pi/4)" 1.0 c.x epsilon;
           assert assertWithinTolerance "polarToCart.y (sqrt2, pi/4)" 1.0 c.y epsilon;
           true;
      testPolarToCart2 =
        let c = equations.polarToCartesian 1.0 math.pi;
        in assert assertWithinTolerance "polarToCart.x (1, pi)" (-1.0) c.x epsilon;
           assert assertWithinTolerance "polarToCart.y (1, pi)" 0.0 c.y epsilon;
           true;
    };

    testAlgebraic = {
      # Test solveQuadratic (x^2 - 1 = 0 => a=1, b=0, c=-1 => roots 1, -1)
      testSolveQuadratic1 =
        let roots = equations.solveQuadratic 1.0 0.0 (-1.0);
        in assert (lib.lists.elem 1.0 roots);
           assert (lib.lists.elem (-1.0) roots);
           assert (builtins.length roots == 2);
           true;
      # Test solveQuadratic (x^2 - 4x + 4 = 0 => a=1, b=-4, c=4 => (x-2)^2=0 => root 2)
      testSolveQuadratic2 =
        let roots = equations.solveQuadratic 1.0 (-4.0) 4.0;
        in assert assertWithinTolerance "solveQuadratic (one root)" 2.0 (builtins.head roots) epsilon;
           assert (builtins.length roots == 2);
           true;
      # Test solveQuadratic (x^2 + 1 = 0 => no real roots)
      testSolveQuadratic3 = assert (equations.solveQuadratic 1.0 0.0 1.0 == []); true;
    };

    testGeometry = {
      # Test euclideanDistance2D
      testDist2D = assertWithinTolerance "euclideanDistance2D" 5.0 (equations.euclideanDistance2D 0.0 0.0 3.0 4.0) epsilon;
      # Test euclideanDistance3D
      testDist3D = assertWithinTolerance "euclideanDistance3D" (math.sqrt 17.0) (equations.euclideanDistance3D 1.0 2.0 3.0 3.0 4.0 6.0) epsilon; # sqrt(2^2 + 2^2 + 3^2) = sqrt(4+4+9) = sqrt(17)
      # Test circleArea
      testCircleArea = assertWithinTolerance "circleArea" math.pi (equations.circleArea 1.0) epsilon;
      # Test sphereVolume
      testSphereVolume = assertWithinTolerance "sphereVolume" (4.0 / 3.0 * math.pi) (equations.sphereVolume 1.0) epsilon;
      # Test triangleArea
      testTriangleArea = assertWithinTolerance "triangleArea" 6.0 (equations.triangleArea 3.0 4.0) epsilon;
      # Test rectangleArea
      testRectangleArea = assertWithinTolerance "rectangleArea" 12.0 (equations.rectangleArea 3.0 4.0) epsilon;
      # Test trapezoidArea
      testTrapezoidArea = assertWithinTolerance "trapezoidArea" 10.0 (equations.trapezoidArea 3.0 7.0 2.0) epsilon; # 0.5 * (3+7) * 2
      # Test cylinderVolume
      testCylinderVolume = assertWithinTolerance "cylinderVolume" (math.pi * 4.0 * 5.0) (equations.cylinderVolume 2.0 5.0) epsilon;
      # Test coneVolume
      testConeVolume = assertWithinTolerance "coneVolume" (1.0 / 3.0 * math.pi * 9.0 * 4.0) (equations.coneVolume 3.0 4.0) epsilon;
    };

    testInterpolation = {
      # Test inverseLerp
      testInverseLerpMid = assertWithinTolerance "inverseLerp (mid)" 0.5 (equations.inverseLerp 10.0 20.0 15.0) epsilon;
      testInverseLerpStart = assertWithinTolerance "inverseLerp (start)" 0.0 (equations.inverseLerp 10.0 20.0 10.0) epsilon;
      testInverseLerpEnd = assertWithinTolerance "inverseLerp (end)" 1.0 (equations.inverseLerp 10.0 20.0 20.0) epsilon;
      # Test remap
      testRemap = assertWithinTolerance "remap" 75.0 (equations.remap 0.0 100.0 50.0 100.0 50.0) epsilon; # Map 50 from [0,100] to [50,100] -> 75
      # Test smoothstep
      testSmoothstepStart = assertWithinTolerance "smoothstep (start)" 0.0 (equations.smoothstep 0.0 1.0 0.0) epsilon;
      testSmoothstepEnd = assertWithinTolerance "smoothstep (end)" 1.0 (equations.smoothstep 0.0 1.0 1.0) epsilon;
      testSmoothstepMid = assertWithinTolerance "smoothstep (mid)" 0.5 (equations.smoothstep 0.0 1.0 0.5) epsilon; # 0.5*0.5*(3-2*0.5) = 0.25 * (3-1) = 0.5
      testSmoothstepOutside = assertWithinTolerance "smoothstep (outside low)" 0.0 (equations.smoothstep 10.0 20.0 5.0) epsilon;
      testSmoothstepOutsideHigh = assertWithinTolerance "smoothstep (outside high)" 1.0 (equations.smoothstep 10.0 20.0 25.0) epsilon;
    };

    testPhysics = {
      # Test kineticEnergy
      testKineticEnergy = assertWithinTolerance "kineticEnergy" 25.0 (equations.kineticEnergy 2.0 5.0) epsilon; # 0.5 * 2 * 5^2
      # Test gravitationalPotentialEnergy
      testGravPotentialEnergy = assertWithinTolerance "gravitationalPotentialEnergy" 98.0665 (equations.gravitationalPotentialEnergy 1.0 10.0) epsilon; # 1 * 9.80665 * 10
    };

    testFinancial = {
      # Test simpleInterest
      testSimpleInterest = assertWithinTolerance "simpleInterest" 110.0 (equations.simpleInterest 100.0 0.05 2.0) epsilon; # 100 * (1 + 0.05 * 2)
      # Test compoundInterest (compounded annually)
      testCompoundInterestAnnual = assertWithinTolerance "compoundInterest (annual)" 110.25 (equations.compoundInterest 100.0 0.05 1.0 2.0) epsilon; # 100 * (1 + 0.05/1)^(1*2) = 100 * 1.05^2
      # Test compoundInterest (compounded monthly)
      testCompoundInterestMonthly = assertWithinTolerance "compoundInterest (monthly)" 110.49413 (equations.compoundInterest 100.0 0.05 12.0 2.0) (epsilon * 100000 ); # 100 * (1 + 0.05/12)^(12*2)
    };

    testUnitConversions = {
      # Test celsiusToFahrenheit
      testCtoF0 = assertWithinTolerance "celsiusToFahrenheit (0C)" 32.0 (equations.celsiusToFahrenheit 0.0) epsilon;
      testCtoF100 = assertWithinTolerance "celsiusToFahrenheit (100C)" 212.0 (equations.celsiusToFahrenheit 100.0) epsilon;
      # Test fahrenheitToCelsius
      testFtoC32 = assertWithinTolerance "fahrenheitToCelsius (32F)" 0.0 (equations.fahrenheitToCelsius 32.0) epsilon;
      testFtoC212 = assertWithinTolerance "fahrenheitToCelsius (212F)" 100.0 (equations.fahrenheitToCelsius 212.0) epsilon;
      # Test kelvinToCelsius
      testKtoC0 = assertWithinTolerance "kelvinToCelsius (0K)" (-273.15) (equations.kelvinToCelsius 0.0) epsilon;
      testKtoC273 = assertWithinTolerance "kelvinToCelsius (273.15K)" 0.0 (equations.kelvinToCelsius 273.15) epsilon;
      # Test celsiusToKelvin
      testCtoKneg273 = assertWithinTolerance "celsiusToKelvin (-273.15C)" 0.0 (equations.celsiusToKelvin (-273.15)) epsilon;
      testCtoK0 = assertWithinTolerance "celsiusToKelvin (0C)" 273.15 (equations.celsiusToKelvin 0.0) epsilon;
    };

    testStatisticsEquations = {
      # Test range (from equations.nix)
      testRange = assert (equations.range [ 3 1 5 2 4 ] == 4); true; # 5 - 1
      # Test variance (from equations.nix)
      testVariance = assertWithinTolerance "variance" 2.0 (equations.variance [ 1 2 3 4 5 ]) epsilon; # Matches stdDev^2
    };

    testTrigonometryEquations = {
      # Test lawOfCosines (find side c of 3, 4, 90deg triangle -> should be 5)
      testLawOfCosinesRightAngle = assertWithinTolerance "lawOfCosines (right angle)" 5.0 (equations.lawOfCosines 3.0 4.0 (math.pi / 2.0)) epsilon;
      # Test lawOfCosines (find side c of 3, 4, 60deg triangle -> c^2 = 9 + 16 - 2*3*4*cos(60) = 25 - 24*0.5 = 25 - 12 = 13)
      testLawOfCosines60Deg = assertWithinTolerance "lawOfCosines (60 deg)" (math.sqrt 13.0) (equations.lawOfCosines 3.0 4.0 (math.pi / 3.0)) epsilon;
    };

    testVectorMath = {
      # Test dotProduct2D
      testDotProduct2D = assertWithinTolerance "dotProduct2D" 11.0 (equations.dotProduct2D 1.0 2.0 3.0 4.0) epsilon; # 1*3 + 2*4 = 3 + 8
      # Test vectorMagnitude2D
      testVectorMagnitude2D = assertWithinTolerance "vectorMagnitude2D" 5.0 (equations.vectorMagnitude2D 3.0 4.0) epsilon;
      # Test normalizeVector2D
      testNormalizeVector2D =
        let v = equations.normalizeVector2D 3.0 4.0;
        in assert assertWithinTolerance "normalizeVector2D.x" 0.6 v.x epsilon;
           assert assertWithinTolerance "normalizeVector2D.y" 0.8 v.y epsilon;
           true;
      # Test vectorAdd2D
      testVectorAdd2D =
        let v = equations.vectorAdd2D 1.0 2.0 3.0 4.0;
        in assert assertWithinTolerance "vectorAdd2D.x" 4.0 v.x epsilon;
           assert assertWithinTolerance "vectorAdd2D.y" 6.0 v.y epsilon;
           true;
      # Test vectorSubtract2D
      testVectorSubtract2D =
        let v = equations.vectorSubtract2D 5.0 7.0 1.0 2.0;
        in assert assertWithinTolerance "vectorSubtract2D.x" 4.0 v.x epsilon;
           assert assertWithinTolerance "vectorSubtract2D.y" 5.0 v.y epsilon;
           true;
      # Test vectorScale2D
      testVectorScale2D =
        let v = equations.vectorScale2D 3.0 4.0 2.0;
        in assert assertWithinTolerance "vectorScale2D.x" 6.0 v.x epsilon;
           assert assertWithinTolerance "vectorScale2D.y" 8.0 v.y epsilon;
           true;
    };
  };

in
# Return the test sets, adding the aggregate runner
testSets // {
  # --- Aggregate Test Runner ---
  # This attribute recursively checks all assertions in the nested sets.
  # Evaluating this attribute will run all tests.
  runAllTests = lib.recurseIntoAttrs testSets;
}

