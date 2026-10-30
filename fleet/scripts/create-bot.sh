#!/usr/bin/env bash
# Usage: fleet/scripts/create-bot.sh <slug> [--worktree-base DIR]     (builder or manager; 0.10.5+)
# Git side of creating a bot whose row the manager already added to local/fleet.json (slug, name, id, role, status):
# copies templates/bot to bots/<slug>/ (drops the example routine), generates bots/<slug>/bot.json (bot-json.sh)
# renders bots/<slug>/THIN-PROMPT.md (render-prompt.sh) and writes <worktree>/.bot (bot-pointer.sh) if the worktree exists. Commits nothing; review, then sync.sh "add <slug>" bots/<slug>/.
# Creating the platform bot and pasting the prompt stay manual, with the owner's yes.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
slug="${1:?usage: create-bot.sh <slug> [--worktree-base DIR]}"; shift
[[ "$slug" =~ ^[a-z0-9-]+$ ]] || { echo "create-bot: bad slug '$slug'" >&2; exit 2; }
python3 -c "import json,sys;sys.exit(0 if any(b['slug']=='$slug' for b in json.load(open('local/fleet.json'))['bots']) else 1)" \
  || { echo "create-bot: add '$slug' to local/fleet.json first (manager)" >&2; exit 1; }
[ ! -e "bots/$slug" ] || { echo "create-bot: bots/$slug exists" >&2; exit 1; }
cp -r templates/bot "bots/$slug"; rm -f "bots/$slug/routines/example.json"
fleet/scripts/bot-json.sh "$slug" "$@"
fleet/scripts/render-prompt.sh "$slug" "$@"
# 0.10.5+: the bot's worktree gets its .bot pointer now if it exists (worktree.sh writes it otherwise)
wt="$(python3 -c "import json;print(json.load(open('bots/$slug/bot.json'))['worktree'])")"
[ -e "$wt/.git" ] && fleet/scripts/bot-pointer.sh "$slug" "$wt" || echo "create-bot: no worktree $wt yet; worktree.sh $slug writes its .bot"
echo "create-bot: bots/$slug ready (not committed)"
