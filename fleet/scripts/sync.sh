#!/usr/bin/env bash
# The sync loop, run inside YOUR worktree: fetch, rebase onto origin/main, commit only paths OWNERS.json grants you, push, retry.
# Usage: fleet/scripts/sync.sh "<commit message>" [paths...]
# Stages with `git add --` (never -A), then commits the whole index:
#   paths given: exactly those paths
#   no paths, manager: local/ , README.md , and bots/<fleet.bot>/ when that directory exists
#     (local/shared/SHARED-SKILLS.md is builder-owned and is unstaged again)
#   no paths, active builder (HEAD:local/fleet.json role builder, status not retired or paused):
#     bots/<fleet.bot>/ and local/shared/SHARED-SKILLS.md
#   no paths, anyone else: bots/<fleet.bot>/
# Untracked files inside those paths are staged. Unstaged and untracked files outside them are left untouched.
# A tracked edit left outside them stays unstaged; git rebase then refuses to start (existing), so that run does not push.
# 0.10.8: before commit, staged bots/<slug>/routines/*.json, bots/<slug>/bot.json and local/fleet.json are
# schema-checked from index blobs (the instance and fleet/schema/*.schema.json are one snapshot).
# A symlink, gitlink, or other non-regular mode is refused. A failure refuses the commit and the push.
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
default=0
if [ $# -eq 0 ]; then
  default=1
  if [ "$role" = manager ]; then set -- local/ README.md; [ -d "bots/$me" ] && set -- "$@" "bots/$me/"; else set -- "bots/$me/"; fi
fi
git add -- "$@"
# Shared skills index is builder-owned. Drop it from a manager's default local/ add
# so the rest of local/ still commits. Stage it on the builder's default sync.
if [ "$default" = 1 ] && [ "$role" = manager ]; then git reset -q -- local/shared/SHARED-SKILLS.md 2>/dev/null || true; fi
# Role and status come from HEAD, same as owners.py. An unstaged roster edit does not count.
if [ "$default" = 1 ] && [ -f local/shared/SHARED-SKILLS.md ] && ME="$me" python3 -c '
import json, os, subprocess, sys
s = os.environ.get("ME", "")
try: raw = subprocess.check_output(["git", "show", "HEAD:local/fleet.json"])
except Exception: sys.exit(1)
try: fl = json.loads(raw.decode())
except Exception: sys.exit(1)
ok = False
for b in fl.get("bots", []):
    if b.get("slug") == s and b.get("role") == "builder" and (b.get("status") or "active") not in ("retired", "paused"):
        ok = True
sys.exit(0 if ok else 1)
'; then git add -- local/shared/SHARED-SKILLS.md; fi
if git diff --cached --quiet; then
  echo "sync: no change"; git fetch -q origin main || true; git rebase -q origin/main 2>/dev/null || git rebase --abort 2>/dev/null || true; exit 0
fi
if ! fleet/scripts/check-staged-config.sh; then
  echo "sync: refusing commit and push; staged configuration JSON failed schema check" >&2
  exit 1
fi
BOT_NAME="$me" BOT_ROLE="$role" git commit -qm "$me: $msg"
for i in 1 2 3 4 5 6; do
  if ! git fetch -q origin main; then sleep $((i*2 + RANDOM % 3)); continue; fi
  if git rebase -q origin/main; then git push -q origin HEAD:main && { echo "sync: pushed"; exit 0; }
  else git rebase --abort; echo "sync: rebase conflict (outside your paths?) — tell the manager" >&2; exit 1; fi
  echo "sync: push rejected, retry $i" >&2; sleep $((i*2 + RANDOM % 3))
done
echo "sync: push failed after retries" >&2; exit 1
