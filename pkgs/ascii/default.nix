{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
}:
buildNpmPackage rec {
  pname = "ascii-silhouettify";
  version = "unstable-2024-06-07";

  src = fetchFromGitHub {
    owner = "meatfighter";
    repo = "ascii-silhouettify";
    rev = "a569a15a3e79a679e08f45290ce18b5b6d610b9e";
    hash = "sha256-4NwKOulGFSiNoUFm48taXGMxACRJUf/OYLIkg0hPTAI=";
  };

  npmDepsHash = "sha256-PK+EigyTztIGROHNcCl2iO1rNT63QQH6UzpsNY/o/74=";

  meta = with lib; {
    description = "A tool to convert images into ASCII art silhouettes";
    homepage = "https://github.com/meatfighter/ascii-silhouettify";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [];
    platforms = platforms.all;
  };
}
