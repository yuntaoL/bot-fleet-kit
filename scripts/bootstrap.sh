#!/usr/bin/env bash
# Usage: scripts/bootstrap.sh [template-repo-url]
# Idempotent first-time setup for a fleet repo (see README "Adoption guide").
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config user.email >/dev/null || { echo "bootstrap: set git identity first: git config user.name '...' && git config user.email '...'" >&2; exit 1; }
chmod +x scripts/*.sh
ln -sf ../../scripts/check-boundary.sh .git/hooks/pre-commit
if [ -n "${1:-}" ] && ! git remote get-url upstream >/dev/null 2>&1; then git remote add upstream "$1"; fi
git remote get-url upstream >/dev/null 2>&1 || echo "bootstrap: no upstream remote yet; pass the template URL to enable upgrades"
python3 -c "import jsonschema" 2>/dev/null || pip install -q jsonschema 2>/dev/null || pip install -q --user --break-system-packages jsonschema 2>/dev/null || echo "bootstrap: install jsonschema for validate.sh"
[ -f templates/fleet/README.md ] && [ "$(basename "$(git remote get-url origin 2>/dev/null)" .git)" != "bot-fleet-template" ] && scripts/init-fleet-docs.sh
if [ ! -f fleet.json ]; then
  printf '{\n  "schemaVersion": 2,\n  "owner": "",\n  "templateVersion": "%s",\n  "bots": []\n}\n' "$(cat VERSION)" > fleet.json
  git add -A fleet.json README.md CHANGELOG.md rules shared && BOT_ROLE=manager git commit -qm "manager: bootstrap fleet.json" && echo "bootstrap: committed fleet.json (push when ready)"
fi
echo "bootstrap: done. Bots commit with BOT_NAME=<slug>; the fleet manager with BOT_ROLE=manager."
