{
  lib,
  pkgs, # We'll need pkgs for fetchPypi and other utilities
  python3, # This is the base python interpreter
  fetchFromGitHub,
}:

let
  # Define the older, open-source PySimpleGUI package
  pysimplegui-4-60-5 = pkgs.python3Packages.buildPythonPackage rec {
    pname = "PySimpleGUI";
    version = "4.60.5";

    # Source from PyPI for this specific version
    src = pkgs.fetchPypi {
      inherit pname version;
      # This is the SHA256 hash for PySimpleGUI-4.60.5.tar.gz
      hash = "sha256-12ysLPIqpxQVg7aVBlq4es24oEVngQgNErJcR7kXNQU=";
    };

    # PySimpleGUI 4.x did not have significant build-time dependencies itself
    # It might have runtime dependencies, but those are usually handled by the application.
    # If it did, you'd add them to propagatedBuildInputs here.

    meta = {
      description = "Python GUI framework";
      homepage = "https://www.pysimplegui.org/";
      license = lib.licenses.lgpl3Only; # License for PySimpleGUI 4.x
    };
  };

  # Create a Python package set that includes our overridden PySimpleGUI
  # and the correct poetry-core.
  myPythonPackages = python3.pkgs.overrideScope (self: super: {
    pysimplegui = pysimplegui-4-60-5;
    # Ensure poetry-core is also taken from this consistent set
    poetry-core = super.poetry-core;
    # You can override other packages here if needed
  });

in
# Use our custom package set to build the application
myPythonPackages.buildPythonApplication rec {
  pname = "hack-interview";
  version = "unstable-2024-09-07";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "ivnvxd";
    repo = "hack-interview";
    rev = "134281ddfee359c2fd0e6d1f954ead6a3cd53086";
    hash = "sha256-Lj/gkUyPHVyBT0cz9AHIpVYgAEWR2c9ExNIuo3e2TRU=";
  };

  # For build systems like poetry-core, use nativeBuildInputs
  nativeBuildInputs = [
    myPythonPackages.poetry-core
  ];

  # For runtime dependencies of your application
  propagatedBuildInputs = with myPythonPackages; [
    loguru
    numpy
    openai
    pysimplegui # This will now refer to pysimplegui-4-60-5
    python-dotenv
    sounddevice
    soundfile
  ];

  pythonImportsCheck = [
    "hack_interview"
  ];

  meta = {
    description = "AI-powered tool for real-time interview question transcription and response generation";
    homepage = "https://github.com/ivnvxd/hack-interview/tree/main";
    license = lib.licenses.mit; # Your project's license
    maintainers = with lib.maintainers; [ ]; # Add your handle if you maintain this Nix expression
    mainProgram = "hack-interview";
  };
}

