{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  fetchPypi,
  setuptools,
  wheel,
  httpx,
  websocket-client,
  requests-toolbelt,
  loguru,
  beautifulsoup4,
  quickjs,
  nest-asyncio,
  poetry-core,
  flit-core,
}: let
  markdownItPy = buildPythonPackage rec {
    pname = "markdown-it-py";
    version = "2.2.0";
    pyproject = true;
    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-fJpeQSaIvHccZ0Msv+vN1obJPOZISRPczwbLWgvqNaE=";
    };
    buildInputs = [flit-core];
  };

  pygments = buildPythonPackage rec {
    pname = "pygments";
    version = "2.15.1";
    pyproject = true;
    src = fetchPypi {
      inherit pname version;
      sha256 = "0e8f0e8f8e9f0e8e9f0e8f8e9f0e8e9f0e8e9f0e8f8e9f0e8f8e9f0e8f0e8f0e";
    };
  };

  rich = buildPythonPackage rec {
    pname = "rich";
    version = "13.3.4";
    pyproject = true;
    src = fetchPypi {
      inherit pname version;
      sha256 = "sha256-tdVz4TYFQj7IC90M1fhUH3hEoOcaE/dM9FTMsvSQcIs=";
    };
    buildInputs = [poetry-core markdownItPy pygments];
    #doCheck = false;
  };
in
  buildPythonPackage rec {
    pname = "poe-api-wrapper";
    version = "1.4.9";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "snowby666";
      repo = "poe-api-wrapper";
      rev = "v${version}";
      hash = "sha256-AEcOc6YuR72eLXSV/t0EqJcfHzgqIf9ULx8f3VxQXdE=";
    };

    nativeBuildInputs = [
      setuptools
      wheel
    ];

    propagatedBuildInputs = [
      httpx
      websocket-client
      requests-toolbelt
      loguru
      rich
      beautifulsoup4
      quickjs
      nest-asyncio
    ];

    pythonImportsCheck = ["poe_api_wrapper"];
    doCheck = false;
    meta = with lib; {
      description = "A Python API wrapper for Poe.com. With this, you will have free access to GPT-4, Claude, Llama, Gemini, Mistral and more";
      homepage = "https://github.com/snowby666/poe-api-wrapper";
      license = licenses.gpl3Only;
      maintainers = with maintainers; [];
    };
  }
