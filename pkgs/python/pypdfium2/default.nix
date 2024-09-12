{ lib
, buildPythonPackage
, fetchPypi
, pythonOlder
, setuptools
, wheel
, git
, cffi
}:

buildPythonPackage rec {
  pname = "pypdfium2";
  version = "4.24.0";  # Check for the latest version on PyPI

  disabled = pythonOlder "3.6";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-YnBsBrxb45qnolMa+AJCBCm2xMR0mO69JSGvfpiNCEg=";
  };

  nativeBuildInputs = [
    setuptools
    wheel
  ];

  propagatedBuildInputs = [
    cffi
  ];

  # Disable tests if they're not easily runnable in Nix build environment
  doCheck = false;

  pythonImportsCheck = [ "pypdfium2" ];

  meta = with lib; {
    description = "Python bindings to PDFium";
    homepage = "https://github.com/pypdfium2-team/pypdfium2";
    license = licenses.asl20;
    maintainers = with maintainers; [ ]; # Add your name if you're maintaining this package
  };
}

