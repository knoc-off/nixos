{ lib
, pkgs
, python3
, fetchFromGitHub
}:

python3.pkgs.buildPythonApplication rec {
  pname = "texify";
  version = "0.1.10";  # Update this to the latest version

  src = fetchFromGitHub {
    owner = "VikParuchuri";
    repo = "texify";
    rev = "v${version}";
    sha256 = "sha256-9ubzbZa8IE/oKIO7cjNkJExlj9XWpeIdDOuAOZ3qFNg=";
  };

  format = "pyproject";

  nativeBuildInputs = with pkgs; [
    poetry
  ];

  buildInputs = with python3.pkgs; [
    setuptools
    poetry-core
  ];

  propagatedBuildInputs = with python3.pkgs; [
    scikit-learn
    pillow
    pydantic
    pydantic-settings
    transformers
    numpy
    python-dotenv
    torch
    tqdm
    tabulate
    ftfy
    rapidfuzz
    filetype
    regex
    grpcio
    pypdfium2
  ];

  # Ensure poetry uses the project's virtualenv
  POETRY_VIRTUALENVS_CREATE = false;

  # Disable tests for now as they might require additional setup
  doCheck = false;

  meta = with lib; {
    description = "OCR model that converts images or PDFs containing math into markdown and LaTeX";
    homepage = "https://github.com/VikParuchuri/texify";
    maintainers = with maintainers; [ ]; # Add your name if you're maintaining this package
  };
}

