{
  inputs,
  upkgs,
  pkgs,
  ...
}: let
  jail = inputs.jail-nix.lib.init (pkgs.extend (_: prev: {
    writeShellApplication = args:
      prev.writeShellApplication (args
        // {
          excludeShellChecks = (args.excludeShellChecks or []) ++ ["SC2016"];
        });
    # Use Determinate's nix so jail-nix's internal `nix-store --query`
    # (in runtime-deep-ro-bind, invoked by the network combinator) doesn't
    # warn about eval-cores / lazy-trees / wasm-builtin from /etc/nix/nix.conf
    # on every startup.
    nix = inputs.determinate.inputs.nix.packages.${prev.stdenv.hostPlatform.system}.nix-cli;
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

  # Windows VM helpers — thin wrappers around sshpass+ssh/scp for the local
  # QEMU Windows VM (SSH forwarded to 127.0.0.1:2223). The jail shares the host
  # net namespace, so 127.0.0.1 reaches the same forwarded port as on the host.
  # Args pass straight through, so the caller controls the ssh/scp command line
  # (e.g. the dynamic 'C:/Users/vmadmin.TEMPLATE--XXXX/Desktop/' path).
  # Port/password are hardcoded (non-sensitive, local dev VM).
  windowsVmHelpers = let
    vmPort = "2223";
    vmPass = "admin";
    vmUser = "vmadmin";
  in pkgs.symlinkJoin {
    name = "windows-vm-helpers";
    paths = [
      (pkgs.writeShellScriptBin "windows-vm-ssh" ''
        exec ${pkgs.sshpass}/bin/sshpass -p ${vmPass} \
          ${pkgs.openssh}/bin/ssh -p ${vmPort} \
          -o StrictHostKeyChecking=no -4 \
          ${vmUser}@127.0.0.1 "$@"
      '')
      (pkgs.writeShellScriptBin "windows-vm-scp" ''
        exec ${pkgs.sshpass}/bin/sshpass -p ${vmPass} \
          ${pkgs.openssh}/bin/scp -P ${vmPort} \
          -o StrictHostKeyChecking=no -4 \
          "$@"
      '')
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
      # NOTE: task and todowrite are intentionally omitted. The default
      # "*": "allow" still lets the top-level agent use them, but opencode's
      # exact-match checks (rule.permission === "task"/"todowrite") won't
      # find explicit rules, so sub-agents get these tools disabled —
      # preventing recursive spawning and todo list clobbering.
      question = "allow";
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

  lspmux = pkgs.callPackage ./lspmux {};

  # Determinate nix — same one added to the toolbelt below. Used as
  # nix-direnv's fallback nix so it doesn't reach for a pinned older nix.
  determinateNix =
    inputs.determinate.inputs.nix.packages.${pkgs.stdenv.hostPlatform.system}.nix-cli;

  # direnv integration for the jail's fish shell.
  #
  # direnv is a shell hook (not a daemon), so nothing needs mounting from the
  # host — we just install the hook and nix-direnv's rc. The jail's home is a
  # tmpfs with no fish config, so we bind these generated files read-only:
  #   * fish conf.d snippet installs `direnv hook fish`
  #   * ~/.config/direnv/direnvrc sources nix-direnv (enables `use flake`)
  # The agent can still run `direnv allow` — that writes allow-state to
  # ~/.local/share/direnv (a persistent rw bind), not to these read-only files.
  direnvFishHook = pkgs.writeText "direnv-hook.fish" ''
    ${lib.getExe pkgs.direnv} hook fish | source
  '';
  direnvRc = pkgs.writeText "direnvrc" ''
    export NIX_DIRENV_FALLBACK_NIX=${lib.getExe determinateNix}
    source ${pkgs.nix-direnv}/share/nix-direnv/direnvrc
  '';

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

    # Non-interactive SSH auth (used by the windows-vm-* helper scripts).
    sshpass

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

    # Per-directory environments — direnv hook + nix-direnv (`use flake`).
    direnv
    nix-direnv

    # Process inspection
    procps # ps, top, pgrep, etc.

    # Nix — self-provisioning inside the jail.
    # Use Determinate's nix-cli (instead of pkgs.nix) so it recognizes
    # the eval-cores / lazy-trees settings present in /etc/nix/nix.conf
    # and doesn't emit warnings on every invocation.
    determinateNix

    # Python tooling (uvx needed by claude-mem for chroma vector search)
    uv

    # Language servers — opencode has built-in support for these.
    # Pre-provided because the jail lacks node/npm so npm-based
    # auto-install won't work, and pre-providing avoids runtime
    # downloads from GitHub/HashiCorp for the rest.
    nixd # .nix
    bash-language-server # .sh .bash .zsh .ksh
    yaml-language-server # .yaml .yml
    pyright # .py .pyi
    typescript-language-server # .ts .tsx .js .jsx .mjs .cjs .mts .cts
    dockerfile-language-server # Dockerfile
    svelte-language-server # .svelte
    vue-language-server # .vue
    astro-language-server # .astro
    biome # .ts .tsx .js .jsx (linter)
    lua-language-server # .lua
    gopls # .go
    terraform-ls # .tf .tfvars
    texlab # .tex .bib
    tinymist # .typ (typst)
    upkgs.gleam # .gleam — unstable skips network test escript_success_with_dependency (stable nixos-26.05 lags)
    zls # .zig .zon
    clojure-lsp # .clj .cljs .cljc .edn
    lspmux # LSP multiplexer (rust LSP via lspmux client)

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

    # Remove the empty mountpoint stubs bwrap created in the persistent
    # ~/projects backing dir for each mounted project. Uses rmdir (empty-only),
    # so real scratch dirs and any project that somehow got content are never
    # touched — only the throwaway empty stubs this session created.
    (add-cleanup ''
      for _bname in "''${JAIL_MOUNTED_BASENAMES[@]-}"; do
        [ -n "$_bname" ] || continue
        rmdir "$JAIL_PROJECTS_BACKING/$_bname" 2>/dev/null || true
      done
    '')

    (add-runtime ''
      # ── Parse CLI arguments ──────────────────────────────────
      JAIL_NAME=""
      JAIL_PROJECTS=()
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --name) [[ $# -ge 2 ]] || { echo "jailed-opencode: --name requires a value" >&2; exit 1; }; JAIL_NAME="$2"; shift 2 ;;
          --) shift; break ;;
          -*) echo "jailed-opencode: unknown option: $1" >&2; exit 1 ;;
          *) JAIL_PROJECTS+=("$(${pkgs.coreutils}/bin/realpath "$1")"); shift ;;
        esac
      done
      while [[ $# -gt 0 ]]; do
        JAIL_PROJECTS+=("$(${pkgs.coreutils}/bin/realpath "$1")"); shift
      done

      # ── Persist-dir prefix (named = isolated, unnamed = shared) ──
      # Backs the writable ~/projects scratch area and direnv allow-state.
      # Named jails get an isolated dir; unnamed jails share one "_shared"
      # dir (kept separate from your real host ~, so the agent can't clobber it).
      if [[ -n "$JAIL_NAME" ]]; then
        JAIL_PERSIST_DIR="$HOME/.local/share/opencode-jails/$JAIL_NAME"
      else
        JAIL_PERSIST_DIR="$HOME/.local/share/opencode-jails/_shared"
      fi
      JAIL_PROJECTS_BACKING="$JAIL_PERSIST_DIR/projects"
      JAIL_DIRENV_DIR="$JAIL_PERSIST_DIR/direnv"
      ${pkgs.coreutils}/bin/mkdir -p "$JAIL_PROJECTS_BACKING" "$JAIL_DIRENV_DIR"

      # ── Project mounting ─────────────────────────────────────
      # ~/projects is always backed by a persistent host dir so scratch work,
      # clones, and generated artifacts survive across sessions. Explicitly
      # passed projects are bind-mounted *on top* at ~/projects/<basename>
      # (bwrap applies binds in order; nested binds layer over the backing dir).
      RUNTIME_ARGS+=(--bind "$JAIL_PROJECTS_BACKING" "$HOME/projects")
      # Persist direnv allow-state so authorized .envrc files stay allowed.
      RUNTIME_ARGS+=(--bind "$JAIL_DIRENV_DIR" "$HOME/.local/share/direnv")
      if [[ ''${#JAIL_PROJECTS[@]} -eq 0 ]]; then
        # No explicit project: work on the current dir (bound at its real path),
        # but keep the persistent ~/projects available for scratch/clones.
        RUNTIME_ARGS+=(--bind "$PWD" "$PWD")
        JAIL_START_DIR="$PWD"
      else
        declare -A SEEN_NAMES
        # Track the mountpoint stubs we ask bwrap to create inside the
        # persistent backing dir, so add-cleanup can remove the (empty) stubs
        # on exit — otherwise every mounted project leaves an empty dir forever.
        JAIL_MOUNTED_BASENAMES=()
        for proj in "''${JAIL_PROJECTS[@]}"; do
          bname=$(${pkgs.coreutils}/bin/basename "$proj")
          if [[ -n "''${SEEN_NAMES[$bname]+x}" ]]; then
            echo "jailed-opencode: duplicate project basename '$bname'" >&2
            echo "  previous: ''${SEEN_NAMES[$bname]}" >&2
            echo "  conflict: $proj" >&2
            exit 1
          fi
          SEEN_NAMES[$bname]="$proj"
          JAIL_MOUNTED_BASENAMES+=("$bname")
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
      # Kill stale host-query from a previous crashed session
      ${pkgs.procps}/bin/fuser -k "$HOST_QUERY_PORT/tcp" 2>/dev/null || true
      ${lib.getExe hostQuery} "$HOST_QUERY_PORT" \
        > "$HOME/.local/state/opencode/host-query.log" 2>&1 &
      HOST_QUERY_PID=$!
      for _ in $(seq 1 20); do
        if ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:$HOST_QUERY_PORT/health" > /dev/null 2>&1; then
          break
        fi
        sleep 0.25
      done
      if ! ${pkgs.curl}/bin/curl -sf "http://127.0.0.1:$HOST_QUERY_PORT/health" > /dev/null 2>&1; then
        echo "WARNING: host-query failed to start (host_exec tool will be unavailable)" >&2
      fi

      # ── State mounting (named = isolated, unnamed = host) ────
      if [[ -n "$JAIL_NAME" ]]; then
        JAIL_DIR="$JAIL_PERSIST_DIR"
        JAIL_STATE_DIR="$HOME/.local/state/opencode-jails/$JAIL_NAME"
        JAIL_CLAUDE_DIR="$JAIL_DIR/claude"
        JAIL_MEM_DIR="$JAIL_DIR/claude-mem"
        JAIL_FISH_DIR="$JAIL_DIR/fish"

        ${pkgs.coreutils}/bin/mkdir -p "$JAIL_CLAUDE_DIR" "$JAIL_STATE_DIR" "$JAIL_MEM_DIR" "$JAIL_FISH_DIR"

        RUNTIME_ARGS+=(--bind "$JAIL_CLAUDE_DIR" "$HOME/.claude")
        RUNTIME_ARGS+=(--bind "$JAIL_DIR" "$HOME/.local/share/opencode")
        RUNTIME_ARGS+=(--bind "$JAIL_STATE_DIR" "$HOME/.local/state/opencode")
        RUNTIME_ARGS+=(--bind "$JAIL_MEM_DIR" "$HOME/.claude-mem")
        RUNTIME_ARGS+=(--bind "$JAIL_FISH_DIR" "$HOME/.local/share/fish")
      else
        ${pkgs.coreutils}/bin/mkdir -p "$HOME/.claude" "$HOME/.local/share/opencode" "$HOME/.local/state/opencode"
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
      if ! curl -sf "http://127.0.0.1:$JAIL_PROXY_PORT/health" > /dev/null 2>&1; then
        echo "FATAL: compat-proxy failed to start (check $PROXY_LOG/compat-proxy.log)" >&2
        exit 1
      fi

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

    # Persist git identity, aliases, and global ignores into the jail.
    # Read-only: the agent gets your config but can't rewrite it to add a
    # remote/credential or change identity. No SSH key or credential helper
    # is ever mounted, so authenticated pushes to real remotes remain
    # impossible — the credential boundary is the enforcement, not config.
    (try-ro-bind (noescape "\"$HOME/.config/git\"") (noescape "~/.config/git"))
    (try-ro-bind (noescape "\"$HOME/.gitignore\"") (noescape "~/.gitignore"))

    (try-rw-bind (noescape "\"$HOME/.config/opencode\"") (noescape "~/.config/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/opencode\"") (noescape "~/.cache/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/uv\"") (noescape "~/.cache/uv"))

    # direnv hook + nix-direnv rc (read-only — agent can't disable the hook).
    # `direnv allow` still works: it writes to ~/.local/share/direnv, which is
    # bind-mounted read-write and persisted (see JAIL_DIRENV_DIR above).
    (ro-bind "${direnvFishHook}" (noescape "~/.config/fish/conf.d/direnv.fish"))
    (ro-bind "${direnvRc}" (noescape "~/.config/direnv/direnvrc"))

    # Persist trash across jail sessions — shared with the host's FreeDesktop trash.
    (add-runtime ''
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/share/Trash"
    '')
    (rw-bind (noescape "\"$HOME/.local/share/Trash\"") (noescape "~/.local/share/Trash"))

    # Shadow coreutils rm/rmdir with trash-backed versions inside the jail.
    # Deferred so it prepends to PATH *after* add-pkg-deps has built it.
    (defer (add-path "${rmSafe}/bin"))
    # Windows VM helper scripts (windows-vm-ssh / windows-vm-scp).
    (defer (add-path "${windowsVmHelpers}/bin"))
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

    (set-env "SHELL" "${upkgs.fish}/bin/fish")
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
