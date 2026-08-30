{
  inputs,
  self,
  upkgs,
  pkgs,
  ...
}:
let
  jail = inputs.jail-nix.lib.init (
    pkgs.extend (
      _: prev: {
        writeShellApplication =
          args:
          prev.writeShellApplication (
            args
            // {
              excludeShellChecks = (args.excludeShellChecks or [ ]) ++ [ "SC2016" ];
            }
          );
      }
    )
  );
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  selfPkgs = self.packages.${system};

  compatProxy = selfPkgs.compat-proxy;

  # Patched opencode (pkgs/opencode) rather than upkgs.opencode directly --
  # its own prompts no longer say "opencode", so the compat-proxy's Claude
  # Code identity spoofing isn't undermined from inside the jail either.
  patchedOpencode = selfPkgs.opencode;

  claudeMem = selfPkgs.claude-mem;
  hostQuery = selfPkgs.host-query;

  # The jail's entire ~/.config/opencode, generated in the store. See
  # config/default.nix for why this is a store path rather than the host's
  # config dir, and why it is mounted as an overlay lower layer.
  opencodeConfig = pkgs.callPackage ./config {
    inherit claudeMem hostQuery lspmuxSession;
    jailContext = ./jail-context.md;
  };

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

  gitSshDeny = pkgs.writeShellScript "git-ssh-denied" ''
    echo "jailed-opencode: git over SSH is disabled inside the sandbox." >&2
    echo "  Commit freely; fetch/push over SSH from the host." >&2
    exit 1
  '';

  # Windows VM helpers — thin wrappers around sshpass+ssh/scp for the local
  # QEMU Windows VM (SSH forwarded to 127.0.0.1:2223). The jail shares the host
  # net namespace, so 127.0.0.1 reaches the same forwarded port as on the host.
  # Args pass straight through, so the caller controls the ssh/scp command line
  # (e.g. the dynamic 'C:/Users/vmadmin.TEMPLATE--XXXX/Desktop/' path).
  # Port/password are hardcoded (non-sensitive, local dev VM).
  windowsVmHelpers =
    let
      vmPort = "2223";
      vmPass = "admin";
      vmUser = "vmadmin";
    in
    pkgs.symlinkJoin {
      name = "windows-vm-helpers";
      paths = [
        (pkgs.writeShellScriptBin "windows-vm-ssh" ''
          exec ${pkgs.sshpass}/bin/sshpass -p ${vmPass} \
            ${pkgs.openssh}/bin/ssh -p ${vmPort} \
            -o StrictHostKeyChecking=no -o WarnWeakCrypto=no -4 \
            ${vmUser}@127.0.0.1 "$@"
        '')
        (pkgs.writeShellScriptBin "windows-vm-scp" ''
          exec ${pkgs.sshpass}/bin/sshpass -p ${vmPass} \
            ${pkgs.openssh}/bin/scp -P ${vmPort} \
            -o StrictHostKeyChecking=no -o WarnWeakCrypto=no -4 \
            "$@"
        '')
      ];
    };

  # Shell helpers shared by the host-side launcher (add-runtime) and the
  # in-jail entrypoint (wrap-entry). Those are two separate scripts, so
  # anything both need has to be injected into both.
  shellHelpers = ''
    # Poll a health endpoint until it answers. Returns non-zero on timeout;
    # the caller decides whether that is fatal.
    #
    # Absolute curl: the host-side launcher runs before the jail's toolbelt
    # PATH exists. The same store path is bound inside the jail, so one
    # definition works for both callers.
    wait_for_health() {
      local url=$1
      local _
      for _ in $(seq 1 20); do
        if ${pkgs.curl}/bin/curl -sf "$url" > /dev/null 2>&1; then
          return 0
        fi
        sleep 0.25
      done
      return 1
    }

    # First free TCP port at or above $1.
    #
    # Ports used to be derived as hash % 200, which silently collided
    # between jails: the loser failed to bind and the session died. Probing
    # keeps the derived port when it is free -- so a restart normally lands
    # on the same one -- and steps past it when it is not.
    pick_port() {
      local port=$1
      local limit=$((port + 200))
      while [ "$port" -lt "$limit" ]; do
        # Subshell so the descriptor is closed for us either way.
        if ! (exec 3<>/dev/tcp/127.0.0.1/"$port") 2>/dev/null; then
          printf '%s' "$port"
          return 0
        fi
        port=$((port + 1))
      done
      echo "jailed-opencode: no free port in $1-$limit" >&2
      return 1
    }
  '';

  lspmux = selfPkgs.lspmux;
  lspmuxSession = selfPkgs.lspmux-session;

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
    export NIX_DIRENV_FALLBACK_NIX=${lib.getExe pkgs.nix}
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
    windowsVmHelpers # windows-vm-ssh / windows-vm-scp

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
    nix

    # Python tooling (uvx needed by claude-mem for chroma vector search)
    uv
    python3

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
    lspmux # LSP multiplexer — `lspmux status` for inspecting instances
    lspmuxSession # lspmux-attach (used by the rust LSP) + lspmux-session

    # Coding agents
    upkgs.claude-code
    patchedOpencode
  ];
