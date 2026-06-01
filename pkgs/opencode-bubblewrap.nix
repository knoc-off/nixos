{
  inputs,
  upkgs,
  pkgs,
  ...
}: let
  jail = inputs.jail-nix.lib.init (pkgs.extend (_: prev: {
    writeShellApplication = args: prev.writeShellApplication (args // {
      excludeShellChecks = (args.excludeShellChecks or []) ++ ["SC2016"];
    });
  }));
  inherit (pkgs) lib;

  compatProxy = pkgs.callPackage ./compat-proxy {};
  claudeMem = pkgs.callPackage ./claude-mem {};
  hostQuery = pkgs.callPackage ./host-query {};

  # Safe rm/rmdir — shadows coreutils inside the jail so agent deletions
  # land in the FreeDesktop trash (~/.local/share/Trash/) instead of being
  # permanent.  Uses rmtrash which accepts all GNU rm/rmdir flags.
  rmSafe = pkgs.symlinkJoin {
    name = "rm-safe";
    paths = [
      (pkgs.writeShellScriptBin "rm" ''exec ${pkgs.rmtrash}/bin/rmtrash "$@"'')
      (pkgs.writeShellScriptBin "rmdir" ''exec ${pkgs.rmtrash}/bin/rmdirtrash "$@"'')
    ];
  };

  # Jail-specific opencode overrides — merged on top of the global config.
  # Permissions are relaxed because the sandbox already constrains blast radius.
  jailConfig = pkgs.writeText "opencode-jail.json" (builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    permission = {
      # Read/explore — always allowed, no side effects
      read = "allow";
      glob = "allow";
      grep = "allow";
      list = "allow";
      lsp = "allow";
      repo_overview = "allow";
      codesearch = "allow";
      webfetch = "allow";
      websearch = "allow";

      # Agent utilities — safe
      task = "allow";
      question = "allow";
      todowrite = "allow";
      repo_clone = "allow";
      skill = "allow";
      external_directory = "allow";

      # Bash — sandbox + trash-backed rm constrain damage
      bash = "allow";

      # Edit — user approves each file modification
      edit = "ask";

      # Host exec — user approves each host command
      host_exec = "ask";
    };
  });

  # Appended to the system prompt by the compat-proxy (via COMPAT_PROXY_APPEND_SYSTEM).
  # Injected after the main CC prompt replacement, so the agent knows its constraints.
  jailSystemContext = builtins.readFile ./jail-context.md;

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

    # Safe deletion (trash-cli provides trash-put, used by rmtrash)
    trash-cli
    rmtrash

    # Process inspection
    procps # ps, top, pgrep, etc.

    # Nix — self-provisioning inside the jail.
    # Use Determinate's nix-cli (instead of pkgs.nix) so it recognizes
    # the eval-cores / lazy-trees settings present in /etc/nix/nix.conf
    # and doesn't emit warnings on every invocation.
    inputs.determinate.inputs.nix.packages.${pkgs.stdenv.hostPlatform.system}.nix-cli

    # Python tooling (uvx needed by claude-mem for chroma vector search)
    uv

    # Coding agents
    upkgs.claude-code
    upkgs.opencode
  ];
