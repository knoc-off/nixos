#!/usr/bin/env nix-shell
#!nix-shell -i bash -p flamegraph

# Generate a flamegraph of Nix evaluation times using the built-in
# stack-sampling eval-profiler (Nix >= 2.30).
#
# The profiler samples the call stack at a configurable frequency and
# writes collapsed-stack output directly (frame;frame count) -- no
# multi-GB trace files, no post-processing pipeline. The collapsed output
# is rendered to SVG with flamegraph.pl.
#
# Usage:
#   ./scripts/nix-flamegraph.sh
#   ./scripts/nix-flamegraph.sh -A nixosConfigurations.hetzner.config.system.build.toplevel.drvPath
#   ./scripts/nix-flamegraph.sh --freq 499 -o my-flamegraph.svg
#   # anything after `--` is passed straight to `nix eval`:
#   ./scripts/nix-flamegraph.sh -- --offline --override-input nelly path:/tmp/fake-nelly

set -euo pipefail

DEFAULT_ATTR="nixosConfigurations.thinkpad-work.config.system.build.toplevel.drvPath"
ATTR=""
STRICT=""
OUTPUT=""
FLAKE_REF="."
FREQUENCY="199"
EXTRA_NIX_ARGS=()

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [-- EXTRA_NIX_ARGS...]

Generate a flamegraph SVG of Nix evaluation times for a flake attribute.
Uses Nix's built-in stack-sampling profiler (eval-profiler) + flamegraph.pl.

Options:
  -A, --attr ATTR       Flake attribute to evaluate. For a derivation, append
                        '.drvPath' so it evaluates to a string.
                        (default: $DEFAULT_ATTR)
  -f, --flake REF       Flake reference (default: .)
  -s, --strict          Deep evaluation via builtins.deepSeq (slower, forces all
                        code paths instead of just what drvPath needs)
      --freq N          Sampling frequency in Hz (default: 199, higher = more detail)
  -o, --output FILE     Output SVG path (default: flamegraph-<attr>-<timestamp>.svg)
  -h, --help            Show this help message

Everything after '--' is forwarded verbatim to 'nix eval' (e.g. --offline,
--override-input, --impure).

Examples:
  $(basename "$0")
  $(basename "$0") -A nixosConfigurations.hetzner.config.system.build.toplevel.drvPath
  $(basename "$0") --freq 499 -o thinkpad-strict.svg -- --offline
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -A|--attr)   ATTR="$2"; shift 2 ;;
        -f|--flake)  FLAKE_REF="$2"; shift 2 ;;
        -s|--strict) STRICT=1; shift ;;
        --freq)      FREQUENCY="$2"; shift 2 ;;
        -o|--output) OUTPUT="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        --)          shift; EXTRA_NIX_ARGS=("$@"); break ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

ATTR="${ATTR:-$DEFAULT_ATTR}"

if [[ -z "$OUTPUT" ]]; then
    SAFE_ATTR=$(echo "$ATTR" | tr './' '-')
    OUTPUT="flamegraph-${SAFE_ATTR}-$(date +%Y%m%d-%H%M%S).svg"
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

PROFILE_FILE="$WORKDIR/nix.profile"

# Build nix eval arguments. The profiler flags are plain settings, so they
# work as either --option NAME VALUE or --NAME VALUE.
EVAL_ARGS=(
    --eval-profiler flamegraph
    --eval-profile-file "$PROFILE_FILE"
    --eval-profiler-frequency "$FREQUENCY"
)

if [[ -n "$STRICT" ]]; then
    echo "Profiling STRICT evaluation of: ${FLAKE_REF}#${ATTR}" >&2
    echo "  (using builtins.deepSeq -- forces all code paths)" >&2
    # Flake '#'-syntax is not valid inside --expr; resolve via getFlake.
    EVAL_ARGS+=(
        --impure
        --expr "builtins.deepSeq (builtins.getFlake (toString ${FLAKE_REF})).${ATTR} true"
    )
else
    echo "Profiling evaluation of: ${FLAKE_REF}#${ATTR}" >&2
    EVAL_ARGS+=(--raw "${FLAKE_REF}#${ATTR}")
fi

echo "  Sampling frequency: ${FREQUENCY} Hz" >&2
echo "  Output: $OUTPUT" >&2
[[ ${#EXTRA_NIX_ARGS[@]} -gt 0 ]] && echo "  Extra nix args: ${EXTRA_NIX_ARGS[*]}" >&2
echo "" >&2

# Step 1: Profile the evaluation.
echo "[1/2] Running nix eval with eval-profiler..." >&2
nix eval "${EVAL_ARGS[@]}" "${EXTRA_NIX_ARGS[@]}" 1>/dev/null

if [[ ! -s "$PROFILE_FILE" ]]; then
    echo "error: profiler produced no samples ($PROFILE_FILE is empty)." >&2
    echo "       The eval may have failed -- rerun the nix eval above without" >&2
    echo "       redirecting stdout to see the error." >&2
    exit 1
fi

PROFILE_SIZE=$(du -h "$PROFILE_FILE" | cut -f1)
PROFILE_LINES=$(wc -l < "$PROFILE_FILE")
echo "  Profile: $PROFILE_SIZE ($PROFILE_LINES stacks)" >&2

# Step 2: Render the collapsed stacks to an SVG.
echo "[2/2] Generating flamegraph SVG..." >&2
flamegraph.pl \
    --title "Nix Eval: ${ATTR}${STRICT:+ (strict)}" \
    --countname "samples" \
    "$PROFILE_FILE" > "$OUTPUT"

OUTPUT_SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "" >&2
echo "Flamegraph written to: $OUTPUT ($OUTPUT_SIZE)" >&2
echo "Open in a browser to interact (click to zoom, search with Ctrl+F)." >&2
