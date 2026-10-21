#!/usr/bin/env bash
# The sync loop, run inside YOUR worktree: fetch, rebase onto origin/main, commit only paths OWNERS.json grants you, push, retry.
# Usage: template/scripts/sync.sh "<commit message>" [paths...]   (default paths: bots/<fleet.bot>/; the manager also gets manager/ and README.md)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
msg="${1:?usage: sync.sh \"message\" [paths...]}"; shift || true
me="${BOT_NAME:-$(git config --get fleet.bot || true)}"; role="${BOT_ROLE:-$(git config --get fleet.role || true)}"
[ -n "$me" ] || { echo "sync: no identity; run inside your worktree or set BOT_NAME/BOT_ROLE" >&2; exit 1; }
if [ $# -eq 0 ]; then if [ "$role" = manager ]; then set -- manager/ README.md; [ -d "bots/$me" ] && set -- "$@" "bots/$me/"; else set -- "bots/$me/"; fi; fi
git add -- "$@"
git diff --cached --quiet && { echo "sync: no change"; git fetch -q origin; git rebase -q origin/main 2>/dev/null || true; exit 0; }
BOT_NAME="$me" BOT_ROLE="$role" git commit -qm "$me: $msg"
for i in 1 2 3 4 5; do
  git fetch -q origin
  if git rebase -q origin/main; then git push -q origin HEAD:main && { echo "sync: pushed"; exit 0; }
  else git rebase --abort; echo "sync: rebase conflict (outside your paths?) — tell the manager" >&2; exit 1; fi
  sleep $((i*3))
done
echo "sync: push failed after retries" >&2; exit 1
