{
  inputs,
  upkgs,
  pkgs,
  ...
}: let
  jail = inputs.jail-nix.lib.init pkgs;
  inherit (pkgs) lib;

  compatProxy = pkgs.callPackage ./compat-proxy {};

  agentToolbelt = with pkgs; [
    # Shell essentials
    bashInteractive
    bash
    coreutils
    findutils
    diffutils

    # Version control
    git
    openssh # git over SSH, scp

    # Search & navigation
    ripgrep
    fd
    tree
    file
    which

    # Text processing
    gnused
    gawk
    gnugrep
    jq
    less
    bat

    # Networking
    curl
    wget
    cacert

    # Archives & compression
    gnutar
    gzip
    unzip
    xz

    # Patching
    gnupatch

    # Process inspection
    procps # ps, top, pgrep, etc.

    # Nix — self-provisioning inside the jail.
    # Use Determinate's nix-cli (instead of pkgs.nix) so it recognizes
    # the eval-cores / lazy-trees settings present in /etc/nix/nix.conf
    # and doesn't emit warnings on every invocation.
    inputs.determinate.inputs.nix.packages.${pkgs.system}.nix-cli

    # Coding agents
    upkgs.claude-code
    upkgs.opencode
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
    '')

    (wrap-entry (entry: ''
      # Per-project port from git root hash (avoids collisions across jails)
      GIT_ROOT=$(git -C "$(pwd -P)" rev-parse --show-toplevel 2>/dev/null || pwd -P)
      PROJECT_HASH=$(echo "$GIT_ROOT" | sha256sum | head -c7)
      PROJECT_PORT=$((18800 + 16#''${PROJECT_HASH:0:4} % 200))

      PROXY_LOG="$HOME/.local/state/opencode"
      mkdir -p "$PROXY_LOG"

      COMPAT_PROXY_LOG=''${COMPAT_PROXY_LOG:-info}

      RULES_DIR="''${COMPAT_PROXY_RULES:-$HOME/.config/compat-proxy/rules}"
      ${lib.getExe compatProxy} \
        --rules-dir "$RULES_DIR" \
        --schema-registry "$RULES_DIR/cc-schemas.toml" \
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

      export OPENCODE_PROXY_URL="http://127.0.0.1:$PROJECT_PORT/v1"

      # fucks startup time, but it will work
      claude -p "say just 'ok'" --model 'haiku'

      ${lib.getExe upkgs.opencode} "$@" || true

      # fish
      ${entry}
    ''))

    (try-rw-bind (noescape "\"$HOME/.config/opencode\"") (noescape "~/.config/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/opencode\"") (noescape "~/.cache/opencode"))
    (add-runtime ''
      COMPAT_PROXY_RULES_REAL=$(readlink -f "$HOME/.config/compat-proxy/rules" 2>/dev/null || true)
    '')
    (try-ro-bind (noescape "\"$COMPAT_PROXY_RULES_REAL\"") (noescape "~/.config/compat-proxy/rules"))
    (rw-bind (noescape "\"$PROJECT_CLAUDE_JSON\"") (noescape "~/.claude.json"))
    (rw-bind (noescape "\"$PROJECT_CLAUDE\"") (noescape "~/.claude"))
    (rw-bind (noescape "\"$PROJECT_SHARE\"") (noescape "~/.local/share/opencode"))
    (rw-bind (noescape "\"$PROJECT_STATE\"") (noescape "~/.local/state/opencode"))

    # Nix support — allows nix build/shell/run inside the jail.
    #
    # The jail's /nix/store is per-path bind mounts (from add-pkg-deps), so
    # newly-built paths aren't visible. We mount the entire store directory
    # so the daemon's downloads appear immediately. NIX_REMOTE=daemon is
    # required because bwrap's uid mapping makes the store look user-owned,
    # which tricks nix into single-user mode.
    (ro-bind "/nix/store" "/nix/store")
    (try-rw-bind "/nix/var/nix/daemon-socket" "/nix/var/nix/daemon-socket")
    (try-ro-bind "/nix/var/nix/db" "/nix/var/nix/db")
    (try-ro-bind "/etc/nix" "/etc/nix")
    # NixOS symlinks /etc/nix/{registry.json,nix.custom.conf} → /etc/static/…
    (try-ro-bind "/etc/static/nix" "/etc/static/nix")

    (try-fwd-env "SHELL")
    (try-fwd-env "COMPAT_PROXY_LOG")
    (try-fwd-env "COMPAT_PROXY_RULES")
    (try-fwd-env "COMPAT_PROXY_DUMP")
    (try-fwd-env "COMPAT_PROXY_UPSTREAM")
    (try-fwd-env "NIX_PATH")
    (set-env "NIX_REMOTE" "daemon")

    (add-pkg-deps (agentToolbelt ++ [compatProxy]))
  ])
