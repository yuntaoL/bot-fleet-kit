#!/usr/bin/env bash
# Create fleet-owned files from template/defaults/ if missing. Never overwrites. Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
D=template/defaults
mkdir -p manager/roles manager/local manager/shared/state manager/shared/skills bots
grep -q '^# bot-fleet-template' README.md 2>/dev/null && cp $D/fleet/README.md README.md && echo "init: fleet README.md"
[ -f manager/CHANGELOG.md ] || { cp $D/fleet/CHANGELOG.md manager/CHANGELOG.md; echo "init: manager/CHANGELOG.md"; }
for f in $D/roles/*.md; do [ -f "manager/roles/$(basename "$f")" ] || { cp "$f" manager/roles/; echo "init: manager/roles/$(basename "$f")"; }; done
[ -f manager/overrides.md ] || { cp $D/fleet/overrides.md manager/overrides.md; echo "init: manager/overrides.md"; }
[ -f manager/shared/state/notified.json ] || { cp $D/fleet/notified.json manager/shared/state/notified.json; echo "init: notified.json"; }
[ -f manager/fleet.json ] || { printf '{\n  "schemaVersion": 2,\n  "owner": "",\n  "templateVersion": "%s",\n  "bots": []\n}\n' "$(cat template/VERSION)" > manager/fleet.json; echo "init: manager/fleet.json"; }
touch manager/local/.gitkeep manager/shared/skills/.gitkeep
