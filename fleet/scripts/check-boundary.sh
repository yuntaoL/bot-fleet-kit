#!/usr/bin/env bash
# pre-commit hook: enforce fleet/OWNERS.json. Identity from env (BOT_NAME, BOT_ROLE) or per-worktree git config (fleet.bot, fleet.role).
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
git diff --cached --name-status --no-renames | python3 "$root/fleet/scripts/owners.py" check
