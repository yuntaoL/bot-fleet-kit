#!/usr/bin/env bash
# 0.10.5: one bots/<slug>/bot.json per bot (identity + environment), so prompts and routines reference it instead of copying it,
# and an untracked pointer <worktree>/.bot (bots/<slug>/bot.json) in every bot worktree, so a bot needs only its worktree path.
# Usage: bash fleet/migrations/0.10.5.sh [--dry-run]   (upgrade.sh runs it; idempotent; never overwrites an existing bot.json)
# Values come from the registry (local/fleet.json: name, role, id, owner_name, optional timezone/fleet_repo) and each bot's
# profile.json title; see fleet/scripts/bot-json.sh. Bots without a bots/<slug>/ folder are skipped. Live prompts are NOT
# changed: re-render (render-prompt.sh / render-routine-prompt.sh) and re-paste one bot at a time with the owner's yes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[ -f local/fleet.json ] || { echo "0.10.5: no local/fleet.json, nothing to do"; exit 0; }
owner="$(python3 -c "import json;print((json.load(open('local/fleet.json')).get('owner_name') or '').strip())")"
[ -n "$owner" ] || { echo "0.10.5: WARNING owner_name is empty in local/fleet.json; set it, then run fleet/scripts/bot-json.sh --all"; exit 0; }
if [ "${1:-}" = --dry-run ]; then
  for s in $(python3 -c "import json;print(' '.join(b['slug'] for b in json.load(open('local/fleet.json'))['bots']))"); do
    [ -d "bots/$s" ] && [ ! -f "bots/$s/bot.json" ] && echo "would: write bots/$s/bot.json"
  done
  git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r wt; do s="$(git -C "$wt" config --worktree --get fleet.bot 2>/dev/null || true)"
    [ -n "$s" ] && [ "$(cat "$wt/.bot" 2>/dev/null)" != "bots/$s/bot.json" ] && echo "would: write $wt/.bot"; true; done; exit 0
fi
fleet/scripts/bot-json.sh --all
# .bot pointer in every bot worktree; the slug comes from the worktree's own fleet.bot config (worktree.sh), not its dir name
wts(){ git worktree list --porcelain | sed -n 's/^worktree //p' | while read -r wt; do
  s="$(git -C "$wt" config --worktree --get fleet.bot 2>/dev/null || true)"; [ -n "$s" ] && [ -f "bots/$s/bot.json" ] && echo "$s $wt"; true; done; }
wts | while read -r s wt; do fleet/scripts/bot-pointer.sh "$s" "$wt"; done
