{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  autoPatchelfHook,
}:
stdenvNoCC.mkDerivation rec {
  pname = "linear-cli";
  version = "1.11.1";

  src = fetchurl {
    url = "https://github.com/schpet/linear-cli/releases/download/v${version}/${
      if stdenvNoCC.hostPlatform.system == "x86_64-linux"
      then "linear-x86_64-unknown-linux-gnu.tar.xz"
      else if stdenvNoCC.hostPlatform.system == "aarch64-linux"
      then "linear-aarch64-unknown-linux-gnu.tar.xz"
      else if stdenvNoCC.hostPlatform.system == "x86_64-darwin"
      then "linear-x86_64-apple-darwin.tar.xz"
      else if stdenvNoCC.hostPlatform.system == "aarch64-darwin"
      then "linear-aarch64-apple-darwin.tar.xz"
      else throw "unsupported system: ${stdenvNoCC.hostPlatform.system}"
    }";
    hash = "sha256-S7zwxOYXwYmK+zcyuhuvVW8JhXPI5hgaWiyEz7T0gII=";
  };

  nativeBuildInputs = [installShellFiles autoPatchelfHook];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 linear $out/bin/linear

    installShellCompletion \
      --cmd linear \
      --bash <($out/bin/linear completions bash) \
      --fish <($out/bin/linear completions fish) \
      --zsh  <($out/bin/linear completions zsh)

    runHook postInstall
  '';

  meta = with lib; {
    description = "Linear without leaving the command line: list, start, and create PRs for linear issues";
    homepage = "https://github.com/schpet/linear-cli";
    changelog = "https://github.com/schpet/linear-cli/blob/v${version}/CHANGELOG.md";
    license = licenses.isc;
    maintainers = with maintainers; [];
    mainProgram = "linear";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = with sourceTypes; [binaryNativeCode];
  };
}
