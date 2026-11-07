#!/usr/bin/env bash
# Schema-check staged configuration JSON before commit.
# Index blobs only (`git show :path`), never the working tree, and only staged paths:
#   bots/<slug>/routines/*.json  -> fleet/schema/routine.schema.json
#   bots/<slug>/bot.json         -> fleet/schema/bot.schema.json
#   local/fleet.json             -> fleet/schema/fleet.schema.json
# Other staged files (journals, profile, state, prose) are ignored.
# Exit 1 with a message on stderr when a staged blob fails its schema.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export PYTHONDONTWRITEBYTECODE=1
exec python3 fleet/scripts/schema_check.py staged
