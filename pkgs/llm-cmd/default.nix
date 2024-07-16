{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  wheel,
  pytest,
}:
buildPythonPackage rec {
  pname = "llm-cmd";
  version = "0.1a0";
  pyproject = true;

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

  passthru.optional-dependencies = {
    test = [
      pytest
    ];
  };

  #pythonImportsCheck = [ "llm_cmd" ];
  dontCheckRuntimeDeps = true;

  meta = with lib; {
    description = "Use LLM to generate and execute commands in your shell";
    homepage = "https://github.com/simonw/llm-cmd";
    license = licenses.asl20;
    maintainers = with maintainers; [];
  };
}
