{
  lib,
  python3,
  fetchFromGitHub,
}:
python3.pkgs.buildPythonApplication rec {
  pname = "ttok";
  version = "0.3";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "simonw";
    repo = "ttok";
    rev = version;
    hash = "sha256-I6EPE6GDAiDM+FbxYzRW4Pml0wDA2wNP1y3pD3dg7Gg=";
  };

  nativeBuildInputs = [
    python3.pkgs.setuptools
    python3.pkgs.wheel
  ];

  propagatedBuildInputs = [
    python3.pkgs.click
    python3.pkgs.tiktoken
  ];

  pythonImportsCheck = ["ttok"];

  meta = with lib; {
    description = "Count and truncate text based on tokens";
    homepage = "https://github.com/simonw/ttok";
    license = licenses.asl20;
    maintainers = with maintainers; [];
    mainProgram = "ttok";
  };
}
