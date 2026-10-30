#!/usr/bin/env bash
# Usage: fleet/scripts/worktree.sh <slug> [base-dir]     (run from the shared clone, as any user of the machine)
#        fleet/scripts/worktree.sh --all [base-dir]       (every non-retired bot in local/fleet.json)
# Gives each bot its own git worktree (default /home/box/bot-fleet-worktrees/<slug>) on branch wt/<slug>,
# tracking origin/main, with per-worktree identity (fleet.bot, fleet.role) and the untracked pointer <wt>/.bot (0.10.5+). Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
base="${2:-${BOT_FLEET_WORKTREES:-$(dirname "$PWD")/bot-fleet-worktrees}}"
git config extensions.worktreeConfig true
git config branch.main.remote origin; git config --replace-all branch.main.merge refs/heads/main
git fetch -q origin
mk(){ slug="$1"
  role=$(python3 -c "import json,sys;print(next(b['role'] for b in json.load(open('local/fleet.json'))['bots'] if b['slug']=='$slug'))")
  [ "$role" = retired ] && { echo "skip $slug (retired)"; return; }
  wt="$base/$slug"; mkdir -p "$base"
  if [ ! -d "$wt/.git" ] && [ ! -f "$wt/.git" ]; then
    git worktree add -q -B "wt/$slug" "$wt" origin/main
  fi
  git -C "$wt" branch -q --set-upstream-to=origin/main "wt/$slug"
  git -C "$wt" config --worktree fleet.bot "$slug"
  git -C "$wt" config --worktree fleet.role "$role"
  git -C "$wt" config --worktree push.default upstream
  fleet/scripts/bot-pointer.sh "$slug" "$wt" >/dev/null   # 0.10.5+: untracked <wt>/.bot -> bots/<slug>/bot.json
  echo "worktree: $wt (branch wt/$slug -> origin/main, role $role)"
}
if [ "${1:?usage: worktree.sh <slug>|--all [base-dir]}" = "--all" ]; then
  for s in $(python3 -c "import json;print(' '.join(b['slug'] for b in json.load(open('local/fleet.json'))['bots']))"); do mk "$s"; done
else mk "$1"; fi
fleet/scripts/install-hook.sh
