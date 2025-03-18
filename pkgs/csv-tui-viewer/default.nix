{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "csv-tui";
  version = "1.2";

  src = fetchFromGitHub {
    owner = "nathangavin";
    repo = "csv-tui";
    rev = "v${version}";
    hash = "sha256-T8T9fW4E/wigktSomoc+xPkVqX5T3OnTmL4XIT5YXe8=";
  };

  cargoHash = "sha256-WDUw539G15rf2X1NWLRCHIxMqyuxthEy8Cbn5XgIFCk=";

  meta = {
    description = "A terminal based csv editor which is designed to be not a ram hog like standard csv editors, but more useful than other text editors";
    homepage = "git@github.com:nathangavin/csv-tui.git";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ ];
    mainProgram = "csv-tui";
  };
}
