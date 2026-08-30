# Named lspmux sessions.
#
# lspmux keys each language server instance on (server, args, env,
# workspace_root) and reuses an instance only when all four match exactly.
# Matching on `env` means a ~60-variable devshell environment has to agree
# byte-for-byte between editors, which it does only by coincidence.
#
# These two commands invert that. A *session* is a saved wrapper script that
# restores a snapshotted devshell environment and execs the language server:
#
#   lspmux-session save windows    # once, from inside the cross devshell
#   LSPMUX_SESSION=windows nvim    # any number of editors, any terminal
#
# `lspmux-attach` runs the client under `env -i`, so the environment it
# forwards is a fixed three variables. The real environment travels inside the
# wrapper named by `server`. Instance identity therefore reduces to
# (session name, workspace root) and collisions become deterministic.
{
  lib,
  pkgs,
  writeShellApplication,
  symlinkJoin,
  bash,
  coreutils,
  jq,
  git,
}:
let
  lspmux = pkgs.callPackage ../lspmux { };
  lspmuxBin = lib.getExe lspmux;
  jqBin = lib.getExe jq;
  gitBin = lib.getExe git;

  # Environment visible to spawned language servers.
  #
  # Used in two places:
  #
  #   1. `pass_environment` in the generated lspmux config, which filters what a
  #      plain `lspmux client` sends. This is the fallback path, used by
  #      projects with no saved session.
  #   2. The filter `lspmux-session save` applies when snapshotting a devshell
  #      into a session wrapper.
  #
  # It is an allowlist rather than ["*" "!VOLATILE_*"] because a nix devshell
  # environment routinely contains sops-provided API keys, and (2) writes its
  # result to a file under ~/.local/state -- which is also mounted into the
  # opencode sandbox, where an agent can read it. Anything matched here ends up
  # in the language server's environment, on disk, and visible to the agent, so
  # weigh additions with all three in mind.
  #
  # Note this list no longer controls *instance identity* for sessions. Session
  # clients contribute a fixed env and carry their real environment inside the
  # wrapper script, so entries here can no longer cause instance fragmentation.
  # Vars that differ per terminal (WAYLAND_DISPLAY, STARSHIP_SESSION_KEY, ...)
  # still fragment the fallback path, though, so the old rule holds there.
  #
  # Patterns are globs; a leading "!" negates. Matching is "at least one
  # positive and no negatives", so negatives always win regardless of order.
  envAllowlist = [
    # Identifies the session on the wire. Redundant for identity (the wrapper
    # path in `server` already does that) but makes `lspmux status` readable.
    "LSPMUX_SESSION"

    # Basic runtime
    "HOME"
    "PATH"
    "CONFIG_SHELL"
    "SOURCE_DATE_EPOCH"

    # Rust / Cargo. CARGO_* also covers the per-triple
    # CARGO_TARGET_<TRIPLE>_{LINKER,RUSTFLAGS,RUNNER} overrides that cross
    # devshells set, which cross-target rust-analyzer instances need.
    #
    # CARGO_TARGET_DIR is excluded on purpose: rust-analyzer has its own
    # targetDir (see lib/rust-analyzer-settings.nix) and must not share a build
    # directory with interactive cargo invocations.
    "CARGO_*"
    "!CARGO_TARGET_DIR"
    "RUSTFLAGS"
    "RUSTUP_HOME"
    "RUST_SRC_PATH"

    # Read by `lspmux-session save` to seed the session's recorded cargo target
    # when CARGO_BUILD_TARGET isn't set. Kept in the allowlist so it lands in
    # the snapshot too.
    "RA_TARGET"

    "SQLX_OFFLINE"
    "DATABASE_URL"

    # Native toolchain
    "CC"
    "CXX"
    "AR"
    "AS"
    "LD"
    "RANLIB"
    "NM"
    "OBJCOPY"
    "OBJDUMP"
    "READELF"
    "STRIP"
    "SIZE"
    "STRINGS"

    "CFLAGS"
    "CXXFLAGS"
    "CPPFLAGS"
    "LDFLAGS"
    "CL_FLAGS"

    # Per-triple compiler/flag overrides, e.g. CC_x86_64_pc_windows_gnu,
    # CFLAGS_x86_64_pc_windows_gnu. Deliberately no "LD_*" glob -- it would
    # match LD_PRELOAD; LD_LIBRARY_PATH is listed explicitly below.
    "CC_*"
    "CXX_*"
    "CFLAGS_*"
    "CXXFLAGS_*"
    "LDFLAGS_*"
    "AR_*"
    "RANLIB_*"
    "WINDRES*"
    "DLLTOOL*"

    # Build-platform counterparts (CC_FOR_BUILD, AR_FOR_BUILD,
    # NIX_CFLAGS_COMPILE_FOR_BUILD, ...) set by cross stdenvs.
    "*_FOR_BUILD"
    "HOST_CC"
    "HOST_PATH"

    "PKG_CONFIG"
    "PKG_CONFIG_PATH"
    "PKG_CONFIG_LIBDIR"
    "PKG_CONFIG_SYSROOT_DIR"

    "CMAKE_INCLUDE_PATH"
    "CMAKE_LIBRARY_PATH"
    "NIXPKGS_CMAKE_PREFIX_PATH"

    "LD_LIBRARY_PATH"
    "NIX_LD"
    "NIX_LD_LIBRARY_PATH"

    "NIX_CC"
    "NIX_BINTOOLS"
    "NIX_CFLAGS_COMPILE"
    "NIX_LDFLAGS"
    "NIX_HARDENING_ENABLE"
    "NIX_ENFORCE_NO_NATIVE"

    # Wrapper setup markers. Globbed rather than pinned to a single triple so
    # cross devshells' _BUILD_ variants (e.g. ..._TARGET_BUILD_x86_64_w64_mingw32)
    # come along too -- without them the cc wrapper skips its flag injection.
    "NIX_CC_WRAPPER_TARGET_*"
    "NIX_BINTOOLS_WRAPPER_TARGET_*"
    "NIX_PKG_CONFIG_WRAPPER_TARGET_*"

    "NIX_STORE"
    "NIX_SSL_CERT_FILE"
    "NIX_PATH"
    "NIX_PROFILES"
    "NIX_USER_PROFILE_DIR"
    "IN_NIX_SHELL"

    # Project build scripts (AWS-LC, windows DLL staging)
    "AWS_LC_SYS_PREBUILT_NASM"
    "LINK_DLL_FOLDERS"
  ];

  positivePatterns = lib.filter (p: !(lib.hasPrefix "!" p)) envAllowlist;
  negativePatterns = map (lib.removePrefix "!") (lib.filter (lib.hasPrefix "!") envAllowlist);
  shellArray = name: items: "${name}=(${lib.concatMapStringsSep " " lib.escapeShellArg items})";

  # Derived from HOME alone, deliberately ignoring XDG_STATE_HOME.
  #
  # This path is simultaneously part of the instance key (as `server`) and a
  # path the lspmux server must exec -- and the server may be running outside
  # the mount namespace of the client that named it, as when jailed opencode
  # attaches to a session created on the host. HOME is the only variable
  # guaranteed to agree across that boundary, so the store hangs off it.
  sessionsDirExpr = ''sessions_dir="$HOME/.local/state/lspmux/sessions"'';

  # How a directory maps to the sessions saved for it. Shared by both commands.
  #
  # Sessions live at $sessions_dir/<repo-basename>@<inode>/<name>/, so a session
  # name only has to be unique within its repository.
  #
  # The inode is the key because it is stable across reboots and identical
  # through the opencode sandbox's bind mount, where the path is not. The
  # basename keeps the store legible and separates distinct worktrees. The
  # device number is deliberately *not* part of the key even though lspmux
  # itself compares (device, inode): /home is btrfs, whose anonymous block
  # device numbers are reassigned on every mount, so a persisted one goes stale
  # on the next reboot. lspmux only holds them in memory, so it doesn't care.
  rootHelpers = ''
    # Git toplevel rather than the cargo workspace root: sessions are selected
    # per repository, so every subdirectory must resolve to the same key.
    #
    # A linked worktree has its own toplevel, so --show-toplevel alone would
    # give every worktree a distinct, session-less key. Resolve through
    # --git-common-dir instead: it points at the *main* checkout's .git both
    # from the main checkout and from any of its worktrees, so they all land
    # on the same root and share saved sessions. Bare repos and other odd
    # GIT_DIR layouts fall back to --show-toplevel.
    repo_root() {
      local dir root common main
      dir=''${1:-$PWD}
      common=$(cd "$dir" && ${gitBin} rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
      main=''${common%/.git}
      if [ -n "$common" ] && [ "$main" != "$common" ] && [ -d "$main" ]; then
        root=$main
      else
        root=$(cd "$dir" && ${gitBin} rev-parse --show-toplevel 2>/dev/null) || root=$dir
      fi
      (cd "$root" && pwd -P)
    }

    root_slug() {
      local root=$1
      local ino base
      ino=$(${coreutils}/bin/stat -Lc %i "$root") || return 1
      base=''${root##*/}
      base=''${base//[^A-Za-z0-9._-]/_}
      [ -n "$base" ] || base=root
      printf '%s@%s' "$base" "$ino"
    }

    # Directory holding this repository's sessions, empty status if none yet.
    group_dir() {
      local root=$1
      local slug dir meta
      slug=$(root_slug "$root") || return 1
      dir="$sessions_dir/$slug"
      if [ -d "$dir" ]; then
        printf '%s' "$dir"
        return 0
      fi
      # Inode changed -- the repo was deleted and recreated, or restored from a
      # backup. Fall back to the recorded path. `save` and `use` rename the
      # directory to match, so this only has to hold until the next write.
      for meta in "$sessions_dir"/*/*/meta.json; do
        [ -e "$meta" ] || continue
        if [ "$(${jqBin} -r '.root' "$meta")" = "$root" ]; then
          printf '%s' "''${meta%/*/meta.json}"
          return 0
        fi
      done
      return 1
    }

    # Name of the session most recently selected for a group directory.
    current_session() {
      local dir=$1
      local meta line
      local lines=() sorted=()
      for meta in "$dir"/*/meta.json; do
        [ -e "$meta" ] || continue
        line=$(${jqBin} -r '[(.selected_at // 0), .name] | @tsv' "$meta") || continue
        lines+=("$line")
      done
      [ ''${#lines[@]} -gt 0 ] || return 1
      mapfile -t sorted < <(printf '%s\n' "''${lines[@]}" | LC_ALL=C ${coreutils}/bin/sort -rn)
      printf '%s' "''${sorted[0]#*$'\t'}"
    }
  '';

  lspmux-attach = writeShellApplication {
    name = "lspmux-attach";
    text = ''
      # Spawned by the editor in place of the language server binary.
      #
      # lspmux keys instances on (server, args, env, workspace_root). With a
      # session selected we re-exec `lspmux client` under `env -i` so the env it
      # forwards is byte-identical from every terminal -- and from inside the
      # opencode sandbox -- and point --server-path at the session wrapper,
      # which carries the real devshell environment internally.
      #
      # Which session that is comes from the repository containing $PWD, not
      # from the environment: the whole point is that two editors opening the
      # same repo agree without either being told anything. LSPMUX_SESSION is
      # only an override for one-off invocations.
      #
      # With no session at all, fall through to a plain client using the ambient
      # environment, filtered by `pass_environment` as before.
      ${sessionsDirExpr}
      ${rootHelpers}

      root=$(repo_root)
      group=$(group_dir "$root") || group=""

      name=""
      if [ -n "''${LSPMUX_SESSION:-}" ]; then
        if [ -n "$group" ] && [ -d "$group/''${LSPMUX_SESSION}" ]; then
          name=$LSPMUX_SESSION
        else
          # Not fatal: LSPMUX_SESSION tends to get exported once and then
          # inherited by every editor started from that shell, including ones
          # opening unrelated repositories. Warn and let the repo decide.
          echo "lspmux-attach: LSPMUX_SESSION='$LSPMUX_SESSION' has no session in $root -- ignoring it" >&2
        fi
      fi

      if [ -z "$name" ] && [ -n "$group" ]; then
        name=$(current_session "$group") || name=""
      fi

      if [ -z "$name" ]; then
        # Loud, because a silent fallback here is indistinguishable from the
        # multiplexing being broken -- you get a second language server and no
        # hint as to why.
        echo "lspmux-attach: no lspmux session for $root -- starting a private language server with the ambient environment. Create one with 'lspmux-session save NAME'." >&2
        exec ${lspmuxBin} client "$@"
      fi

      wrapper="$group/$name/server"
      if [ ! -x "$wrapper" ]; then
        echo "lspmux-attach: session '$name' for $root has no wrapper (re-run 'lspmux-session save $name -f')" >&2
        exit 1
      fi

      # lspmux must be an absolute path here: after `env -i` there is no PATH
      # left for env(1) to resolve a bare name against.
      #
      # XDG_CONFIG_HOME is forwarded because the client reads its own
      # config.toml to find the server socket. It is passed unconditionally,
      # defaulted the same way the `directories` crate would: leaving it out
      # when unset would make a host that exports it (as a systemd user
      # environment does) disagree with a sandbox that doesn't, splitting one
      # session into two instances.
      exec env -i \
        HOME="$HOME" \
        XDG_CONFIG_HOME="''${XDG_CONFIG_HOME:-$HOME/.config}" \
        LSPMUX_SESSION="$name" \
        ${lspmuxBin} client --server-path "$wrapper" "$@"
    '';
  };

  lspmux-session = writeShellApplication {
    name = "lspmux-session";
    text = ''
      ${sessionsDirExpr}
      ${rootHelpers}

      # Mirrors `pass_environment` from the lspmux config.
      ${shellArray "positive" positivePatterns}
      ${shellArray "negative" negativePatterns}

      die() {
        echo "lspmux-session: $*" >&2
        exit 1
      }

      usage() {
        echo "usage: lspmux-session <command> [args]"
        echo
        echo "  Sessions belong to the git repository they were saved in, and"
        echo "  the editor picks one automatically. You only need to name one"
        echo "  to switch between them, e.g. between build targets."
        echo
        echo "  save NAME [-f] [--server BIN] [--target TRIPLE]"
        echo "        Snapshot the current environment into a session wrapper"
        echo "        and select it. Run this from inside the devshell the"
        echo "        language server should see."
        echo "  use NAME    Select NAME for this repository."
        echo "  ls          List sessions; '*' marks the one selected here."
        echo "  show NAME   Print the session's wrapper script."
        echo "  rm NAME     Delete a session."
        echo "  kill NAME   Kill the running language server for a session."
        exit "''${1:-2}"
      }

      check_name() {
        case "$1" in
          "" | . | .. | */*) die "invalid session name: '$1'" ;;
        esac
      }

      # The session store is bind-mounted read-only into the opencode sandbox,
      # so mutating subcommands are reachable but cannot work there. Fail with
      # an explanation rather than a bare EROFS from mkdir/rm.
      require_writable() {
        local probe="$sessions_dir"
        while [ ! -e "$probe" ] && [ "$probe" != "/" ]; do
          probe=''${probe%/*}
          [ -n "$probe" ] || probe=/
        done
        [ -w "$probe" ] || die "session store is read-only here ($probe) -- sessions must be created on the host, not inside a sandbox"
      }

      env_allowed() {
        local name=$1 pat
        for pat in "''${negative[@]}"; do
          # shellcheck disable=SC2053 # unquoted RHS is a glob match, on purpose
          if [[ $name == $pat ]]; then return 1; fi
        done
        for pat in "''${positive[@]}"; do
          # shellcheck disable=SC2053
          if [[ $name == $pat ]]; then return 0; fi
        done
        return 1
      }

      # PID of the running instance for a session wrapper, empty if none.
      instance_pid() {
        local status
        status=$(${lspmuxBin} status --json 2>/dev/null) || return 0
        printf '%s' "$status" \
          | ${jqBin} -r --arg w "$1" 'first(.instances[] | select(.server == $w) | .pid) // ""'
      }

      # Mark a session as the one this repository should use. Ordering by
      # timestamp rather than a pointer file because a pointer would have to be
      # *named* after the repo, and no naming scheme is both stable across
      # reboots and identical inside the sandbox -- see rootHelpers.
      select_session() {
        local meta=$1
        local tmp="$meta.tmp"
        # Milliseconds: two saves in the same second would otherwise tie, and
        # the tiebreak is whatever `sort` does with the name. Not nanoseconds --
        # jq carries numbers as doubles, and 19 digits would lose precision and
        # reintroduce the tie.
        ${jqBin} --argjson now "$(${coreutils}/bin/date +%s%3N)" '.selected_at = $now' "$meta" > "$tmp"
        ${coreutils}/bin/mv -f "$tmp" "$meta"
      }

      # The group directory for $PWD's repository, renamed first if the repo's
      # inode changed since the sessions were saved.
      group_dir_healed() {
        local root=$1
        local slug dir want
        slug=$(root_slug "$root") || return 1
        dir=$(group_dir "$root") || return 1
        want="$sessions_dir/$slug"
        if [ "$dir" != "$want" ]; then
          ${coreutils}/bin/mv -T "$dir" "$want"
          dir=$want
        fi
        printf '%s' "$dir"
      }

      # Resolve NAME to a session directory: the repository containing $PWD
      # first, then a unique match anywhere, so `rm`/`kill` still work from
      # outside the tree.
      resolve_session() {
        local name=$1
        local root group d
        local hits=()
        root=$(repo_root)
        if group=$(group_dir "$root"); then
          if [ -d "$group/$name" ]; then
            printf '%s' "$group/$name"
            return 0
          fi
        fi
        for d in "$sessions_dir"/*/"$name"; do
          [ -d "$d" ] || continue
          hits+=("$d")
        done
        case ''${#hits[@]} in
          0) return 1 ;;
          1) printf '%s' "''${hits[0]}"; return 0 ;;
          *) die "session '$name' exists in several repositories; cd into the one you mean" ;;
        esac
      }

      cmd_save() {
        local force=0 name="" server="" target=""
        while [ $# -gt 0 ]; do
          case "$1" in
            -f | --force) force=1; shift ;;
            --server) [ $# -ge 2 ] || die "--server needs an argument"; server=$2; shift 2 ;;
            --target) [ $# -ge 2 ] || die "--target needs an argument"; target=$2; shift 2 ;;
            -*) die "unknown option: $1" ;;
            *) [ -z "$name" ] || die "unexpected argument: $1"; name=$1; shift ;;
          esac
        done
        check_name "$name"
        require_writable

        local root group
        root=$(repo_root)
        group=$(group_dir_healed "$root") || group="$sessions_dir/$(root_slug "$root")"

        [ -n "$server" ] || server=rust-analyzer
        local server_bin
        server_bin=$(command -v "$server") \
          || die "'$server' not found in PATH -- run 'lspmux-session save' from inside the devshell"

        [ -n "$target" ] || target=''${CARGO_BUILD_TARGET:-''${RA_TARGET:-}}

        local dir="$group/$name"
        if [ -e "$dir" ] && [ "$force" -eq 0 ]; then
          die "session '$name' already exists for $root; pass -f to replace it (a running instance keeps its old environment until 'lspmux-session kill $name')"
        fi
        ${coreutils}/bin/mkdir -p "$dir"
        ${coreutils}/bin/chmod 700 "$sessions_dir" "$group" "$dir"

        local entries n=0 entry var
        # NUL-delimited so values containing newlines don't corrupt the list.
        # `compgen -e` would be the obvious choice but nixpkgs' non-interactive
        # bash is built without progcomp.
        mapfile -d "" -t entries < <(${coreutils}/bin/env -0)

        # Written to a temporary and moved into place so a live instance never
        # sees a half-written wrapper. It keeps running the old inode either
        # way; the new environment takes effect on the next spawn.
        local tmp="$dir/.server.tmp"
        {
          # Absolute interpreter: the wrapper is exec'd by the lspmux server,
          # which has no useful PATH of its own, and /usr/bin/env is not
          # guaranteed to exist.
          echo '#!${bash}/bin/bash'
          echo "# lspmux session '$name', generated $(${coreutils}/bin/date -Is)"
          echo "# root: $root"
          echo "# regenerate with: lspmux-session save $name -f"
          for entry in "''${entries[@]}"; do
            var=''${entry%%=*}
            # Skip environ entries that aren't valid shell identifiers (bash
            # doesn't bind those, so `declare -p` would fail).
            if [[ ! $var =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then continue; fi
            if env_allowed "$var"; then
              declare -p "$var"
              n=$((n + 1))
            fi
          done
          printf 'exec %q "$@"\n' "$server_bin"
        } > "$tmp"
        ${coreutils}/bin/chmod 700 "$tmp"
        ${coreutils}/bin/mv -f "$tmp" "$dir/server"

        ${jqBin} -n \
          --arg name "$name" \
          --arg root "$root" \
          --arg root_base "''${root##*/}" \
          --argjson root_ino "$(${coreutils}/bin/stat -Lc %i "$root")" \
          --argjson root_dev "$(${coreutils}/bin/stat -Lc %d "$root")" \
          --arg server "$server_bin" \
          --arg target "$target" \
          --arg created "$(${coreutils}/bin/date -Is)" \
          --argjson selected_at "$(${coreutils}/bin/date +%s%3N)" \
          '{
            name: $name,
            root: $root,
            root_base: $root_base,
            root_ino: $root_ino,
            # Recorded for diagnostics only. Never matched on: btrfs hands out
            # anonymous device numbers at mount time, so this is stale after the
            # next reboot.
            root_dev: $root_dev,
            server: $server,
            target: (if $target == "" then null else $target end),
            created: $created,
            selected_at: $selected_at
          }' > "$dir/meta.json"

        echo "saved session '$name'"
        echo "  root:   $root"
        echo "  server: $server_bin"
        [ -z "$target" ] || echo "  target: $target"
        echo "  env:    $n variables"
      }

      cmd_use() {
        local name=$1
        local root group
        root=$(repo_root)
        require_writable
        group=$(group_dir_healed "$root") \
          || die "no sessions saved for $root (create one with 'lspmux-session save $name')"
        [ -d "$group/$name" ] \
          || die "no session '$name' for $root (see 'lspmux-session ls')"
        select_session "$group/$name/meta.json"
        echo "selected session '$name' for $root"
      }

      cmd_ls() {
        local metas=() meta
        for meta in "$sessions_dir"/*/*/meta.json; do
          if [ -e "$meta" ]; then metas+=("$meta"); fi
        done
        if [ ''${#metas[@]} -eq 0 ]; then
          echo "no sessions saved (create one with 'lspmux-session save NAME')"
          return 0
        fi

        local root group selected="" name target wrapper pid state mark
        root=$(repo_root)
        group=$(group_dir "$root") || group=""
        [ -z "$group" ] || selected=$(current_session "$group") || selected=""

        printf '%-2s %-18s %-11s %-26s %s\n' "" NAME STATE TARGET ROOT
        for meta in "''${metas[@]}"; do
          name=$(${jqBin} -r '.name' "$meta")
          target=$(${jqBin} -r '.target // "-"' "$meta")
          wrapper="''${meta%/meta.json}/server"

          pid=$(instance_pid "$wrapper")
          if [ -n "$pid" ]; then state="up ($pid)"; else state="down"; fi

          # '*' is the session this directory resolves to, '.' its siblings.
          mark=""
          if [ -n "$group" ] && [ "''${meta%/*/meta.json}" = "$group" ]; then
            if [ "$name" = "$selected" ]; then mark="*"; else mark="."; fi
          fi

          printf '%-2s %-18s %-11s %-26s %s\n' \
            "$mark" "$name" "$state" "$target" "$(${jqBin} -r '.root' "$meta")"
        done
      }

      cmd_show() {
        local dir
        dir=$(resolve_session "$1") || die "no session '$1'"
        while IFS= read -r line; do printf '%s\n' "$line"; done < "$dir/server"
      }

      cmd_rm() {
        local dir
        dir=$(resolve_session "$1") || die "no session '$1'"
        require_writable
        local pid
        pid=$(instance_pid "$dir/server")
        [ -z "$pid" ] || echo "lspmux-session: warning: instance $pid is still running; 'kill' it separately" >&2
        ${coreutils}/bin/rm -rf -- "$dir"
        # Leave no empty repository directories behind to be matched later.
        ${coreutils}/bin/rmdir -- "''${dir%/*}" 2>/dev/null || true
        echo "removed session '$1'"
      }

      cmd_kill() {
        local dir
        dir=$(resolve_session "$1") || die "no session '$1'"
        local pid
        pid=$(instance_pid "$dir/server")
        [ -n "$pid" ] || die "no running instance for session '$1'"
        # The language server is a child of the lspmux server, which may live
        # outside our PID namespace -- the sandbox unshares PIDs, so the pid
        # reported over the socket is unaddressable from in there.
        [ -d "/proc/$pid" ] || die "instance $pid is not visible from here (different PID namespace) -- kill it from the host"
        kill "$pid"
        echo "killed $pid (session '$1')"
      }

      [ $# -ge 1 ] || usage
      cmd=$1
      shift
      case "$cmd" in
        save) cmd_save "$@" ;;
        use) [ $# -eq 1 ] || usage; check_name "$1"; cmd_use "$1" ;;
        ls | list) cmd_ls ;;
        show) [ $# -eq 1 ] || usage; check_name "$1"; cmd_show "$1" ;;
        rm) [ $# -eq 1 ] || usage; check_name "$1"; cmd_rm "$1" ;;
        kill) [ $# -eq 1 ] || usage; check_name "$1"; cmd_kill "$1" ;;
        help | -h | --help) usage 0 ;;
        *) die "unknown command: $cmd (try --help)" ;;
      esac
    '';
  };
in
symlinkJoin {
  name = "lspmux-session";

  paths = [
    lspmux-attach
    lspmux-session
  ];

  passthru = {
    inherit envAllowlist lspmux;
  };

  meta = {
    description = "Named, manually managed lspmux language server sessions";
    mainProgram = "lspmux-session";
  };
}
