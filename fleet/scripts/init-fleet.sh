#!/usr/bin/env bash
# Create fleet-owned files from templates/ if missing. Never overwrites. Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
D=templates
mkdir -p local/rules local/roles local/shared/state local/shared/skills bots
grep -qE '^# bot-fleet-(kit|template)$' README.md 2>/dev/null && cp $D/local/README.md README.md && echo "init: fleet README.md"
[ -f local/CHANGELOG.md ] || { cp $D/local/CHANGELOG.md local/CHANGELOG.md; echo "init: local/CHANGELOG.md"; }
[ -f local/overrides.md ] || { cp $D/local/overrides.md local/overrides.md; echo "init: local/overrides.md"; }
[ -f local/shared/state/notified.json ] || { cp $D/local/notified.json local/shared/state/notified.json; echo "init: notified.json"; }
[ -f local/fleet.json ] || { printf '{\n  "schemaVersion": 2,\n  "owner": "",\n  "owner_name": "",\n  "templateVersion": "%s",\n  "bots": []\n}\n' "$(cat fleet/VERSION)" > local/fleet.json; echo "init: local/fleet.json"; }
mkdir -p local/registry
[ -f local/registry/INDEX.md ] || { cp $D/local/registry/INDEX.md local/registry/INDEX.md; echo "init: local/registry/INDEX.md"; }
[ -f local/shared/INDEX.md ] || { cp $D/local/shared-INDEX.md local/shared/INDEX.md; echo "init: local/shared/INDEX.md"; }
touch local/rules/.gitkeep local/shared/skills/.gitkeep
[ -d examples ] && echo "note: examples/ is template-repo only (fleets fetch examples with add-example.sh); remove it by hand if unneeded: git rm -r examples" || true
