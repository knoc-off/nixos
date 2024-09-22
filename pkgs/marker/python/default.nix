{ pkgs ? import <nixpkgs> {} }:

let
  pythonPackages = pkgs.python3Packages;
in pkgs.mkShell {
  buildInputs = [
    pkgs.python3
    pythonPackages.virtualenv
    pythonPackages.pip
    pythonPackages.tensorflow
    pythonPackages.pillow
    pythonPackages.numpy
    pythonPackages.matplotlib
  ];

  shellHook = ''
    # Create a virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
      echo "Creating new venv environment"
      python -m venv venv
    fi

    # Activate the virtual environment
    source venv/bin/activate

    # Upgrade pip
    pip install --upgrade pip

    echo "Python virtual environment activated. Use 'deactivate' to exit."
  '';
}
