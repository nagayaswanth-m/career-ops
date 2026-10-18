#!/bin/bash
# Git privacy guard for a PUBLIC fork of career-ops.
#
# Installed as .git/hooks/pre-commit and .git/hooks/pre-push by
# .claude/hooks/session-start.sh (or run `bash .claude/hooks/git-privacy-guard.sh install`).
# It refuses a commit/push that would publish:
#   1. user-layer files (cv.md, config/profile.yml, data/, reports/, output/, ...),
#      even when force-added past .gitignore;
#   2. the candidate's own email, phone, name or LinkedIn URL, read at runtime
#      from the gitignored config/profile.yml, so this file holds no personal data;
#   3. strings shaped like API keys, tokens or private keys.
# Bypass a false positive deliberately with `git commit --no-verify`.
set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$repo_root" || exit 0

mode="${1:-pre-commit}"

if [ "$mode" = "install" ]; then
  hooks_dir=$(git rev-parse --git-path hooks)
  mkdir -p "$hooks_dir"
  for hook in pre-commit pre-push; do
    dest="$hooks_dir/$hook"
    if [ -e "$dest" ] && ! grep -q "git-privacy-guard" "$dest" 2>/dev/null; then
      echo "privacy-guard: $dest already exists and is not ours; left untouched." >&2
      continue
    fi
    printf '#!/bin/sh\nexec bash "$(git rev-parse --show-toplevel)/.claude/hooks/git-privacy-guard.sh" %s "$@"\n' "$hook" > "$dest"
    chmod +x "$dest"
  done
  exit 0
fi

# Paths that belong to the user layer (DATA_CONTRACT.md). Shipped placeholders
# (.gitkeep, README.md, *.template.md, *.example.*) are allowed through.
personal_path_re='^(cv\.md|article-digest\.md|portals\.yml|voice-dna\.md|\.career-ops-data|\.env(\..*)?|config/(profile\.yml|cv-facts\.json|benchmarks\.yml|plugins\.yml|local-paths\.txt)|modes/_(profile|custom|brief)\.md|(data|reports|output|jds|documents|writing-samples|interview-prep|batch/tracker-additions|local)/.*)$'
allowed_path_re='(^|/)(\.gitkeep|README\.md)$|\.template\.md$|\.example\.'
secret_file_re='\.(pem|key|p12|pfx|keystore)$|(^|/)id_(rsa|ed25519|ecdsa)$'

# High-signal token shapes. Placeholders such as sk-xxxx or <your-key> are skipped below.
secret_re='(sk-ant-[A-Za-z0-9_-]{20,}|sk-(proj-)?[A-Za-z0-9]{32,}|gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}|AIza[0-9A-Za-z_-]{35}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{20,}|ntn_[A-Za-z0-9]{40,}|secret_[A-Za-z0-9]{40,}|apify_api_[A-Za-z0-9]{30,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----)'
placeholder_re='(x{6,}|X{6,}|your[_-]|<[^>]*>|example|placeholder|dummy|redacted|\.\.\.)'

paths=""
added=""
case "$mode" in
  pre-commit)
    paths=$(git diff --cached --name-only --diff-filter=ACMR)
    added=$(git diff --cached -U0 --no-color --diff-filter=ACMR | grep '^+' | grep -v '^+++' || true)
    ;;
  pre-push)
    zero=0000000000000000000000000000000000000000
    while read -r _local_ref local_sha _remote_ref _remote_sha; do
      [ -z "${local_sha:-}" ] && continue
      [ "$local_sha" = "$zero" ] && continue
      for c in $(git rev-list "$local_sha" --not --remotes 2>/dev/null); do
        paths="$paths"$'\n'"$(git show --name-only --diff-filter=ACMR --format= "$c")"
        added="$added"$'\n'"$(git show -U0 --no-color --diff-filter=ACMR --format= "$c" | grep '^+' | grep -v '^+++' || true)"
      done
    done
    ;;
  *)
    echo "usage: git-privacy-guard.sh [pre-commit|pre-push|install]" >&2
    exit 2
    ;;
esac

problems=()

while IFS= read -r p; do
  [ -z "$p" ] && continue
  if echo "$p" | grep -Eq "$personal_path_re" && ! echo "$p" | grep -Eq "$allowed_path_re"; then
    problems+=("personal file: $p")
  elif echo "$p" | grep -Eq "$secret_file_re"; then
    problems+=("key/certificate file: $p")
  fi
done <<< "$paths"

# The candidate's own identifiers, read from the gitignored profile (data root aware).
pii=$(node --input-type=module -e "
  import { readFileSync, existsSync } from 'fs';
  const { getProfilePath } = await import('./path-resolver.mjs');
  const yaml = await import('js-yaml');
  const file = getProfilePath();
  if (!existsSync(file)) process.exit(0);
  const c = (yaml.load(readFileSync(file, 'utf8')) || {}).candidate || {};
  const out = [];
  for (const v of [c.email, ...(c.alternate_emails || []), c.full_name, c.linkedin]) {
    if (typeof v === 'string' && v.trim().length >= 6) out.push('S:' + v.trim());
  }
  const digits = String(c.phone || '').replace(/\D/g, '');
  if (digits.length >= 10) out.push('P:' + digits.slice(-10));
  console.log(out.join('\n'));
" 2>/dev/null || true)

if [ -n "$added" ] && [ -n "$pii" ]; then
  added_digits=$(printf '%s' "$added" | tr -cd '0-9\n')
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    kind=${entry%%:*}
    value=${entry#*:}
    if [ "$kind" = "S" ] && printf '%s' "$added" | grep -Fqi -- "$value"; then
      problems+=("your personal detail appears in the change: '${value:0:3}…'")
    elif [ "$kind" = "P" ] && printf '%s' "$added_digits" | grep -Fq -- "$value"; then
      problems+=("your phone number appears in the change")
    fi
  done <<< "$pii"
fi

if [ -n "$added" ]; then
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    echo "$hit" | grep -Eqi "$placeholder_re" && continue
    problems+=("possible secret: ${hit:0:12}…")
  done < <(printf '%s' "$added" | grep -Eo "$secret_re" | sort -u)
fi

if [ ${#problems[@]} -gt 0 ]; then
  echo "" >&2
  echo "✋ privacy-guard blocked this $mode — this fork is PUBLIC." >&2
  for p in "${problems[@]}"; do echo "   - $p" >&2; done
  echo "" >&2
  if [ "$mode" = "pre-push" ]; then
    echo "   Remove it from the unpushed commit(s) first, e.g. git reset --soft <last-pushed-commit>, unstage, recommit." >&2
    echo "   Only if this is a false positive: git push --no-verify" >&2
  else
    echo "   Unstage with: git restore --staged <file>   (personal files stay local; they are gitignored)" >&2
    echo "   Only if this is a false positive: git commit --no-verify" >&2
  fi
  exit 1
fi
exit 0
