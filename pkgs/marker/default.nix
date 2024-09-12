{ pkgs ? import <nixpkgs> {} }:

let
  pythonEnv = pkgs.python311.withPackages (ps: with ps; [
    pip
    virtualenv
  ]);
in
pkgs.mkShell {
  buildInputs = [
    pythonEnv
    pkgs.ghostscript
    pkgs.tesseract
    pkgs.git
    pkgs.stdenv.cc.cc.lib
    pkgs.libGL
    pkgs.libGLU
    pkgs.xorg.libX11
    pkgs.xorg.libXi
    pkgs.xorg.libXmu
    pkgs.xorg.libXext
    pkgs.opencv
    pkgs.glib
    pkgs.gtk3
    pkgs.gdk-pixbuf
    pkgs.cairo
  ];

  shellHook = ''
    echo "Marker development environment"
    echo "Run 'python -m venv venv' to create a virtual environment"
    echo "Then 'source venv/bin/activate' to activate it"
    echo "Finally, 'pip install marker-pdf' to install marker"

    # Increase the file descriptor limit
    ulimit -n 4096
  '';

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [
    pkgs.stdenv.cc.cc.lib
    pkgs.libGL
    pkgs.libGLU
    pkgs.xorg.libX11
    pkgs.xorg.libXi
    pkgs.xorg.libXmu
    pkgs.xorg.libXext
    pkgs.opencv
    pkgs.glib
    pkgs.gtk3
    pkgs.gdk-pixbuf
    pkgs.cairo
  ];

  PKG_CONFIG_PATH = pkgs.lib.makeSearchPath "lib/pkgconfig" [
    pkgs.glib.dev
    pkgs.gtk3.dev
    pkgs.gdk-pixbuf.dev
    pkgs.cairo.dev
  ];

  # Set environment variables for PyTorch
  PYTORCH_USE_SYSTEM_NCCL = "1";
  USE_SYSTEM_NCCL = "1";
  TORCH_USE_CUDA_DSA = "0";
}

