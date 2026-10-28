#!/bin/bash
# Codespaces / dev-container setup for career-ops. Runs once when the
# container is created: installs dependencies, the Chromium that
# generate-pdf.mjs renders CVs with, the web dashboard's dependencies, and the
# git privacy guard that keeps personal files out of this public fork.
set -euo pipefail

cd "$(dirname "$0")/.."

sudo apt-get update -qq && sudo apt-get install -y -qq unzip > /dev/null
npm install --no-audit --no-fund
npx playwright install --with-deps chromium
(cd web && npm ci --no-audit --no-fund)
bash .claude/hooks/git-privacy-guard.sh install
bash .claude/hooks/attach-data-repo.sh

echo
echo "career-ops is ready."
echo "Personal files come from your private career-ops-data repo (cloned next to this one)."
echo "Commit and push changes there: cd ../career-ops-data && git add -A && git commit -m update && git push"
echo "Start the dashboard with:  bash .devcontainer/start-ui.sh"
