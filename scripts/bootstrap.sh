#!/usr/bin/env bash
# Install pre-commit boundary hook, create fleet.json if missing.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
ln -sf ../../scripts/check-boundary.sh .git/hooks/pre-commit
chmod +x scripts/*.sh
[ -f fleet.json ] || printf '{\n  "schemaVersion": 1,\n  "templateVersion": "%s",\n  "bots": []\n}\n' "$(cat VERSION)" > fleet.json
echo "bootstrap: hook installed. Commit with BOT_NAME=<slug> (bots) or BOT_ROLE=manager (fleet manager)."
