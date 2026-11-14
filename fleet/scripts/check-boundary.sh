#!/usr/bin/env bash
# pre-commit hook: enforce fleet/OWNERS.json. Identity from env (BOT_NAME, BOT_ROLE) or per-worktree git config (fleet.bot, fleet.role).
# local/shared/SHARED-SKILLS.md and local/prompts/ are builder-owned: owners.py allows the bot whose local/fleet.json role is builder.
# upgrade.sh may write the shared index, and a manager may only add that file when it is the pristine template stub.
# Bots' own files under bots/<slug>/ stay owned by those bots.
# When HEAD:local/fleet.json sets board, the manager and the coordinator may create or delete that file,
# and every non-retired bot may update it. Card ownership (a bot only touches its own cards) is a convention
# the coordinator's scan audits; this hook is file-level and cannot see rows. Omit board and the path stays manager-owned.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
git diff --cached --name-status --no-renames | python3 "$root/fleet/scripts/owners.py" check
