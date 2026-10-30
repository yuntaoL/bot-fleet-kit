#!/usr/bin/env bash
# Safe pull for concurrent runs (0.10.2): explicit fetch of origin/main + fast-forward only, serialized by a
# per-worktree lock (<git-dir>/fleet-sync.lock, shared with sync.sh), retried with backoff.
# Usage: fleet/scripts/pull.sh        (run inside your worktree; never merges or rebases your local commits)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
if [ -z "${FLEET_SYNC_LOCKED:-}" ] && command -v flock >/dev/null; then
  exec 9>"$(git rev-parse --git-dir)/fleet-sync.lock"; flock -w 300 9 || { echo "pull: lock busy for 300s" >&2; exit 1; }
  export FLEET_SYNC_LOCKED=1
fi
for i in 1 2 3 4 5; do
  if git fetch -q origin main && git merge -q --ff-only origin/main; then echo "pull: up to date with origin/main"; exit 0; fi
  sleep $((i*2))
done
echo "pull: could not fast-forward to origin/main (local commits or local changes?) — run sync.sh or tell the manager" >&2; exit 1