in
  jail "jailed-opencode" upkgs.fish (with jail.combinators; [
    network
    time-zone
    no-new-session
    (set-argv [])
    (add-cleanup ''kill $HOST_QUERY_PID 2>/dev/null || true'')

    (add-runtime ''
      # ── Parse CLI arguments ──────────────────────────────────
      JAIL_NAME=""
      JAIL_PROJECTS=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) JAIL_NAME="$2"; shift 2 ;;
          --) shift; break ;;
          -*) echo "jailed-opencode: unknown option: $1" >&2; exit 1 ;;
          *) JAIL_PROJECTS+=("$(${pkgs.coreutils}/bin/realpath "$1")"); shift ;;
        esac
      done
      while [[ $# -gt 0 ]]; do
        JAIL_PROJECTS+=("$(${pkgs.coreutils}/bin/realpath "$1")"); shift
      done

      # ── Project mounting ─────────────────────────────────────
      if [[ ''${#JAIL_PROJECTS[@]} -eq 0 ]]; then
        RUNTIME_ARGS+=(--bind "$PWD" "$PWD")
        JAIL_START_DIR="$PWD"
      else
        RUNTIME_ARGS+=(--dir "$HOME/projects")
        declare -A SEEN_NAMES
        for proj in "''${JAIL_PROJECTS[@]}"; do
          bname=$(${pkgs.coreutils}/bin/basename "$proj")
          if [[ -n "''${SEEN_NAMES[$bname]+x}" ]]; then
            echo "jailed-opencode: duplicate project basename '$bname'" >&2
            echo "  previous: ''${SEEN_NAMES[$bname]}" >&2
            echo "  conflict: $proj" >&2
            exit 1
          fi
          SEEN_NAMES[$bname]="$proj"
          RUNTIME_ARGS+=(--bind "$proj" "$HOME/projects/$bname")
        done
        JAIL_START_DIR="$HOME/projects"
      fi

      # ── Port derivation (deterministic per identity) ─────────
      if [[ -n "$JAIL_NAME" ]]; then
        PORT_SEED="$JAIL_NAME"
      else
        PORT_SEED="''${JAIL_PROJECTS[0]:-$PWD}"
      fi
      PORT_HASH=$(echo "$PORT_SEED" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/head -c7)
      JAIL_PROXY_PORT=$((18800 + 16#''${PORT_HASH:0:4} % 200))
      JAIL_MEM_PORT=$((19200 + 16#''${PORT_HASH:0:4} % 200))
      HOST_QUERY_PORT=$((19600 + 16#''${PORT_HASH:0:4} % 200))

      # ── Host-query service (runs on host, outside jail) ──────
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/state/opencode"
      ${lib.getExe hostQuery} "$HOST_QUERY_PORT" \
        > "$HOME/.local/state/opencode/host-query.log" 2>&1 &
      HOST_QUERY_PID=$!
      for _ in $(seq 1 20); do
        if ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:$HOST_QUERY_PORT/health" > /dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      # ── State mounting (named = isolated, unnamed = host) ────
      if [[ -n "$JAIL_NAME" ]]; then
        JAIL_DIR="$HOME/.local/share/opencode-jails/$JAIL_NAME"
        JAIL_STATE_DIR="$HOME/.local/state/opencode-jails/$JAIL_NAME"
        JAIL_CLAUDE_DIR="$JAIL_DIR/claude"
        JAIL_CLAUDE_JSON="$JAIL_DIR/claude.json"
        JAIL_MEM_DIR="$JAIL_DIR/claude-mem"

        ${pkgs.coreutils}/bin/mkdir -p "$JAIL_CLAUDE_DIR" "$JAIL_STATE_DIR" "$JAIL_MEM_DIR"

        [ -f "$JAIL_CLAUDE_JSON" ] || echo '{"hasCompletedOnboarding":true,"migrationVersion":11,"opusProMigrationComplete":true,"sonnet1m45MigrationComplete":true}' > "$JAIL_CLAUDE_JSON"

        RUNTIME_ARGS+=(--bind "$JAIL_CLAUDE_JSON" "$HOME/.claude.json")
        RUNTIME_ARGS+=(--bind "$JAIL_CLAUDE_DIR" "$HOME/.claude")
        RUNTIME_ARGS+=(--bind "$JAIL_DIR" "$HOME/.local/share/opencode")
        RUNTIME_ARGS+=(--bind "$JAIL_STATE_DIR" "$HOME/.local/state/opencode")
        RUNTIME_ARGS+=(--bind "$JAIL_MEM_DIR" "$HOME/.claude-mem")
        # Always share host credentials into isolated .claude
        [ -f "$HOME/.claude/.credentials.json" ] && \
          RUNTIME_ARGS+=(--ro-bind "$HOME/.claude/.credentials.json" "$HOME/.claude/.credentials.json")
      else
        RUNTIME_ARGS+=(--bind "$HOME/.claude.json" "$HOME/.claude.json")
        RUNTIME_ARGS+=(--bind "$HOME/.claude" "$HOME/.claude")
        RUNTIME_ARGS+=(--bind "$HOME/.local/share/opencode" "$HOME/.local/share/opencode")
        RUNTIME_ARGS+=(--bind "$HOME/.local/state/opencode" "$HOME/.local/state/opencode")
        [ -d "$HOME/.claude-mem" ] && RUNTIME_ARGS+=(--bind "$HOME/.claude-mem" "$HOME/.claude-mem")
      fi

      # ── Pass computed values into the jail ───────────────────
      RUNTIME_ARGS+=(--setenv JAIL_PROXY_PORT "$JAIL_PROXY_PORT")
      RUNTIME_ARGS+=(--setenv JAIL_MEM_PORT "$JAIL_MEM_PORT")
      RUNTIME_ARGS+=(--setenv HOST_QUERY_PORT "$HOST_QUERY_PORT")
      RUNTIME_ARGS+=(--setenv JAIL_START_DIR "$JAIL_START_DIR")
      RUNTIME_ARGS+=(--setenv JAIL_NAME "''${JAIL_NAME:-}")
    '')

    (wrap-entry (entry: ''
      PROXY_LOG="$HOME/.local/state/opencode"
      mkdir -p "$PROXY_LOG"

      COMPAT_PROXY_LOG=''${COMPAT_PROXY_LOG:-info}

      RULES_DIR="''${COMPAT_PROXY_RULES:-$HOME/.config/compat-proxy/rules}"
      ${lib.getExe compatProxy} \
        --rules-dir "$RULES_DIR" \
        --schema-registry "$RULES_DIR/cc-schemas.toml" \
        --credentials-path "$HOME/.claude/.credentials.json" \
        --port "$JAIL_PROXY_PORT" \
        --log-level "$COMPAT_PROXY_LOG" \
        ''${COMPAT_PROXY_DUMP:+--dump-requests} \
        > "$PROXY_LOG/compat-proxy.log" 2>&1 &
      PROXY_PID=$!
      trap 'kill $PROXY_PID 2>/dev/null || true' EXIT

      for _ in $(seq 1 20); do
        if curl -sf "http://127.0.0.1:$JAIL_PROXY_PORT/health" > /dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      export OPENCODE_PROXY_URL="http://127.0.0.1:$JAIL_PROXY_PORT/v1"

      CLAUDE_MEM_WORKER_PORT=$JAIL_MEM_PORT \
      CLAUDE_MEM_WORKER_HOST=127.0.0.1 \
      CLAUDE_MEM_DATA_DIR="$HOME/.claude-mem" \
        ${lib.getExe claudeMem} > "$PROXY_LOG/claude-mem.log" 2>&1 &
      CLAUDE_MEM_PID=$!
      trap 'kill $PROXY_PID $CLAUDE_MEM_PID 2>/dev/null || true' EXIT

      for _ in $(seq 1 20); do
        if curl -sf "http://127.0.0.1:$JAIL_MEM_PORT/api/health" > /dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done

      export CLAUDE_MEM_WORKER_PORT=$JAIL_MEM_PORT

      cd "$JAIL_START_DIR"
      ${entry}
    ''))

    (try-rw-bind (noescape "\"$HOME/.config/opencode\"") (noescape "~/.config/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/opencode\"") (noescape "~/.cache/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/uv\"") (noescape "~/.cache/uv"))

    # Persist trash across jail sessions — shared with the host's FreeDesktop trash.
    (add-runtime ''
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/share/Trash"
    '')
    (rw-bind (noescape "\"$HOME/.local/share/Trash\"") (noescape "~/.local/share/Trash"))

    # Shadow coreutils rm/rmdir with trash-backed versions inside the jail.
    # Deferred so it prepends to PATH *after* add-pkg-deps has built it.
    (defer (add-path "${rmSafe}/bin"))
    (add-runtime ''
      COMPAT_PROXY_RULES_REAL=$(readlink -f "$HOME/.config/compat-proxy/rules" 2>/dev/null || true)
    '')
    (try-ro-bind (noescape "\"$COMPAT_PROXY_RULES_REAL\"") (noescape "~/.config/compat-proxy/rules"))
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
    (set-env "OPENCODE_CONFIG" "${jailConfig}")
    (set-env "COMPAT_PROXY_APPEND_SYSTEM" jailSystemContext)

    (add-pkg-deps (agentToolbelt ++ [compatProxy claudeMem]))
  ])
