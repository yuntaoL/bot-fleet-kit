#!/usr/bin/env bash
# Fleet-owned scaffolding: README/CHANGELOG, rules/roles defaults, rules/local/overrides.md, shared/state/notified.json. Never overwrites. Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
grep -q '^# bot-fleet-template' README.md 2>/dev/null && cp templates/fleet/README.md README.md && echo "init: fleet README.md"
if [ ! -f CHANGELOG.md ] || head -1 CHANGELOG.md | grep -qx '# Changelog'; then cp templates/fleet/CHANGELOG.md CHANGELOG.md; echo "init: fleet CHANGELOG.md"; fi
mkdir -p rules/roles rules/local shared/state
for f in templates/rules/roles/*.md; do [ -f "rules/roles/$(basename "$f")" ] || { cp "$f" rules/roles/; echo "init: rules/roles/$(basename "$f")"; }; done
[ -f rules/local/overrides.md ] || { cp templates/rules/local/overrides.md rules/local/; echo "init: rules/local/overrides.md"; }
rm -f rules/local/.gitkeep
[ -f shared/state/notified.json ] || { cp templates/fleet/notified.json shared/state/notified.json; echo "init: shared/state/notified.json"; }
