{
  lib,
  buildGo126Module,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs,
}: let
  version = "2.3.6";

  src = fetchFromGitHub {
    owner = "dagu-org";
    repo = "Dagu";
    rev = "v${version}";
    hash = "sha256-HcjBLvtL6e5tcVn+Y/KWnvR9MaXA8g0qJiFxpuRahd4=";
  };
in
  buildGo126Module {
    pname = "dagu";
    inherit version src;

    vendorHash = "sha256-VZlskGF/qsZ8UeaGuaWF9+biAHcdxo34wmQJeFua+c8=";

    nativeBuildInputs = [
      pnpm_10
      pnpmConfigHook
      nodejs
    ];

    pnpmDeps = fetchPnpmDeps {
      pname = "dagu-ui";
      inherit version src;
      sourceRoot = "${src.name}/ui";
      pnpm = pnpm_10;
      fetcherVersion = 3;
      hash = "sha256-fFHrOSLcTKNtnZn11pITA9nZFPCdJX7tE/DykrQxzJg=";
    };

    pnpmRoot = "ui";

    preBuild = ''
      # Build the frontend UI
      pushd ui
      pnpm build
      popd

      # Copy built assets into the embed directory
      rm -rf internal/service/frontend/assets/*
      cp ui/dist/* internal/service/frontend/assets/
    '';

    postInstall = ''
      mv $out/bin/cmd $out/bin/dagu
    '';

    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
    ];

    # Tests require filesystem access and network that aren't available in the Nix sandbox
    doCheck = false;

    meta = {
      description = "A local-first workflow engine built the way it should be: declarative, file-based, self-contained, air-gapped ready. One binary that scales from laptop to distributed cluster. Your Workflow Operator handles creating and debugging workflows";
      homepage = "https://github.com/dagu-org/Dagu";
      license = lib.licenses.gpl3Only;
      maintainers = with lib.maintainers; [];
      mainProgram = "dagu";
    };
  }
