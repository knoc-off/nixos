{
  inputs,
  upkgs,
  pkgs,
  ...
}: let
  jail = inputs.jail-nix.lib.init pkgs;
  inherit (pkgs) lib;

  compatProxy = pkgs.callPackage ./compat-proxy {};
  rulesDir = "${compatProxy}/share/compat-proxy/rules";

  agentToolbelt = with pkgs; [
    bashInteractive
    coreutils
    findutils
    diffutils
    git
    ripgrep
    fd
    jq
    curl
    cacert
    gnused
    gawk
    gnugrep
    gnutar
    gzip
    upkgs.claude-code
    upkgs.opencode
    bash
  ];
in
  jail "jailed-opencode" upkgs.fish (with jail.combinators; [
    network
    time-zone
    no-new-session
    mount-cwd

    (add-runtime ''
      GIT_ROOT=$(${pkgs.git}/bin/git -C "$(pwd -P)" rev-parse --show-toplevel 2>/dev/null || pwd -P)
      PROJECT_HASH=$(echo "$GIT_ROOT" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/head -c7)
      PROJECT_SHARE="$HOME/.local/share/opencode-jails/$PROJECT_HASH"
      PROJECT_STATE="$HOME/.local/state/opencode-jails/$PROJECT_HASH"
      PROJECT_CLAUDE="$HOME/.local/share/opencode-jails/$PROJECT_HASH/claude"
      PROJECT_CLAUDE_JSON="$HOME/.local/share/opencode-jails/$PROJECT_HASH/claude.json"

      ${pkgs.coreutils}/bin/mkdir -p "$PROJECT_SHARE" "$PROJECT_STATE" "$PROJECT_CLAUDE"
      echo "$GIT_ROOT" > "$PROJECT_SHARE/.project-path"

      # Each jail gets its own .claude.json; seed with onboarding-complete so
      # claude-code doesn't re-run setup on every launch (auth happens separately)
      [ -f "$PROJECT_CLAUDE_JSON" ] || echo '{"hasCompletedOnboarding":true,"migrationVersion":11,"opusProMigrationComplete":true,"sonnet1m45MigrationComplete":true}' > "$PROJECT_CLAUDE_JSON"

      while IFS= read -r f; do
        target=$(readlink "$f" 2>/dev/null || true)
        if [ -n "$target" ] && [[ "$target" == /nix/store/* ]]; then
          RUNTIME_ARGS+=(--ro-bind "$target" "$target")
        fi
      done < <(find "$HOME/.config/opencode" -path "*/node_modules" -prune -o -type l -print)
    '')

    (wrap-entry (entry: ''
      # Per-project port from git root hash (avoids collisions across jails)
      GIT_ROOT=$(git -C "$(pwd -P)" rev-parse --show-toplevel 2>/dev/null || pwd -P)
      PROJECT_HASH=$(echo "$GIT_ROOT" | sha256sum | head -c7)
      PROJECT_PORT=$((18800 + 16#''${PROJECT_HASH:0:4} % 200))

      PROXY_LOG="$HOME/.local/state/opencode"
      mkdir -p "$PROXY_LOG"

      COMPAT_PROXY_LOG=''${COMPAT_PROXY_LOG:-info}

      ${lib.getExe compatProxy} \
        --rules-dir "''${COMPAT_PROXY_RULES:-${rulesDir}}" \
        --schema-registry "''${COMPAT_PROXY_RULES:-${rulesDir}}/cc-schemas.toml" \
        --credentials-path "$HOME/.claude/.credentials.json" \
        --port $PROJECT_PORT \
        --log-level "$COMPAT_PROXY_LOG" \
        ''${COMPAT_PROXY_DUMP:+--dump-requests} \
        > "$PROXY_LOG/compat-proxy.log" 2>&1 &
      PROXY_PID=$!
      trap 'kill $PROXY_PID 2>/dev/null || true' EXIT

      # Wait for proxy to be ready
      for _ in $(seq 1 20); do
        if curl -sf http://127.0.0.1:$PROJECT_PORT/health > /dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      export OPENCODE_PROXY_URL="http://127.0.0.1:$PROJECT_PORT"
      ${entry}
    ''))

    (try-rw-bind (noescape "\"$HOME/.config/opencode\"") (noescape "~/.config/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/opencode\"") (noescape "~/.cache/opencode"))
    (try-rw-bind (noescape "\"$HOME/.config/compat-proxy\"") (noescape "~/.config/compat-proxy"))
    (rw-bind (noescape "\"$PROJECT_CLAUDE_JSON\"") (noescape "~/.claude.json"))
    (rw-bind (noescape "\"$PROJECT_CLAUDE\"") (noescape "~/.claude"))
    (rw-bind (noescape "\"$PROJECT_SHARE\"") (noescape "~/.local/share/opencode"))
    (rw-bind (noescape "\"$PROJECT_STATE\"") (noescape "~/.local/state/opencode"))

    (try-fwd-env "ANTHROPIC_API_KEY")
    (try-fwd-env "OPENAI_API_KEY")
    (try-fwd-env "COMPAT_PROXY_LOG")
    (try-fwd-env "COMPAT_PROXY_RULES")
    (try-fwd-env "COMPAT_PROXY_DUMP")
    (try-fwd-env "COMPAT_PROXY_UPSTREAM")

    (add-pkg-deps (agentToolbelt ++ [compatProxy]))
  ])
