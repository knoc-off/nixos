#!/usr/bin/env nix-shell
#!nix-shell -i bash -p inferno

# Generate a flamegraph of Nix evaluation times using the built-in
# stack-sampling eval-profiler (Nix >= 2.30).
#
# The profiler samples the call stack at a configurable frequency and
# writes collapsed-stack output directly — no multi-GB trace files,
# no post-processing pipeline.
#
# Usage:
#   ./scripts/nix-flamegraph.sh
#   ./scripts/nix-flamegraph.sh -A nixosConfigurations.hetzner.config.system.build.toplevel
#   ./scripts/nix-flamegraph.sh --strict --freq 499
#   ./scripts/nix-flamegraph.sh -o my-flamegraph.svg

set -euo pipefail

DEFAULT_ATTR="nixosConfigurations.framework13.config.system.build.toplevel"
ATTR=""
STRICT=""
OUTPUT=""
FLAKE_REF="."
FREQUENCY="199"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Generate a flamegraph SVG of Nix evaluation times for a flake attribute.
Uses Nix's built-in stack-sampling profiler (eval-profiler).

Options:
  -A, --attr ATTR       Flake attribute to evaluate
                        (default: $DEFAULT_ATTR)
  -f, --flake REF       Flake reference (default: .)
  -s, --strict          Deep evaluation via builtins.deepSeq (slower, all code paths)
      --freq N          Sampling frequency in Hz (default: 199, higher = more detail)
  -o, --output FILE     Output SVG path (default: flamegraph-<attr>-<timestamp>.svg)
  -h, --help            Show this help message

Examples:
  $(basename "$0")
  $(basename "$0") -A nixosConfigurations.hetzner.config.system.build.toplevel
  $(basename "$0") --strict --freq 499 -o framework13-strict.svg
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

# Build nix eval arguments
EVAL_ARGS=(
    --option eval-profiler flamegraph
    --option eval-profile-file "$PROFILE_FILE"
    --option eval-profiler-frequency "$FREQUENCY"
)

if [[ -n "$STRICT" ]]; then
    echo "Profiling STRICT evaluation of: ${FLAKE_REF}#${ATTR}" >&2
    echo "  (using builtins.deepSeq -- evaluates all code paths)" >&2
    EVAL_ARGS+=(--impure --expr "builtins.deepSeq (builtins.tryEval ${FLAKE_REF}#${ATTR}) true")
else
    echo "Profiling evaluation of: ${FLAKE_REF}#${ATTR}" >&2
    EVAL_ARGS+=(--raw "${FLAKE_REF}#${ATTR}")
fi

echo "  Sampling frequency: ${FREQUENCY} Hz" >&2
echo "  Output: $OUTPUT" >&2
echo "" >&2

# Step 1: Profile the evaluation
echo "[1/2] Running nix eval with eval-profiler..." >&2

nix eval "${EVAL_ARGS[@]}" 1>/dev/null

PROFILE_SIZE=$(du -h "$PROFILE_FILE" | cut -f1)
PROFILE_LINES=$(wc -l < "$PROFILE_FILE")
echo "  Profile: $PROFILE_SIZE ($PROFILE_LINES samples)" >&2

# Step 2: Generate flamegraph SVG
echo "[2/2] Generating flamegraph SVG..." >&2

inferno-flamegraph \
    --title "Nix Eval: ${ATTR}${STRICT:+ (strict)}" \
    --countname "samples" \
    "$PROFILE_FILE" > "$OUTPUT"

OUTPUT_SIZE=$(du -h "$OUTPUT" | cut -f1)
echo "" >&2
echo "Flamegraph written to: $OUTPUT ($OUTPUT_SIZE)" >&2
echo "Open in a browser to interact (click to zoom, search with Ctrl+F)." >&2
