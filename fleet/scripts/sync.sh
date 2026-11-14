#!/usr/bin/env bash
# The sync loop, run inside YOUR worktree: fetch, rebase onto origin/main, commit only paths OWNERS.json grants you, push, retry.
# Usage: fleet/scripts/sync.sh "<commit message>" [paths...]
# Stages with `git add --` (never -A), then commits the whole index:
#   paths given: exactly those paths
#   no paths, manager: local/ , README.md , and bots/<fleet.bot>/ when that directory exists
#     (local/shared/SHARED-SKILLS.md and local/prompts/ are builder-owned and are unstaged again)
#   no paths, active builder (HEAD:local/fleet.json role builder, status not retired or paused):
#     bots/<fleet.bot>/, local/shared/SHARED-SKILLS.md, and local/prompts/
#   no paths, anyone else: bots/<fleet.bot>/
# Every sync also stages bots/<fleet.bot>/journal (when that directory exists). Path arguments
# used to leave the journal unstaged, and rebase then refused. A path sync does not stage the
# board: a half-edited board must not ride along. A default sync (no paths) stages the board
# when this bot may write that change.
# A foreign path already staged is unstaged. A bot path whose mode is not 100644
# stays staged and the commit is refused. owners.py check runs here even when the hook is off.
# Untracked files inside the staged paths are staged. A tracked edit outside them stays unstaged;
# git rebase then refuses to start, so that run does not push.
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
if [ "$default" = 1 ] && [ "$role" = manager ]; then
  git reset -q -- local/shared/SHARED-SKILLS.md 2>/dev/null || true
  git reset -q -- local/prompts 2>/dev/null || true
fi
# Role and status come from HEAD, same as owners.py. An unstaged roster edit does not count.
active_builder=0
if [ "$default" = 1 ] && ME="$me" python3 -c '
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
'; then active_builder=1; fi
if [ "$active_builder" = 1 ] && [ -f local/shared/SHARED-SKILLS.md ]; then git add -- local/shared/SHARED-SKILLS.md; fi
if [ "$active_builder" = 1 ] && [ -d local/prompts ]; then git add -- local/prompts; fi
# Journal, with or without path arguments. Leaving it unstaged makes rebase refuse.
if [ -d "bots/$me/journal" ]; then git add -- "bots/$me/journal" 2>/dev/null || true; fi
# Default sync only. A path sync must not pick up a half-edited board.
if [ "$default" = 1 ]; then
  board_path="$(BOT_NAME="$me" BOT_ROLE="$role" python3 fleet/scripts/owners.py board-stage 2>/dev/null || true)"
  if [ -n "$board_path" ]; then git add -- "$board_path"; fi
fi
# Drop a foreign path before the schema check, so another bot's invalid JSON does not block this commit.
# A non-100644 path stays in the index: the schema check and the mode check both have to see it.
mode_bad=0
while IFS=$'\t' read -r st path; do
  [ -n "${path:-}" ] || continue
  err="$(printf '%s\t%s\n' "$st" "$path" | BOT_NAME="$me" BOT_ROLE="$role" python3 fleet/scripts/owners.py check 2>&1)" && rc=0 || rc=$?
  if [ "$rc" != 0 ]; then
    if printf '%s\n' "$err" | grep -q 'not a regular file'; then
      printf '%s\n' "$err" >&2
      mode_bad=1
    else
      # A symlink or gitlink outside this bot's tree is still refused. Unstaging it would
      # put the previous blob back and hide the mode from the schema check.
      mode="$(git ls-files --stage -- "$path" | awk 'NR==1 { print $1 }')"
      if [ -n "$mode" ] && [ "$mode" != "100644" ] && [ "$mode" != "100755" ]; then
        printf 'check-boundary: %s: staged mode %s is not a regular file (100644); symlink and gitlink are refused\n' "$path" "$mode" >&2
        mode_bad=1
      else
        git reset -q -- "$path" 2>/dev/null || true
      fi
    fi
  fi
done < <(git diff --cached --name-status --no-renames)
if ! git diff --cached --quiet; then
  if ! fleet/scripts/check-staged-config.sh; then
    echo "sync: refusing commit and push; staged configuration JSON failed schema check" >&2
    exit 1
  fi
fi
if [ "$mode_bad" = 1 ]; then
  echo "sync: refusing commit and push; ownership check failed" >&2
  exit 1
fi
if ! git diff --cached --name-status --no-renames | BOT_NAME="$me" BOT_ROLE="$role" python3 fleet/scripts/owners.py check; then
  echo "sync: refusing commit and push; ownership check failed" >&2
  exit 1
fi
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
