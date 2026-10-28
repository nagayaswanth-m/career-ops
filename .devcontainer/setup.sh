#!/bin/bash
# Codespaces / dev-container setup for career-ops. Runs once when the
# container is created: installs dependencies, the Chromium that
# generate-pdf.mjs renders CVs with, the web dashboard's dependencies, and the
# git privacy guard that keeps personal files out of this public fork.
set -euo pipefail

cd "$(dirname "$0")/.."

npm install --no-audit --no-fund
npx playwright install --with-deps chromium
(cd web && npm ci --no-audit --no-fund)
bash .claude/hooks/git-privacy-guard.sh install

echo
echo "career-ops is ready."
echo "Personal files (cv.md, config/profile.yml, data/, reports/, ...) are gitignored:"
echo "upload or unzip them into this folder; they stay in this private codespace."
echo "Start the dashboard with:  bash .devcontainer/start-ui.sh"
