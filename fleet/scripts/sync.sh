#!/usr/bin/env bash
# The sync loop, run inside YOUR worktree: fetch, rebase onto origin/main, commit only paths OWNERS.json grants you, push, retry.
# Usage: fleet/scripts/sync.sh "<commit message>" [paths...]   (default paths: bots/<fleet.bot>/; the manager also gets local/ and README.md)
# 0.10.2: serialized per worktree by flock on <git-dir>/fleet-sync.lock (shared with pull.sh); always fetches origin main
# explicitly; a rejected push is retried with backoff and jitter.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
msg="${1:?usage: sync.sh \"message\" [paths...]}"; shift || true
me="${BOT_NAME:-$(git config --get fleet.bot || true)}"; role="${BOT_ROLE:-$(git config --get fleet.role || true)}"
[ -n "$me" ] || { echo "sync: no identity; run inside your worktree or set BOT_NAME/BOT_ROLE" >&2; exit 1; }
if [ -z "${FLEET_SYNC_LOCKED:-}" ] && command -v flock >/dev/null; then
  exec 9>"$(git rev-parse --git-dir)/fleet-sync.lock"; flock -w 300 9 || { echo "sync: lock busy for 300s" >&2; exit 1; }
  export FLEET_SYNC_LOCKED=1
fi
if [ $# -eq 0 ]; then if [ "$role" = manager ]; then set -- local/ README.md; [ -d "bots/$me" ] && set -- "$@" "bots/$me/"; else set -- "bots/$me/"; fi; fi
git add -- "$@"
if git diff --cached --quiet; then
  echo "sync: no change"; git fetch -q origin main || true; git rebase -q origin/main 2>/dev/null || git rebase --abort 2>/dev/null || true; exit 0
fi
BOT_NAME="$me" BOT_ROLE="$role" git commit -qm "$me: $msg"
for i in 1 2 3 4 5 6; do
  if ! git fetch -q origin main; then sleep $((i*2 + RANDOM % 3)); continue; fi
  if git rebase -q origin/main; then git push -q origin HEAD:main && { echo "sync: pushed"; exit 0; }
  else git rebase --abort; echo "sync: rebase conflict (outside your paths?) — tell the manager" >&2; exit 1; fi
  echo "sync: push rejected, retry $i" >&2; sleep $((i*2 + RANDOM % 3))
done
echo "sync: push failed after retries" >&2; exit 1
