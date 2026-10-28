#!/bin/bash
# Starts the career-ops web dashboard so it can be opened through the
# codespace's forwarded port. The server still listens on loopback only; the
# codespace's own forwarded hostname is the one extra host the request guard
# accepts (CAREER_OPS_WEB_ALLOWED_HOSTS, see web/src/lib/origin-guard.mjs).
# Runs a production build: no dev hot-reload socket, which Next.js refuses to
# serve to a non-loopback origin, and faster pages on a phone.
set -euo pipefail

cd "$(dirname "$0")/.."
port="${1:-3000}"

if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
  export CAREER_OPS_WEB_ALLOWED_HOSTS="${CODESPACE_NAME}-${port}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  url="https://${CAREER_OPS_WEB_ALLOWED_HOSTS}"
else
  url="http://127.0.0.1:${port}"
fi

CAREER_OPS_ROOT=$(node --input-type=module -e "import('./path-resolver.mjs').then(m => console.log(m.getCareerOpsRoot()))")
export CAREER_OPS_ROOT PORT="$port"

echo "Building the dashboard (about a minute)..."
build_log="${TMPDIR:-/tmp}/career-ops-web-build.log"
if ! (cd web && npx next build > "$build_log" 2>&1); then
  tail -n 40 "$build_log"
  echo "Build failed; full log: $build_log"
  exit 1
fi

echo
echo "career-ops dashboard: $url"
echo "(Ports tab -> port $port. Keep its visibility Private: it shows your CV and tracker.)"
echo
cd web && exec node server.mjs start -p "$port" -H 127.0.0.1
