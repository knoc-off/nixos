{ lib
, buildNpmPackage
, fetchFromGitHub
}:

buildNpmPackage rec {
  pname = "mcscript";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "Stevertus";
    repo = "mcscript";
    rev = version;
    hash = "sha256-+eC+UtJhnBao5nsytRROW+s4K3E1hG+n8QJpkN8ZaH8=";
  };

  npmDepsHash = "";

  # Use postPatch to ensure package-lock.json is copied after unpacking the source
  postPatch = ''
    echo "Copying package-lock.json to build directory"
    cp ${./package-lock.json} ./package-lock.json
    ls -l
  '';


  meta = with lib; {
    description = "A programming language for Minecraft Vanilla";
    homepage = "https://github.com/Stevertus/mcscript";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.all;
  };
}
