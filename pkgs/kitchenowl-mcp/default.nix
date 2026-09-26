# MCP server for a single KitchenOwl household.
#
# Reads are compact projections of the REST API; writes go through a validator
# that checks a recipe renders and scales correctly before anything is written.
{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "kitchenowl-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3Packages.hatchling ];

  dependencies = with python3Packages; [
    fastmcp
    httpx
    uvicorn
  ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  passthru.devShell = python3Packages.python.withPackages (
    ps: with ps; [
      fastmcp
      httpx
      uvicorn
      pytest
    ]
  );

  meta = {
    description = "MCP server for a single KitchenOwl household, with recipe validation";
    homepage = "https://github.com/TomBursch/kitchenowl";
    license = lib.licenses.mit;
    mainProgram = "kitchenowl-mcp";
  };
}
