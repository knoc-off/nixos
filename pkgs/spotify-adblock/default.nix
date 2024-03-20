{pkgs, ...}:
pkgs.rustPackages.rustPlatform.buildRustPackage
{
  pname = "spotify-adblock";
  version = "0.0.1";

  cargoHash = "sha256-HpOxoHe7jbmgU2Im0JKSGISmj4im6fwFIuyJTueLmM0=";
  # Exec=env LD_PRELOAD=/usr/local/lib/spotify-adblock.so spotify %U

  #nativeBuildInputs = [ pkg-config ];

  src = pkgs.fetchFromGitHub {
    owner = "abba23";
    repo = "spotify-adblock";
    rev = "5a3281dee9f889afdeea7263558e7a715dcf5aab";
    hash = "sha256-UzpHAHpQx2MlmBNKm2turjeVmgp5zXKWm3nZbEo0mYE=";
  };
}
