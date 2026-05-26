{
  lib,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
  bun,
  uv,
  nodejs,

  makeWrapper,
}: let
  version = "13.2.0";

  src = fetchFromGitHub {
    owner = "thedotmack";
    repo = "claude-mem";
    rev = "v${version}";
    hash = "sha256-TP/oB1HkFATfYY6sQx36vzJnRoetRjRq0k0sKpJ5GD8=";
  };

  # Runtime dependency for the worker (zod is marked external in the esbuild bundle)
  workerDeps = buildNpmPackage {
    pname = "claude-mem-worker-deps";
    inherit version src;

    # Override source to a minimal package with just zod
    postPatch = ''
      cp ${./worker-deps-lock.json} package-lock.json
      cat > package.json << 'EOF'
      {
        "name": "claude-mem-worker-deps",
        "version": "1.0.0",
        "private": true,
        "dependencies": {
          "zod": "^4.3.6"
        }
      }
      EOF
    '';

    npmDepsHash = "sha256-0g0bJHjKXGRhNw4hYkkGjhWLRnIAZyyyfVmI1Mo8P+U=";
    dontNpmBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/node_modules
      cp -r node_modules/zod $out/lib/node_modules/
      runHook postInstall
    '';
  };
in
  stdenv.mkDerivation {
    pname = "claude-mem";
    inherit version src;

    nativeBuildInputs = [makeWrapper];

    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/claude-mem

      # Pre-built worker and helper scripts
      cp -r plugin $out/lib/claude-mem/

      # OpenCode plugin (standalone, no build step, no zod dependency)
      mkdir -p $out/lib/claude-mem/dist/opencode-plugin
      cp ${./opencode-plugin.js} $out/lib/claude-mem/dist/opencode-plugin/index.js

      # Symlink zod into the worker's module resolution path
      mkdir -p $out/lib/claude-mem/plugin/node_modules
      ln -s ${workerDeps}/lib/node_modules/zod $out/lib/claude-mem/plugin/node_modules/zod

      # Worker wrapper (runs under Bun for bun:sqlite)
      mkdir -p $out/bin
      makeWrapper ${bun}/bin/bun $out/bin/claude-mem-worker \
        --add-flags "$out/lib/claude-mem/plugin/scripts/worker-service.cjs" \
        --set NODE_PATH "$out/lib/claude-mem/plugin/node_modules" \
        --prefix PATH : ${lib.makeBinPath [ uv ]}

      runHook postInstall
    '';

    meta = with lib; {
      description = "Persistent memory compression system for Claude Code and OpenCode";
      homepage = "https://github.com/thedotmack/claude-mem";
      license = licenses.asl20;
      platforms = platforms.linux;
      mainProgram = "claude-mem-worker";
    };
  }
