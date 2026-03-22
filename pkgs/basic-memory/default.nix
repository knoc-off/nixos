# Basic Memory - local-first knowledge management with MCP
# AI conversations that remember, stored as Markdown files
# https://github.com/basicmachines-co/basic-memory
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "basic-memory";
  version = "0.20.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "basicmachines-co";
    repo = "basic-memory";
    rev = "v${version}";
    hash = "sha256-x1co0sDbIMjLD7Ez9w6UwOjan4vkts4XMhAIyvhazD4=";
  };

  build-system = with python3Packages; [
    hatchling
  ];

  # uv-dynamic-versioning derives version from git tags which aren't
  # available in the nix fetch. Replace with a hardcoded version and
  # strip the build plugin dependency.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'dynamic = ["version"]' "" \
      --replace-fail 'requires = ["hatchling", "uv-dynamic-versioning>=0.7.0"]' \
                     'requires = ["hatchling"]' \
      --replace-fail '[tool.hatch.version]' "" \
      --replace-fail 'source = "uv-dynamic-versioning"' ""

    # Inject a static version into [project]
    substituteInPlace pyproject.toml \
      --replace-fail 'description =' 'version = "${version}"
    description ='
  '';

  dependencies = with python3Packages; [
    sqlalchemy
    pyyaml
    typer
    aiosqlite
    greenlet
    pydantic
    mcp
    pydantic-settings
    loguru
    markdown-it-py
    python-frontmatter
    rich
    unidecode
    dateparser
    watchfiles
    fastapi
    alembic
    pillow
    pybars3
    fastmcp
    pyjwt
    python-dotenv
    pytest-aio
    aiofiles
    asyncpg
    nest-asyncio
    pytest-asyncio
    psycopg
    mdformat
    mdformat-gfm
    mdformat-frontmatter
    sniffio
    anyio
    httpx
    fastembed
    sqlite-vec
    openai
  ];

  # pyright is listed as a runtime dep upstream (likely a mistake)
  # — it's a type checker and not needed at runtime
  pythonRemoveDeps = ["pyright"];

  # Tests require postgres testcontainers / Docker
  doCheck = false;

  meta = {
    description = "Local-first knowledge management with MCP - AI conversations that remember";
    homepage = "https://github.com/basicmachines-co/basic-memory";
    license = lib.licenses.agpl3Plus;
    mainProgram = "basic-memory";
  };
}
