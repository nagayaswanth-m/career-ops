#!/bin/bash
# Attaches the private personal-data repository to this checkout.
#
# Personal files (cv.md, config/profile.yml, data/, reports/, ...) live in a
# separate PRIVATE repo named career-ops-data, owned by the same account as
# this fork, cloned next to it. This script clones it when it is missing and
# writes the gitignored .career-ops-data marker that path-resolver.mjs reads,
# so every career-ops tool uses it as the data root (DATA_CONTRACT.md,
# "Custom Data Directory"). Nothing personal is ever stored in this public fork.
#
# Safe to run repeatedly. Never fails the caller: if the repo does not exist or
# this environment has no access to it, it says so and the checkout keeps
# using its own (gitignored) files.
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 0
data_dir="../career-ops-data"

if [ ! -d "$data_dir/.git" ]; then
  origin=$(git remote get-url origin 2>/dev/null) || exit 0
  case "$origin" in
    *.git) data_url="${origin%/*}/career-ops-data.git" ;;
    *) data_url="${origin%/*}/career-ops-data" ;;
  esac
  if ! GIT_TERMINAL_PROMPT=0 git clone --quiet "$data_url" "$data_dir" 2>/dev/null; then
    echo "career-ops: private data repo not reachable from here; using this checkout's own files." >&2
    exit 0
  fi
fi

if [ ! -f .career-ops-data ] || [ "$(cat .career-ops-data)" != "$data_dir" ]; then
  echo "$data_dir" > .career-ops-data
fi
echo "career-ops: personal data from $(cd "$data_dir" && pwd)" >&2
