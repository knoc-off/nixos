{ ... }: {
  home =
    { pkgs, lib, ... }:
    let
      inherit (pkgs) mkComplgenScript;
    in
    {
      home.packages = [

        # Render GitHub PR review threads as markdown, tracking which ones you've seen.
        (mkComplgenScript {
          name = "pr-threads";
          package = pkgs.writers.writePython3Bin "pr-threads" { flakeIgnore = [ "E501" ]; } ''
            import argparse
            import json
            import os
            import re
            import subprocess
            import sys
            from datetime import datetime, timedelta, timezone
            from pathlib import Path

            GH = "${pkgs.gh}/bin/gh"
            EPOCH = "1970-01-01T00:00:00Z"
            QUERY = """
            query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
              repository(owner: $owner, name: $name) {
                pullRequest(number: $number) {
                  reviewThreads(first: 100, after: $endCursor) {
                    pageInfo { hasNextPage endCursor }
                    nodes {
                      isResolved isOutdated path line originalLine
                      comments(first: 100) {
                        nodes { author { login } body url createdAt viewerDidAuthor }
                      }
                    }
                  }
                }
              }
            }"""


            def gh(*args):
                r = subprocess.run([GH, *args], capture_output=True, text=True)
                if r.returncode:
                    sys.exit(r.stderr.strip() or f"gh {args[0]} failed")
                return r.stdout


            def main():
                p = argparse.ArgumentParser(description="Render GitHub PR review threads as markdown, tracking which ones you've seen. With neither --since nor --all, shows threads with comments newer than the last run.")
                p.add_argument("pr", nargs="?", help="PR number (default: PR for current branch)")
                p.add_argument("-R", "--repo", metavar="O/N", help="repository (default: current repo)")
                p.add_argument("-s", "--since", metavar="SPEC", help='show threads with activity since SPEC (e.g. "1 hour", "2 days")')
                p.add_argument("-a", "--all", action="store_true", help="show every thread, ignore state file")
                p.add_argument("-n", "--no-mark", action="store_true", help="don't advance the seen-marker")
                p.add_argument("--include-mine", action="store_true", help="keep threads whose only new comments are your own")
                p.add_argument("-u", "--unresolved", action="store_true", help="drop resolved threads")
                p.add_argument("-r", "--reasoning", choices=["fold", "strip", "raw"], default="fold", help="handling of <details> blocks (default: fold)")
                a = p.parse_args()

                repo = a.repo or gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
                pr = a.pr or gh("pr", "view", "--json", "number", "-q", ".number").strip()
                owner, name = repo.split("/", 1)
                state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "pr-threads" / f"{owner}__{name}__{pr}"

                if a.all:
                    cutoff = EPOCH
                elif a.since:
                    m = re.fullmatch(r"(\d+)\s*(minute|hour|day|week)s?", a.since.strip())
                    if not m:
                        sys.exit(f"cannot parse --since {a.since!r} (try '2 hours', '1 day')")
                    cutoff = (datetime.now(timezone.utc) - timedelta(**{m[2] + "s": int(m[1])})).strftime("%Y-%m-%dT%H:%M:%SZ")
                else:
                    cutoff = state.read_text().strip() if state.exists() else EPOCH

                pages = json.loads(gh(
                    "api", "graphql", "--paginate", "--slurp",
                    "-F", f"owner={owner}", "-F", f"name={name}", "-F", f"number={pr}",
                    "-f", f"query={QUERY}"))
                threads = [t for page in pages
                           for t in page["data"]["repository"]["pullRequest"]["reviewThreads"]["nodes"]]

                def is_new(c):
                    return c["createdAt"] > cutoff

                def clean(body):
                    body = body.replace("\r", "")
                    if a.reasoning == "strip":
                        body = re.sub(r"<details>.*?</details>", "_[reasoning elided]_", body, flags=re.S)
                    return body

                shown = [t for t in threads if any(map(is_new, t["comments"]["nodes"]))]
                if not a.include_mine:
                    shown = [t for t in shown
                             if any(is_new(c) and not c["viewerDidAuthor"] for c in t["comments"]["nodes"])]
                if a.unresolved:
                    shown = [t for t in shown if not t["isResolved"]]

                if not shown:
                    print(f"_Nothing new since {cutoff}._")
                by_path = {}
                for t in shown:
                    by_path.setdefault(t["path"], []).append(t)
                for path, ts in sorted(by_path.items()):
                    print(f"# {path.rsplit('/', 1)[-1]}")
                    print(f"`{path}`")
                    print()
                    for t in sorted(ts, key=lambda t: t["line"] or t["originalLine"] or 0):
                        line = t["line"] or t["originalLine"] or "?"
                        hdr = f"## [L{line}]({t['comments']['nodes'][0]['url']})"
                        hdr += " *(resolved)*" if t["isResolved"] else ""
                        hdr += " *(outdated)*" if t["isOutdated"] else ""
                        print(hdr)
                        print()
                        for c in t["comments"]["nodes"]:
                            tag = "  `new`" if is_new(c) else ""
                            print(f"- **@{(c['author'] or {}).get('login', 'ghost')}**{tag}")
                            for ln in clean(c["body"]).split("\n"):
                                print("  " + ln if ln else "")
                            print()

                if not a.no_mark and not a.all:
                    stamps = [c["createdAt"] for t in threads for c in t["comments"]["nodes"]]
                    if stamps:
                        state.parent.mkdir(parents=True, exist_ok=True)
                        state.write_text(max(stamps) + "\n")


            main()
          '';
          grammar = ''
            pr-threads [<PR>] [(-R | --repo) <REPO> "repository"] [(-s | --since) <SPEC> "activity since"] [(-a | --all) "show every thread"] [(-n | --no-mark) "don't advance seen-marker"] [--include-mine "keep own comments"] [(-u | --unresolved) "drop resolved threads"] [(-r | --reasoning) (fold | strip | raw) "<details> handling"];
          '';
        })

        (pkgs.writeShellApplication {
          name = "get-review-requests";

          runtimeInputs = [
            pkgs.gh
          ];

          text = ''
            gh search prs \
              --review-requested=@me \
              --state=open \
              --sort=updated \
              --order=desc \
              --json repository,title,url,createdAt,author \
              --template '{{range .}}{{tablerow .repository.nameWithOwner .title .author.login (timeago .createdAt) .url}}{{end}}'
          '';
        })

        (pkgs.writeShellApplication {
          name = "google-oauth";

          runtimeInputs = [
            pkgs.oath-toolkit
            pkgs.wl-clipboard
          ];

          text = ''
            CODE=$(oathtool --totp -b "$GOOGLE_TOTP_KEY")
            echo "$CODE"
            echo "$CODE" | wl-copy
          '';
        })

        (pkgs.writeShellApplication {
          name = "skim-env-vars";

          runtimeInputs = [
            pkgs.python3
            pkgs.skim
          ];

          text = ''
            python3 -c 'import os,sys; sys.stdout.write("\0".join(sorted(os.environ)) + "\0")' \
              | sk --read0 --no-mouse --no-multi \
                  --preview 'python3 -c "import os,sys; k=sys.argv[1]; sys.stdout.write(os.environ.get(k, \"\"))" {}' \
                  --preview-window=right:70%:wrap
          '';
        })

        (pkgs.writeShellScriptBin "opencode-api" ''
          set -euo pipefail

          AUTH_DIR="$HOME/.local/share/opencode"
          AUTH_FILE="$AUTH_DIR/auth.json"
          AUTH_API="$AUTH_DIR/auth.json.api"
          AUTH_BAK="$AUTH_DIR/auth.json.bak.$$"

          [[ -f "$AUTH_API" ]] || { echo "Missing $AUTH_API"; exit 1; }

          RESTORE_PID=""
          cleanup() {
            [[ -n "''${RESTORE_PID:-}" ]] && kill "$RESTORE_PID" 2>/dev/null || true
            [[ -f "$AUTH_BAK" ]] && mv "$AUTH_BAK" "$AUTH_FILE"
          }
          trap cleanup EXIT

          cp "$AUTH_FILE" "$AUTH_BAK"
          cp "$AUTH_API" "$AUTH_FILE"

          (sleep 30 && [[ -f "$AUTH_BAK" ]] && mv "$AUTH_BAK" "$AUTH_FILE") &
          RESTORE_PID=$!

          opencode "$@"
        '')

        (pkgs.writeShellScriptBin "git-branch-view" ''
          set -euo pipefail

          export GIT="${pkgs.git}/bin/git"
          export SK="${pkgs.skim}/bin/sk"
          export DELTA="${pkgs.delta}/bin/delta"
          export BASH="${pkgs.bash}/bin/bash"
          export TPUT="${pkgs.ncurses}/bin/tput"

          # Pick a default BASE if not provided
          if [ -z "''${BASE:-}" ]; then
            if "$GIT" show-ref --verify --quiet refs/remotes/origin/main; then
              BASE="origin/main"
            elif "$GIT" show-ref --verify --quiet refs/heads/main; then
              BASE="main"
            elif "$GIT" show-ref --verify --quiet refs/remotes/origin/master; then
              BASE="origin/master"
            elif "$GIT" show-ref --verify --quiet refs/heads/master; then
              BASE="master"
            else
              BASE=""
            fi
            export BASE
          fi

          # Delta enabled by default (set SHOW_DELTA=0 to disable)
          export SHOW_DELTA="''${SHOW_DELTA: -1}"

          "$GIT" for-each-ref --format='%(refname:short)' refs/heads \
          | "$SK" \
              --prompt="branch> " \
              --height=100% \
              --layout=reverse \
              --preview-window='right:70%' \
              --bind="ctrl-u:preview-page-up,ctrl-d:preview-page-down" \
              --preview 'bash -lc '"'"'
                b="''${1-}"
                [ -n "$b" ] || exit 0

                base="''${BASE:-}"
                show="''${SHOW_DELTA:-1}"

                mb=""
                if [ -n "$base" ]; then
                  mb="$("$GIT" merge-base "$b" "$base" 2>/dev/null || true)"
                fi

                cols="''${FZF_PREVIEW_COLUMNS:-}"
                if [ -z "$cols" ]; then
                  cols="$("$TPUT" cols 2>/dev/null || echo 120)"
                fi

                if [ -n "$mb" ]; then
                  "$GIT" diff --name-status "$mb..$b"
                  echo
                  "$GIT" log --oneline --no-merges "$mb..$b" | head -200

                  if [ "$show" = "1" ]; then
                    echo
                    "$GIT" diff --color=always "$mb..$b" | "$DELTA" --paging=never --width="$cols"
                  fi
                else
                  "$GIT" show --name-status --oneline -n 1 "$b"
                  echo
                  "$GIT" log --oneline -n 30 "$b"

                  if [ "$show" = "1" ]; then
                    echo
                    "$GIT" show --color=always -n 1 "$b" | "$DELTA" --paging=never --width="$cols"
                  fi
                fi
              '"'"' _ {}'
        '')

        (mkComplgenScript {
          name = "excel_to_csv";
          text = ''
            python -c "import pandas as pd; import sys; pd.read_excel(sys.argv[1]).to_csv(sys.argv[2], index=False, encoding='utf-8')" "$1" "$2"
          '';
          grammar = ''
            excel_to_csv {{{ ${pkgs.fd}/bin/fd --type f --extension xlsx --extension xls --max-depth 1 . --color never --hidden --no-ignore }}} "Input Excel file" <PATH> "Output CSV file";
          '';
          runtimeInputs = [
            (pkgs.python3.withPackages (ps: [
              ps.pandas
              ps.openpyxl
            ]))
          ];
        })

        (pkgs.writeShellApplication {
          name = "record-region";
          runtimeInputs = with pkgs; [
            wl-screenrec
            slurp
            wl-clipboard
            libnotify
            coreutils
            dragon-drop
            socat
            jq
            gawk
          ];
          text = ''
            outdir="''${HOME}/Videos/recordings"
            mkdir -p "$outdir"
            timestamp=$(date +%Y%m%d_%H%M%S)
            outfile="''${outdir}/recording_''${timestamp}.mp4"

            geometry=$(slurp) || { echo "Selection cancelled"; exit 1; }

            echo "Recording region: $geometry"
            echo "Output: $outfile"
            echo "Press Ctrl+C to stop recording."

            # Trap SIGINT so wl-screenrec exits cleanly and finalizes the mp4
            trap 'echo ""' INT
            wl-screenrec --geometry "$geometry" --filename "$outfile" || true
            trap - INT

            if [ -f "$outfile" ] && [ -s "$outfile" ]; then
              printf '%s' "$outfile" | wl-copy
              notify-send -i video-x-generic "Recording saved" "$outfile (path copied)"
              echo "Saved: $outfile"

              # Spawn dragon-drop for easy drag-and-drop of the recording
              dragon-drop --and-exit "$outfile" &
              DRAGON_PID=$!
              sleep 0.3

              # Background listener: reposition dragon-drop to bottom-right
              # of the focused monitor whenever the user switches monitors
              (
                set +e
                trap 'exit 0' TERM

                reposition() {
                  mon=$(hyprctl -j monitors | jq -r '
                    [.[] | select(.focused)][0] |
                    "\(.x) \(.y) \(.width) \(.height) \(.scale)"')
                  [ -n "$mon" ] || return 0
                  read -r mx my mw mh ms <<< "$mon"

                  win=$(hyprctl -j clients | jq -r '
                    [.[] | select(.class == "dragon-drop")][0] |
                    "\(.size[0]) \(.size[1])"')
                  [ -n "$win" ] && [ "$win" != "null null" ] || return 0
                  read -r ww wh <<< "$win"

                  tx=$(awk "BEGIN { printf \"%d\", $mx + ($mw / $ms) - $ww - 20 }")
                  ty=$(awk "BEGIN { printf \"%d\", $my + ($mh / $ms) - $wh - 20 }")
                  hyprctl dispatch movewindowpixel "exact $tx $ty,class:dragon-drop" \
                    >/dev/null 2>&1
                  return 0
                }

                socat -U - \
                  "UNIX-CONNECT:''${XDG_RUNTIME_DIR}/hypr/''${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" \
                  2>/dev/null \
                | while IFS= read -r ev; do
                    case "$ev" in focusedmon*) reposition ;; esac
                  done
              ) &
              FOLLOW_PID=$!

              wait $DRAGON_PID 2>/dev/null || true
              kill $FOLLOW_PID 2>/dev/null || true
            else
              notify-send -u critical "Recording failed" "No output file produced"
              exit 1
            fi
          '';
        })

        # TODO: Add ignore glob as easy to add. more important than include tbh
        (pkgs.writeShellScriptBin "text-search" ''
          sk --ansi -i -c 'rg --color=always --line-number "{}"' \
             --preview 'f=$(echo {} | cut -d: -f1); l=$(echo {} | cut -d: -f2); bat --color=always --style=numbers --highlight-line $l "$f"' \
             --preview-window '+{2}-/2' \
             --delimiter ':'
        '')

        (pkgs.writeShellApplication {
          name = "gitignore";
          runtimeInputs = [
            pkgs.git
            pkgs.gnused
          ];
          text = ''
            git ls-files --others --exclude-standard | sed "s|^|$(git rev-parse --show-prefix)|" >> "$(git rev-parse --show-toplevel)/.git/info/exclude"
          '';
        })
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        (mkComplgenScript {
          name = "pipewire-combine-sinks";
          text = ''
            die() { echo "Error: $*" >&2; exit 1; }

            cleanup() {
              mapfile -t ids < <(pactl list modules short | grep -w module-combine-sink | awk '{print $1}' || true)
              [[ ''${#ids[@]} -eq 0 ]] && echo "No combined sinks found." && return
              echo "Removing ''${#ids[@]} combined sink module(s)..."
              for id in "''${ids[@]}"; do pactl unload-module "$id" 2>/dev/null || true; done
            }

            case "''${1:-}" in
              -c|--clean) cleanup; exit 0 ;;
              -h|--help)  echo "Usage: pipewire-combine-sinks [-c|--clean] [-h|--help]"; exit 0 ;;
              "")         ;; # continue
              *)          die "Unknown option: $1" ;;
            esac

            cleanup

            # Discover sinks (TSV: node.name, description)
            mapfile -t raw < <(
              pw-dump | jq -r '
                .[] | select(.type == "PipeWire:Interface:Node"
                        and .info.props["media.class"] == "Audio/Sink")
                | [.info.props["node.name"],
                   (.info.props["node.description"] // .info.props["node.name"])]
                | @tsv'
            )
            [[ ''${#raw[@]} -lt 2 ]] && die "Need at least 2 sinks to combine."

            declare -a names descs
            declare -A desc_to_idx
            for i in "''${!raw[@]}"; do
              IFS=$'\t' read -r name desc <<< "''${raw[$i]}"
              names+=("$name"); descs+=("$desc"); desc_to_idx["$desc"]=$i
            done

            # Select sinks
            first=$(printf '%s\n' "''${descs[@]}" | gum choose --header "Select first device")
            second=$(printf '%s\n' "''${descs[@]}" | grep -vxF "$first" | gum choose --header "Select second device")
            idx1="''${desc_to_idx[$first]}"
            idx2="''${desc_to_idx[$second]}"

            # Name combined sink
            sink_name=$(gum input --placeholder "combined" --header "Name for combined sink" --char-limit 64) || true
            sink_name="''${sink_name:-combined}"
            [[ "$sink_name" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Invalid name — use [a-zA-Z0-9_-] only."

            # Create & set default
            echo "Creating '$sink_name': $first + $second"
            pactl load-module module-combine-sink sink_name="$sink_name" slaves="''${names[$idx1]},''${names[$idx2]}"
            gum spin --spinner dot --title "Waiting for registration..." -- sleep 2

            new_id=$(pw-dump | jq -r --arg n "$sink_name" '
              [.[] | select(.type == "PipeWire:Interface:Node"
                      and .info.props["node.name"] == $n)][0].id // empty')
            [[ -z "$new_id" ]] && die "Sink '$sink_name' not found after creation."

            wpctl set-default "$new_id"
            echo "Done — '$sink_name' is now the default output."
          '';

          grammar = ''
            pipewire-combine-sinks (-c | --clean | -h | --help)?;
          '';

          runtimeInputs = with pkgs; [
            pipewire
            jq
            pulseaudio
            wireplumber
            coreutils
            gum
            gnugrep
            gawk
          ];
        })

        (mkComplgenScript {
          name = "ping"; # The command name users will type

          text = ''
            # Use exec to replace this script process with ping for cleaner signal handling
            if [ $# -eq 0 ]; then
              echo "No target specified, pinging default: 1.1.1.1"
              # Use inetutils ping, which is more standard than toybox's
              exec ${pkgs.inetutils}/bin/ping 1.1.1.1
            else
              # Pass all arguments exactly as received to the real ping
              exec ${pkgs.inetutils}/bin/ping "$@"
            fi
          '';

          # Grammar for command-line completion. Its command block runs in the
          # user's interactive shell, so it references awk by store path.
          grammar = ''
            ping {{{
              [ -f "$HOME/.ssh/known_hosts" ] && \
              ${pkgs.gawk}/bin/awk '
                # Skip comments, hashed hosts (|1|...), and markers (@...)
                /^#/ || /^\|/ || /^@/ { next }
                {
                  # Get the first field (host list)
                  hosts = $1
                  # Remove bracket/port notation like [host]:port
                  gsub(/\[|\]:[0-9]+/, "", hosts)
                  # Split comma-separated hosts and print each one
                  n = split(hosts, arr, ",")
                  for (i = 1; i <= n; i++) {
                    print arr[i]
                  }
                }
              ' "$HOME/.ssh/known_hosts" | sort -u
            }}} "Target host/IP"

            # Allow any other host/IP not in the list
            <HOST>

            # Allow any subsequent arguments (like -c, -i, etc.)
            ... ;
          '';
        })

        (mkComplgenScript {
          name = "chrome";
          text = ''
            nix shell nixpkgs#ungoogled-chromium --command chromium "$@" &>/dev/null &
          '';
          grammar = ''
            chrome [<URL>];
          '';
        })

        (mkComplgenScript {
          name = "connect";
          text = ''
            if [ $# -lt 1 ]; then echo "Usage: connect <SSID> [password]"; exit 1; fi
            nmcli device wifi rescan
            nmcli device wifi connect "$@"
          '';
          grammar = ''
            connect {{{ ${pkgs.networkmanager}/bin/nmcli -t -f SSID dev wifi list }}} "SSID" [password "password: string"];
          '';
          runtimeInputs = [ pkgs.networkmanager ];
        })

        (mkComplgenScript {
          name = "qr";
          text = ''
            # Check for --share option
            for arg in "$@"; do
                if [[ "$arg" == "--share" ]]; then
                    qrencode -t UTF8 < "$0"
                    exit 0
                fi
            done

            # Read input if no arguments provided
            if [ $# -eq 0 ]; then
                read -r sanitized_input
            else
                sanitized_input="$*"
            fi

            # Generate QR code
            echo "$sanitized_input" | qrencode -t UTF8
          '';
          grammar = ''
            qr (--share | {{{ ${pkgs.fd}/bin/fd --type directory --type file --max-depth 1 . --color never }}} <INPUT>);
          '';
          runtimeInputs = [ pkgs.qrencode ];
        })

        (mkComplgenScript {
          name = "compress";
          text = ''
            if [ "$#" -ne 2 ]; then echo "Usage: compress <source> <dest.tar.gz>"; exit 1; fi
            [ ! -e "$1" ] && { echo "Error: Source not found"; exit 1; }
            tar -cf - "$1" | pv -s "$(du -sb "$1" | awk '{print $1}')" | pigz -9 > "$2".tar.gz
          '';
          grammar = ''
            compress {{{ ${pkgs.fd}/bin/fd --type directory --type file --max-depth 1 . --color never }}} "Source" <PATH> "Destination";
          '';
          runtimeInputs = [
            pkgs.pigz
            pkgs.pv
          ];
        })

        (mkComplgenScript {
          name = "rsync-compress";
          text = ''
            if [ "$#" -ne 2 ]; then echo "Usage: rsync-compress <source> <dest>"; exit 1; fi
            [ ! -e "$1" ] && { echo "Error: Source not found"; exit 1; }
            size=$(du -sb "$1" | awk '{print $1}')
            rsync -avz --progress --compress-level=9 "$1" "$2" | pv -lep -s "$size"
          '';
          grammar = ''
            rsync-compress {{{ ${pkgs.fd}/bin/fd --type directory --type file --max-depth 1 . --color never }}} "Source" <PATH> "Destination";
          '';
          runtimeInputs = [
            pkgs.rsync
            pkgs.pv
          ];
        })
      ];
    };
}
