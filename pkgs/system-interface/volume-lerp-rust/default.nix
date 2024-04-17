{pkgs, ...}:
pkgs.rustPackages.rustPlatform.buildRustPackage
{
  pname = "volumeLerp";
  version = "0.0.1";

  cargoHash = "sha256-T8ihF8VBa2dfDYz71oeHgZPf8C6r3O9adqkvStzpylw=";

  src = ./.;

}
