{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "mcp-auth-proxy";
  version = "2.10.2";

  src = fetchFromGitHub {
    owner = "sigbit";
    repo = "mcp-auth-proxy";
    tag = "v${finalAttrs.version}";
    hash = "sha256-unjFj943dCI2Ylo2Ekv7gsX8ltPE1nfnaOxbqBsAeu4=";
  };

  vendorHash = "sha256-3yMn2ybSLa+6V/VKY0AzChFCqGv5dPSzz70Xdps5n2E=";

  # Upstream ships CGO_ENABLED=0 release binaries, which makes the bundled
  # gorm.io/driver/sqlite (mattn/go-sqlite3) dead weight there as well.
  # Matching that keeps the C toolchain and glibc out of the closure.
  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
  ];

  # These three exercise the sqlite backend, which is a cgo stub under
  # CGO_ENABLED=0. Everything else in the suite, including
  # TestSQLRepositoryUnsupportedDriver, still runs.
  checkFlags = [ "-skip=^TestSQLRepository(AccessTokenSession|SessionPersistence)" ];

  # pkg/backend/testserver is a fixture for the test suite, not a tool. Drop it
  # after the build rather than restricting subPackages, which would also
  # narrow checkPhase to the root package and skip the pkg/* tests.
  postInstall = ''
    rm "$out/bin/testserver"
  '';

  meta = {
    description = "OAuth 2.1/OIDC authentication proxy for MCP servers";
    homepage = "https://github.com/sigbit/mcp-auth-proxy";
    changelog = "https://github.com/sigbit/mcp-auth-proxy/blob/v${finalAttrs.version}/CHANGELOG.md";
    license = lib.licenses.mit;
    mainProgram = "mcp-auth-proxy";
    platforms = lib.platforms.unix;
  };
})
