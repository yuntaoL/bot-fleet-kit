#!/usr/bin/env bash
# pre-commit hook: enforce fleet/OWNERS.json. Identity from env (BOT_NAME, BOT_ROLE) or per-worktree git config (fleet.bot, fleet.role).
# local/shared/SHARED-SKILLS.md is builder-owned: owners.py allows the bot whose local/fleet.json role is builder, upgrade.sh, and a manager add of the pristine template stub.
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
git diff --cached --name-status --no-renames | python3 "$root/fleet/scripts/owners.py" check
