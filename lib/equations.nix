# equations.nix
{ lib ? import <nixpkgs/lib>
, math ? import ./math.nix { inherit lib; }
}:

with math;
rec {
  /* Coordinate Systems */
  cartesianToPolar = x: y: {
    r = sqrt (pow x 2 + pow y 2);
    theta = atan2 y x;
  };

  polarToCartesian = r: theta: {
    x = r * cos theta;
    y = r * sin theta;
  };

  /* Algebraic Equations */
  solveQuadratic = a: b: c:
    let
      discriminant = pow b 2 - 4 * a * c;
      sqrtD = sqrt discriminant;
    in if discriminant < 0 then [] else [
      ((-b + sqrtD) / (2 * a))
      ((-b - sqrtD) / (2 * a))
    ];

  /* Geometry */
  euclideanDistance2D = x1: y1: x2: y2:
    sqrt (pow (x2 - x1) 2 + pow (y2 - y1) 2);

  euclideanDistance3D = x1: y1: z1: x2: y2: z2:
    sqrt (pow (x2 - x1) 2 + pow (y2 - y1) 2 + pow (z2 - z1) 2);

  circleArea = radius: pi * pow radius 2;
  sphereVolume = radius: (4.0 / 3.0) * pi * pow radius 3;

  /* Interpolation */
  inverseLerp = a: b: value: (value - a) / (b - a);
  remap = inMin: inMax: outMin: outMax: value:
    lerp outMin outMax (inverseLerp inMin inMax value);

  smoothstep = edge0: edge1: x:
    let
      t = clamp ((x - edge0) / (edge1 - edge0)) 0.0 1.0;
    in t * t * (3.0 - 2.0 * t);

  /* Physics */
  kineticEnergy = mass: velocity: 0.5 * mass * pow velocity 2;
  gravitationalPotentialEnergy = mass: height:
    mass * 9.80665 * height;  # Earth gravity

  /* Financial */
  simpleInterest = principal: rate: time:
    principal * (1 + rate * time);

  compoundInterest = principal: rate: periods: time:
    principal * pow (1 + rate / periods) (periods * time);

  /* Unit Conversions */
  celsiusToFahrenheit = c: (c * 9.0 / 5.0) + 32.0;
  fahrenheitToCelsius = f: (f - 32.0) * (5.0 / 9.0);

  kelvinToCelsius = k: k - 273.15;
  celsiusToKelvin = c: c + 273.15;

  /* Statistics */
  range = numbers:
    let sorted = lib.sort (a: b: a < b) numbers;
    in lib.last sorted - lib.head sorted;

  variance = numbers:
    let
      avg = average numbers;
      squaredDiffs = map (x: pow (x - avg) 2) numbers;
    in average squaredDiffs;

  /* Trigonometry */
  lawOfCosines = a: b: angle:
    sqrt (pow a 2 + pow b 2 - 2 * a * b * cos angle);

  /* Vector Math */
  dotProduct2D = x1: y1: x2: y2: x1 * x2 + y1 * y2;
  vectorMagnitude2D = x: y: sqrt (pow x 2 + pow y 2);
  normalizeVector2D = x: y:
    let mag = vectorMagnitude2D x y;
    in { x = x / mag; y = y / mag; };

  /* Vector Operations */
  vectorAdd2D = x1: y1: x2: y2: {
    x = x1 + x2;
    y = y1 + y2;
  };

  vectorSubtract2D = x1: y1: x2: y2: {
    x = x1 - x2;
    y = y1 - y2;
  };

  vectorScale2D = x: y: scale: {
    x = x * scale;
    y = y * scale;
  };

  /* Geometry */
  triangleArea = base: height: 0.5 * base * height;

  rectangleArea = width: height: width * height;

  trapezoidArea = a: b: height: 0.5 * (a + b) * height;

  cylinderVolume = radius: height: pi * pow radius 2 * height;

  coneVolume = radius: height: (1.0 / 3.0) * pi * pow radius 2 * height;
}

