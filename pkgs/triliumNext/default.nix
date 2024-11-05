{ lib
, buildNpmPackage
, fetchFromGitHub
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

  # If the package uses npm workspaces
  # npmWorkspace = ".";

  # Skip some unnecessary steps
  dontNpmBuild = false;  # Set to true if no build step is needed
  dontNpmPrune = true;

  postInstall = ''
    mkdir -p $out/bin
    cat > $out/bin/notes <<EOF
    #!/bin/sh
    cd $out/lib/node_modules/${pname}
    exec node dist/www.js
    EOF
    chmod +x $out/bin/notes
  '';

  meta = with lib; {
    description = "Build your personal knowledge base with TriliumNext Notes";
    homepage = "https://github.com/TriliumNext/Notes";
    license = licenses.agpl3Only;
    maintainers = with maintainers; [ ];
    mainProgram = "notes";
    platforms = platforms.all;
  };
}

