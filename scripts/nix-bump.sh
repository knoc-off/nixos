#!/usr/bin/env bash
# Pulls the flake.lock last verified by optiplex's nix-autobuild (see
# systems/services/nix-autobuild.nix) into the local checkout, without
# touching anything else in the working tree.
#
# optiplex builds every per-host toplevel against a candidate flake.lock and
# only
# pushes it to the `built` branch if every per-host toplevel succeeded -- so
# unlike a plain `nix flake update`, bumping via this script means the new lock
# is already known to build and its outputs are already sitting in optiplex's
# harmonia cache. Run this instead of `nix flake update` on anything that isn't
# optiplex itself.
#
# Taking only flake.lock is enough to hit that cache: no derivation depends on
# this repo's git revision, so a local checkout at a different commit than the
# builder still evaluates to identical store paths. (This was not always true --
# system.nixos.label used to embed self.shortRev, which made every host's
# toplevel miss the cache unless the client sat on the builder's exact commit.)
#
# Servers don't need this at all: they can rebuild straight off the branch,
# e.g. `nixos-rebuild switch --flake github:knoc-off/nixos/built#hetzner`.
#
# Usage:
#   ./scripts/nix-bump.sh
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [ -n "$(git status --porcelain -- flake.lock)" ]; then
  echo "flake.lock has uncommitted changes -- commit, stash, or discard them first." >&2
  exit 1
fi

git fetch origin built

before=$(git rev-parse HEAD:flake.lock 2>/dev/null || echo "")
git checkout origin/built -- flake.lock
after=$(git hash-object flake.lock)

if [ "$before" = "$after" ]; then
  echo "flake.lock already matches optiplex's built branch."
  exit 0
fi

echo "flake.lock updated from origin/built. Diff:"
git diff --stat -- flake.lock
echo
echo "Review with 'git diff flake.lock', then commit when ready."
