{ lib
, buildPythonPackage
, fetchFromGitHub
, setuptools
, wheel
, pytest
, mkShell
, shell ? false
}:

let
  pname = "llm-cmd";
  version = "0.1a0";

  src = fetchFromGitHub {
    owner = "simonw";
    repo = "llm-cmd";
    rev = version;
    hash = "sha256-cYpX4+7XDqUgqI0q4FTiaJJQ+vb+XlucWW8H1U5WH3A=";
  };

  nativeBuildInputs = [
    setuptools
    wheel
  ];

  propagatedBuildInputs = [
  ];

  optional-dependencies = {
    test = [
      pytest
    ];
  };

  meta = with lib; {
    description = "Use LLM to generate and execute commands in your shell";
    homepage = "https://github.com/simonw/llm-cmd";
    license = licenses.asl20;
    maintainers = with maintainers; [];
  };

  package = buildPythonPackage {
    inherit pname version src nativeBuildInputs propagatedBuildInputs meta;
    pyproject = true;

    passthru.optional-dependencies = optional-dependencies;

    #pythonImportsCheck = [ "llm_cmd" ];
    dontCheckRuntimeDeps = true;
  };

in
if shell then
  mkShell {
    name = "${pname}-dev-shell";
    packages = nativeBuildInputs ++ propagatedBuildInputs ++ optional-dependencies.test;

    shellHook = ''
      echo "Entering ${pname} development shell"
    '';
  }
else
  package
