#!/usr/bin/env bash
# Replace the template's README/CHANGELOG with fleet ones (only if still the template copies) and ensure rules/local/. Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
grep -q '^# bot-fleet-template' README.md 2>/dev/null && cp templates/fleet/README.md README.md && echo "init: fleet README.md"
if [ ! -f CHANGELOG.md ] || head -1 CHANGELOG.md | grep -qx '# Changelog'; then cp templates/fleet/CHANGELOG.md CHANGELOG.md; echo "init: fleet CHANGELOG.md"; fi
mkdir -p rules/local; [ -n "$(ls -A rules/local 2>/dev/null)" ] || cp /dev/null rules/local/.gitkeep
