{ lib, python3, fetchFromGitHub, ... }:

python3.pkgs.buildPythonApplication rec {
  pname = "wrap-codeblocks";
  version = "1.0.0";

  # Use the current directory, which should contain your Python script.
  src = ./.;

  propagatedBuildInputs = with python3.pkgs; [
    pathspec
    pygments
  ];

  # Use the appropriate entry point as installed. In this example, we
  # assume your script is named "wrap-codeblocks.py". Adjust if needed.
  entryPoint = "wrap-codeblocks.py";

  meta = with lib; {
    description = "File-to-XML converter with automatic .gitignore support and language detection.";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ "Your Name <you@example.com>" ];
  };
}