in
jail "jailed-opencode" upkgs.fish (
  with jail.combinators;
  [
    network
    time-zone
    no-new-session
    (set-argv [ ])
    (add-cleanup "kill $HOST_QUERY_PID 2>/dev/null || true")

    (add-runtime ''
      ${shellHelpers}

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
      # Backs the writable ~/scratch area and direnv allow-state.
      # Named jails get an isolated dir; unnamed jails share one "_shared"
      # dir (kept separate from your real host ~, so the agent can't clobber it).
      if [[ -n "$JAIL_NAME" ]]; then
        JAIL_PERSIST_DIR="$HOME/.local/share/opencode-jails/$JAIL_NAME"
      else
        JAIL_PERSIST_DIR="$HOME/.local/share/opencode-jails/_shared"
      fi
      JAIL_SCRATCH_BACKING="$JAIL_PERSIST_DIR/scratch"
      JAIL_DIRENV_DIR="$JAIL_PERSIST_DIR/direnv"
      # ~/scratch was called ~/projects before projects moved to their real
      # paths. Carry the old backing dir over rather than orphaning it.
      if [[ -d "$JAIL_PERSIST_DIR/projects" && ! -e "$JAIL_SCRATCH_BACKING" ]]; then
        ${pkgs.coreutils}/bin/mv "$JAIL_PERSIST_DIR/projects" "$JAIL_SCRATCH_BACKING"
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$JAIL_SCRATCH_BACKING" "$JAIL_DIRENV_DIR"

      # ── Project mounting ─────────────────────────────────────
      # Projects are bound at their *real host path*, not remapped under a
      # jail-local directory.
      #
      # This is load-bearing for anything that talks to a host process about
      # files. LSP is the sharp case: lspmux lets an in-jail client join the
      # rust-analyzer the host's neovim already started, but it initializes the
      # server from the *first* client's InitializeParams and discards later
      # ones. A joining client whose files live under a different prefix is
      # therefore describing paths the server was never told about -- they
      # belong to no crate, so it gets no diagnostics, no hover, nothing.
      # Identical paths also make file references in agent output directly
      # usable on the host.
      #
      # ~/scratch stays backed by a persistent host dir so throwaway clones and
      # generated artifacts survive across sessions.
      RUNTIME_ARGS+=(--bind "$JAIL_SCRATCH_BACKING" "$HOME/scratch")
      # Persist direnv allow-state so authorized .envrc files stay allowed.
      RUNTIME_ARGS+=(--bind "$JAIL_DIRENV_DIR" "$HOME/.local/share/direnv")

      # ~/workspaces holds git worktrees, bound at its real host path and
      # shared (unlike ~/scratch) across every jail, named or not -- a
      # worktree created in one session should be usable from the host and
      # from any other session immediately, not siloed per jail name. Because
      # the whole directory is bound, worktrees created *inside* it become
      # visible to the jail automatically; they don't need to be passed as
      # explicit projects or require a jail restart.
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/workspaces"
      RUNTIME_ARGS+=(--bind "$HOME/workspaces" "$HOME/workspaces")

      if [[ ''${#JAIL_PROJECTS[@]} -eq 0 ]]; then
        # No explicit project: work on the current dir.
        RUNTIME_ARGS+=(--bind "$PWD" "$PWD")
        JAIL_START_DIR="$PWD"
      else
        for proj in "''${JAIL_PROJECTS[@]}"; do
          RUNTIME_ARGS+=(--bind "$proj" "$proj")
        done
        # opencode is single-root: it can only browse (@-complete, index) files
        # under one directory. With multiple projects, root at their deepest
        # common ancestor so all of them show up as siblings under it, rather
        # than at the first project (which would hide the rest entirely).
        JAIL_START_DIR="''${JAIL_PROJECTS[0]}"
        if [[ ''${#JAIL_PROJECTS[@]} -gt 1 ]]; then
          common="''${JAIL_PROJECTS[0]}"
          for proj in "''${JAIL_PROJECTS[@]:1}"; do
            while [[ "$common" != "/" && "$proj" != "$common" && "$proj" != "$common"/* ]]; do
              common="''${common%/*}"
              [[ -z "$common" ]] && common="/"
            done
          done
          if [[ "$common" == "/" ]]; then
            echo "jailed-opencode: projects share no common ancestor above /:" >&2
            printf '  %s\n' "''${JAIL_PROJECTS[@]}" >&2
            exit 1
          fi
          JAIL_START_DIR="$common"
          # opencode only indexes up to 100k files under a non-git root (it
          # falls back to `project.directory = "/"` internally when the root
          # itself isn't a repo, which also breaks relative path display and
          # .gitignore lookup) -- so a shared ancestor above all your repos is
          # a known-inferior fallback, not a fully-supported setup. Loud rather
          # than silently degraded.
          if [[ ! -e "$JAIL_START_DIR/.git" ]]; then
            echo "jailed-opencode: warning: shared root $JAIL_START_DIR is not a git repo" >&2
            echo "  opencode's file index and .gitignore handling degrade outside a repo root" >&2
          fi
        fi
      fi

      # ── Port allocation ──────────────────────────────────────
      # Seeded from the jail identity so a given jail keeps its ports across
      # restarts, then probed so two jails can never fight over one.
      if [[ -n "$JAIL_NAME" ]]; then
        PORT_SEED="$JAIL_NAME"
      else
        PORT_SEED="''${JAIL_PROJECTS[0]:-$PWD}"
      fi
      PORT_HASH=$(echo "$PORT_SEED" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/head -c7)
      PORT_OFFSET=$((16#''${PORT_HASH:0:4} % 200))
      JAIL_PROXY_PORT=$(pick_port $((18800 + PORT_OFFSET)))
      JAIL_MEM_PORT=$(pick_port $((19200 + PORT_OFFSET)))
      HOST_QUERY_PORT=$(pick_port $((19600 + PORT_OFFSET)))

      # ── Host-query service (runs on host, outside jail) ──────
      # Its log goes to this jail's own state dir, not the host's
      # ~/.local/state/opencode -- that path is the *jail's* state once bound,
      # and writing there from the host side would be the last thing putting
      # agent state outside a jail-owned directory.
      if [[ -n "$JAIL_NAME" ]]; then
        JAIL_STATE_DIR="$HOME/.local/state/opencode-jails/$JAIL_NAME"
      else
        JAIL_STATE_DIR="$HOME/.local/state/opencode-jails/_shared"
      fi
      ${pkgs.coreutils}/bin/mkdir -p "$JAIL_STATE_DIR"
      ${lib.getExe hostQuery} "$HOST_QUERY_PORT" \
        > "$JAIL_STATE_DIR/host-query.log" 2>&1 &
      HOST_QUERY_PID=$!
      if ! wait_for_health "http://127.0.0.1:$HOST_QUERY_PORT/health"; then
        echo "jailed-opencode: warning: host-query failed to start on port $HOST_QUERY_PORT" >&2
        echo "  the host_exec tool will be unavailable this session" >&2
      fi

      # ── State mounting (all jail-owned, nothing from the host) ────
      # Named and unnamed jails differ only in *which* persist dir they use:
      # a named one gets its own, unnamed ones share "_shared" (the same
      # identity that already backs their ~/scratch and direnv state). Neither
      # reads or writes the host's ~/.claude, ~/.claude.json or
      # ~/.local/share/opencode -- the host holds no agent state at all.
      #
      # This is also where credentials live. compat-proxy only *reads* tokens
      # (creds.rs: "no caching, no refresh logic") and errors on expiry, so the
      # refresh has to come from the `claude` CLI in the jail's own toolbelt,
      # writing to the .credentials.json below. That means one `claude /login`
      # per jail identity -- once for _shared, once per named jail.
      JAIL_DIR="$JAIL_PERSIST_DIR"
      JAIL_CLAUDE_DIR="$JAIL_DIR/claude"
      JAIL_MEM_DIR="$JAIL_DIR/claude-mem"
      JAIL_FISH_DIR="$JAIL_DIR/fish"
      # JAIL_STATE_DIR was computed above, for the host-query log.

      ${pkgs.coreutils}/bin/mkdir -p "$JAIL_CLAUDE_DIR" "$JAIL_MEM_DIR" "$JAIL_FISH_DIR"

      # .claude.json carries `oauthAccount.accountUuid`, which compat-proxy
      # reads for the `metadata.user_id` field real Claude Code sends. It is
      # created by the first in-jail `claude` login; until then requests simply
      # omit the field (main.rs warns and continues). Bound only if present so
      # a fresh jail doesn't fail on a missing file.
      [ -f "$JAIL_DIR/claude.json" ] && RUNTIME_ARGS+=(--bind "$JAIL_DIR/claude.json" "$HOME/.claude.json")

      # opencode must not hold its own anthropic OAuth token in here. The
      # compat-proxy is what supplies credentials, so an `oauth` entry is
      # redundant -- but worse, it is silently destructive: native-runtime.ts
      # refuses to run the native LLM path under OAuth auth ("OAuth auth
      # requires a provider fetch override") and falls back to the AI SDK,
      # which is the *only* path the Claude Code tool-name aliasing patch
      # (pkgs/opencode) hooks. Requests then go out naming opencode's own
      # tools -- `todowrite` alone is enough -- and Anthropic rejects them
      # with a quota-shaped "You're out of extra usage" error that has
      # nothing to do with quota. Swapped for the same dummy api key the
      # generated config already sets, since the proxy ignores it either way.
      AUTH_JSON="$JAIL_DIR/auth.json"
      if [ -f "$AUTH_JSON" ] \
        && [ "$(${pkgs.jq}/bin/jq -r '.anthropic.type // ""' "$AUTH_JSON")" = "oauth" ]; then
        ${pkgs.coreutils}/bin/cp "$AUTH_JSON" "$AUTH_JSON.oauth.bak"
        if ${pkgs.jq}/bin/jq '.anthropic = {"type":"api","key":"not-needed"}' \
            "$AUTH_JSON" > "$AUTH_JSON.tmp"; then
          ${pkgs.coreutils}/bin/mv "$AUTH_JSON.tmp" "$AUTH_JSON"
          echo "jailed-opencode: replaced stale anthropic OAuth auth in $AUTH_JSON" >&2
          echo "  (it disables opencode's native LLM runtime; backup at $AUTH_JSON.oauth.bak)" >&2
        else
          ${pkgs.coreutils}/bin/rm -f "$AUTH_JSON.tmp"
          echo "jailed-opencode: warning: could not rewrite $AUTH_JSON" >&2
        fi
      fi

      # No credentials yet: say so up front rather than letting the first
      # request fail with a 503 from the proxy.
      if [ ! -f "$JAIL_CLAUDE_DIR/.credentials.json" ]; then
        echo "jailed-opencode: no credentials in $JAIL_CLAUDE_DIR" >&2
        echo "  run 'claude /login' inside the jail once to authenticate this jail identity" >&2
      fi

      RUNTIME_ARGS+=(--bind "$JAIL_CLAUDE_DIR" "$HOME/.claude")
      RUNTIME_ARGS+=(--bind "$JAIL_DIR" "$HOME/.local/share/opencode")
      RUNTIME_ARGS+=(--bind "$JAIL_STATE_DIR" "$HOME/.local/state/opencode")
      RUNTIME_ARGS+=(--bind "$JAIL_MEM_DIR" "$HOME/.claude-mem")
      RUNTIME_ARGS+=(--bind "$JAIL_FISH_DIR" "$HOME/.local/share/fish")

      if [[ -r "$HOME/.ssh/id_ed25519_signing" ]]; then
        RUNTIME_ARGS+=(--ro-bind "$HOME/.ssh/id_ed25519_signing" "$HOME/.ssh/id_ed25519_signing")
        RUNTIME_ARGS+=(--ro-bind "$HOME/.ssh/id_ed25519_signing.pub" "$HOME/.ssh/id_ed25519_signing.pub")
      fi
      RUNTIME_ARGS+=(--setenv GIT_CONFIG_COUNT 1)
      RUNTIME_ARGS+=(--setenv GIT_CONFIG_KEY_0 core.sshCommand)
      RUNTIME_ARGS+=(--setenv GIT_CONFIG_VALUE_0 "${gitSshDeny}")

      # ── Pass computed values into the jail ───────────────────
      RUNTIME_ARGS+=(--setenv JAIL_PROXY_PORT "$JAIL_PROXY_PORT")
      RUNTIME_ARGS+=(--setenv JAIL_MEM_PORT "$JAIL_MEM_PORT")
      RUNTIME_ARGS+=(--setenv HOST_QUERY_PORT "$HOST_QUERY_PORT")
      RUNTIME_ARGS+=(--setenv JAIL_START_DIR "$JAIL_START_DIR")
      RUNTIME_ARGS+=(--setenv JAIL_NAME "''${JAIL_NAME:-}")
    '')

    (wrap-entry (entry: ''
      ${shellHelpers}

      LOG_DIR="$HOME/.local/state/opencode"
      mkdir -p "$LOG_DIR"

      # Full request/response capture, opt-in via COMPAT_PROXY_DUMP=1.
      # The shaped body that actually goes upstream is the only reliable
      # thing to debug against -- reconstructing it by hand has repeatedly
      # produced requests that behave differently from the real ones.
      PROXY_DUMP_ARGS=()
      if [[ -n "''${COMPAT_PROXY_DUMP:-}" ]]; then
        PROXY_DUMP_ARGS+=(--dump-dir "$LOG_DIR/dumps")
      fi

      ${lib.getExe compatProxy} \
        --credentials-path "$HOME/.claude/.credentials.json" \
        --port "$JAIL_PROXY_PORT" \
        --max-tokens 64000 \
        "''${PROXY_DUMP_ARGS[@]}" \
        --log-level "''${COMPAT_PROXY_LOG:-info}" \
        > "$LOG_DIR/compat-proxy.log" 2>&1 &
      PROXY_PID=$!
      trap 'kill $PROXY_PID 2>/dev/null || true' EXIT

      # Fatal: without the proxy there are no credentials, so every request
      # would fail with a 503 that is far less legible than this.
      if ! wait_for_health "http://127.0.0.1:$JAIL_PROXY_PORT/health"; then
        echo "jailed-opencode: FATAL: compat-proxy failed to start" >&2
        echo "  see $LOG_DIR/compat-proxy.log" >&2
        exit 1
      fi

      export OPENCODE_PROXY_URL="http://127.0.0.1:$JAIL_PROXY_PORT/v1"

      # Routes requests through packages/llm instead of the AI SDK -- the
      # code path the Claude-Code tool-name aliasing patch (pkgs/opencode
      # postPatch) actually runs on. home.sessionVariables doesn't cross
      # the bwrap boundary, so this has to be set here too.
      export OPENCODE_EXPERIMENTAL_NATIVE_LLM=1

      CLAUDE_MEM_WORKER_PORT=$JAIL_MEM_PORT \
      CLAUDE_MEM_WORKER_HOST=127.0.0.1 \
      CLAUDE_MEM_DATA_DIR="$HOME/.claude-mem" \
        ${lib.getExe claudeMem} > "$LOG_DIR/claude-mem.log" 2>&1 &
      CLAUDE_MEM_PID=$!
      trap 'kill $PROXY_PID $CLAUDE_MEM_PID 2>/dev/null || true' EXIT

      # Non-fatal: memory search degrades, the session still works.
      if ! wait_for_health "http://127.0.0.1:$JAIL_MEM_PORT/api/health"; then
        echo "jailed-opencode: warning: claude-mem failed to start on port $JAIL_MEM_PORT" >&2
        echo "  memory search will be unavailable; see $LOG_DIR/claude-mem.log" >&2
      fi

      export CLAUDE_MEM_WORKER_PORT=$JAIL_MEM_PORT

      cd "$JAIL_START_DIR"
      ${entry}
    ''))

    (try-ro-bind (noescape "\"$HOME/.config/git\"") (noescape "~/.config/git"))
    (try-ro-bind (noescape "\"$HOME/.gitignore\"") (noescape "~/.gitignore"))

    # ~/.config/opencode is generated (pkgs/opencode-bubblewrap/config), not
    # the host's. A tmpfs overlay rather than a plain ro-bind because opencode
    # writes into its own config dir on every start and cannot be told not to
    # -- .gitignore via ensureGitignore, and package.json/bun.lock/node_modules
    # from the background `@opencode-ai/plugin` install. Those land in the
    # upper layer and are discarded at session end, so config state can never
    # accumulate across sessions.
    (overlay-tmp [ "${opencodeConfig}" ] (noescape "~/.config/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/opencode\"") (noescape "~/.cache/opencode"))
    (try-rw-bind (noescape "\"$HOME/.cache/uv\"") (noescape "~/.cache/uv"))

    # Package-manager caches, shared read-write with the host so a session
    # doesn't start cold and re-download everything into a tmpfs it then throws
    # away. All of these are content-addressed or checksum-verified, so a
    # corrupted entry is re-fetched rather than silently trusted.
    #
    # Note this is ~/.cargo/registry rather than ~/.cargo: there is no
    # credentials file there today, but `cargo login` writes a crates.io token
    # to ~/.cargo/credentials.toml, and binding the subdirectory keeps that
    # permanently out of the jail's reach. ~/.rustup is deliberately absent --
    # toolchains come from the devshell.
    (try-rw-bind (noescape "\"$HOME/.cargo/registry\"") (noescape "~/.cargo/registry"))
    (try-rw-bind (noescape "\"$HOME/.cargo/git\"") (noescape "~/.cargo/git"))
    (try-rw-bind (noescape "\"$HOME/.cache/nix\"") (noescape "~/.cache/nix"))
    (try-rw-bind (noescape "\"$HOME/.local/share/pnpm\"") (noescape "~/.local/share/pnpm"))
    (try-rw-bind (noescape "\"$HOME/.npm\"") (noescape "~/.npm"))
    (try-rw-bind (noescape "\"$HOME/.bun\"") (noescape "~/.bun"))

    # lspmux client config (read-only). Without it the in-jail client falls back
    # to the default `pass_environment = ["*"]`, which drags jail-specific vars
    # (JAIL_NAME, derived ports, the injected system prompt) into the instance
    # fingerprint — so every session with different ports mints a fresh
    # rust-analyzer instead of reusing one.
    (try-ro-bind (noescape "\"$HOME/.config/lspmux\"") (noescape "~/.config/lspmux"))

    # Named lspmux sessions (read-only), so a jailed agent can *join* the same
    # rust-analyzer the host's neovim is using instead of spawning its own.
    #
    # Three things have to line up for the instance key to match across the
    # sandbox boundary, and they do:
    #   * `server` — the wrapper path, which hangs off HOME (identical here) and
    #     is exec'd by the host lspmux server, so it must resolve host-side.
    #   * `env` — `lspmux-attach` re-execs under `env -i`, so JAIL_NAME and the
    #     derived ports can't leak into the fingerprint no matter what.
    #   * `workspace_root` — compared by (device, inode), and projects are bound
    #     at their real host path anyway, so both spellings agree.
    #
    # Matching the instance key is necessary but not sufficient: the server is
    # initialized from the first client's InitializeParams and later ones are
    # discarded, so a joining client must also *name* its files the way the
    # first one did. That is why projects are mounted at their real paths.
    #
    # Read-only because a session saved in here would snapshot the jail's
    # toolbelt PATH, which is useless to the host server that has to run it.
    # Note the wrappers contain the snapshotted devshell environment, so
    # anything in the lspmux env allowlist is readable by the agent.
    (add-runtime ''
      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/state/lspmux"
    '')
    (ro-bind (noescape "\"$HOME/.local/state/lspmux\"") (noescape "~/.local/state/lspmux"))

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
    # Shadow coreutils rm/rmdir with trash-backed versions inside the jail.
    # Deferred so it prepends to PATH *after* add-pkg-deps has built it --
    # this is the one entry that has to win against a toolbelt name.
    (defer (add-path "${rmSafe}/bin"))
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
    (try-fwd-env "COMPAT_PROXY_DUMP")
    (try-fwd-env "COMPAT_PROXY_UPSTREAM")
    (try-fwd-env "NIX_PATH")
    # Selects which named lspmux session the in-jail rust LSP joins, e.g.
    # `LSPMUX_SESSION=windows jailed-opencode ~/integrations-mono`.
    (try-fwd-env "LSPMUX_SESSION")
    # MCP server credentials, read out of the config by opencode's {env:...}
    # substitution. Sourced from sops via the shell environment on the host;
    # without these forwards the context7 and figma servers silently fail to
    # authenticate inside the jail.
    (try-fwd-env "CONTEXT7_API_KEY")
    (set-env "NIX_REMOTE" "daemon")

    (add-pkg-deps (
      agentToolbelt
      ++ [
        compatProxy
        claudeMem
      ]
    ))
  ]
)
