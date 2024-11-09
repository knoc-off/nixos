{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs
}:

buildNpmPackage rec {
  pname = "notes";
  version = "0.90.8";

  src = fetchFromGitHub {
    owner = "TriliumNext";
    repo = "Notes";
    rev = "v${version}";
    hash = "sha256-SiU0+BX/CmiiCqve12kglh6Qa2TtTYIYENGFwyGiMsU=";
  };

  npmDepsHash = "sha256-TumJ1d696FpaeOrD3aZuP1PrVExlXHY4o1z4agyDXBU=";

  # Skip some unnecessary steps
  dontNpmBuild = true;
  dontNpmPrune = true;
  ELECTRON_SKIP_BINARY_DOWNLOAD = "1";

  postInstall = ''
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/trilium-server \
      --add-flags "$out/lib/node_modules/${pname}/src/www" \
      --chdir "$out/lib/node_modules/${pname}"
  '';

  meta = with lib; {
    description = "Build your personal knowledge base with TriliumNext Notes";
    homepage = "https://github.com/TriliumNext/Notes";
    license = licenses.agpl3Only;
    maintainers = with maintainers; [ ];
    mainProgram = "trilium";
    platforms = platforms.all;
  };
}

