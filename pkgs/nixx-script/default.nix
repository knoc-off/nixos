{ lib, python3, fetchFromGitHub }:

python3.pkgs.buildPythonApplication rec {
  pname = "nixx";
  version = "1.0.0";

  # Uses the current directory as the source (which must include
  # nixx.py and setup.py).
  src = ./.;

  # You can add any propagatedBuildInputs if your script needed external
  # Python modules. Here, we don’t need extra ones.
  propagatedBuildInputs = [];

  # The entry point is defined by our setup.py file.
  entryPoint = "nixx";

  meta = with lib; {
    description =
      "A nix wrapper that processes arguments, supports background execution, "
      + "and integrates with nix-shell and pueue.";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ "Your Name <you@example.com>" ];
  };
}

