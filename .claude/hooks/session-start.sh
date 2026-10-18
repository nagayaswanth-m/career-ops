#!/bin/bash
# SessionStart hook for Claude Code on the web (cloud sessions only).
# A cloud session starts from a fresh clone, so it installs npm dependencies
# and, when the repo's Playwright expects a newer headless-shell revision than
# the one pre-installed in the sandbox, links the pre-installed build in so
# generate-pdf.mjs can render CVs. Local machines are left alone.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

npm install --ignore-scripts --no-audit --no-fund --loglevel=error

browsers_dir="${PLAYWRIGHT_BROWSERS_PATH:-/opt/pw-browsers}"
want=$(node -e "const b=JSON.parse(require('fs').readFileSync('node_modules/playwright-core/browsers.json','utf8'));const s=b.browsers.find(x=>x.name==='chromium-headless-shell');process.stdout.write(s?s.revision:'')" 2>/dev/null || true)
target="$browsers_dir/chromium_headless_shell-$want/chrome-headless-shell-linux64"

if [ -n "$want" ] && [ ! -e "$target/chrome-headless-shell" ]; then
  have=$(ls -d "$browsers_dir"/chromium_headless_shell-*/chrome-linux 2>/dev/null | sort -V | tail -1 || true)
  if [ -n "$have" ] && [ -x "$have/headless_shell" ]; then
    mkdir -p "$target"
    ln -sf "$have"/* "$target"/
    ln -sf "$have/headless_shell" "$target/chrome-headless-shell"
    touch "$browsers_dir/chromium_headless_shell-$want/INSTALLATION_COMPLETE" \
          "$browsers_dir/chromium_headless_shell-$want/DEPENDENCIES_VALIDATED"
  fi
fi
