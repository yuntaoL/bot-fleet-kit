#!/usr/bin/env bash
# pre-commit hook: enforce fleet/OWNERS.json. Identity from env (BOT_NAME, BOT_ROLE) or per-worktree git config (fleet.bot, fleet.role).
# local/shared/SHARED-SKILLS.md and local/prompts/ are builder-owned: owners.py allows the bot whose local/fleet.json role is builder.
# upgrade.sh may write the shared index, and a manager may only add that file when it is the pristine template stub.
# Bots' own files under bots/<slug>/ stay owned by those bots.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
git diff --cached --name-status --no-renames | python3 "$root/fleet/scripts/owners.py" check
