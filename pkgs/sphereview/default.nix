# SphereView - GTK4 image viewer for 360° equirectangular photospheres and panoramas
# https://github.com/dynobo/sphereview
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchNpmDeps,
  npmHooks,
  nodejs_22,
  pkg-config,
  glib,
  blueprint-compiler,
  wrapGAppsHook4,
  gtk4,
  libadwaita,
  webkitgtk_6_0,
  glib-networking,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "sphereview";
  version = "0.1.6";

  src = fetchFromGitHub {
    owner = "dynobo";
    repo = "sphereview";
    tag = "v${finalAttrs.version}";
    hash = "sha256-YvCMFnnJSVTYVSNRdIg/vZMy/9hgqHWbhFxrKG75fv8=";
  };

  cargoLock = {
    lockFile = "${finalAttrs.src}/Cargo.lock";
  };

  # Vendored JS deps for the bundled Photo Sphere Viewer frontend. Upstream's
  # build.rs runs `npm ci --offline && npm run build` itself during the cargo
  # build phase (it falls back to --offline whenever it can't reach 8.8.8.8:53,
  # which is always true in the Nix sandbox). npmConfigHook pre-populates
  # node_modules + npm's offline cache so that call succeeds unmodified.
  npmRoot = "resources/photosphereviewer";
  npmDeps = fetchNpmDeps {
    name = "sphereview-${finalAttrs.version}-npm-deps";
    src = "${finalAttrs.src}/resources/photosphereviewer";
    hash = "sha256-q0bOYCs32S5BZglvRohCewFDrSdeJK5tQO2MsAPpUDg=";
  };

  # node_modules is already installed & shebang-patched by npmConfigHook.
  # build.rs would otherwise re-run `npm ci`/`npm install` itself (it only
  # ever takes the `--offline` branch in the sandbox), which reinstalls
  # node_modules from scratch and restores unpatched "#!/usr/bin/env node"
  # shebangs (breaking `node_modules/.bin/vite` since there's no /usr/bin/env
  # in the sandbox). Drop that reinstall, keeping the `npm run build` and
  # `glib-compile-resources` calls untouched.
  postPatch = ''
    sed -i '/if TcpStream::connect/,/^    }$/d' build.rs
  '';

  nativeBuildInputs = [
    pkg-config
    nodejs_22
    npmHooks.npmConfigHook
    glib # for `glib-compile-resources`, invoked by upstream's build.rs
    blueprint-compiler # compiles resources/data/window.blp via gtk4's `blueprint` feature
    wrapGAppsHook4
  ];

  buildInputs = [
    gtk4
    libadwaita
    webkitgtk_6_0
    glib-networking
  ];

  postInstall = ''
    install -Dm644 io.github.dynobo.sphereview.desktop \
      $out/share/applications/io.github.dynobo.sphereview.desktop
    install -Dm644 io.github.dynobo.sphereview.appdata.xml \
      $out/share/metainfo/io.github.dynobo.sphereview.appdata.xml
    install -Dm644 resources/icons/scalable/apps/io.github.dynobo.sphereview.svg \
      $out/share/icons/hicolor/scalable/apps/io.github.dynobo.sphereview.svg
  '';

  meta = {
    description = "Image viewer for 360° equirectangular photospheres and panoramas";
    homepage = "https://github.com/dynobo/sphereview";
    changelog = "https://github.com/dynobo/sphereview/blob/v${finalAttrs.version}/CHANGELOG";
    license = lib.licenses.mit;
    mainProgram = "sphereview";
    platforms = lib.platforms.linux;
  };
})
