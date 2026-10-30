#!/usr/bin/env bash
# 0.10.5: one bots/<slug>/bot.json per bot (identity + environment), so prompts and routines reference it instead of copying it.
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
    [ -d "bots/$s" ] && [ ! -f "bots/$s/bot.json" ] && echo "would: write bots/$s/bot.json"; done; exit 0
fi
fleet/scripts/bot-json.sh --all
