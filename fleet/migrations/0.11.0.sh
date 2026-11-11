#!/usr/bin/env bash
# 0.11.0: seed bots/<slug>/kb/ACTIONS.md and local/shared/SHARED-SKILLS.md when missing.
# Usage: bash fleet/migrations/0.11.0.sh [--dry-run]
# Idempotent. Never overwrites an existing file. Skips retired bots and bots with no folder.
# upgrade.sh runs this, then commits with BOT_FLEET_UPGRADE=1 (that path may write bots/ and the shared index).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[ -f local/fleet.json ] || { echo "0.11.0: no local/fleet.json, nothing to do"; exit 0; }
DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
DRY="$DRY" python3 - <<'PY'
import json, os, sys
dry = os.environ.get("DRY") == "1"
for p in ("templates/local/shared/SHARED-SKILLS.md", "templates/bot/kb/ACTIONS.md"):
    if not os.path.isfile(p):
        sys.exit(f"0.11.0: missing {p}")
shared_src = open("templates/local/shared/SHARED-SKILLS.md", "rb").read()
actions_src = open("templates/bot/kb/ACTIONS.md", "rb").read()
def write(dest, data):
    if os.path.lexists(dest):
        return
    if dry:
        print(f"would: write {dest}")
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(data)
    print(f"0.11.0: wrote {dest}")
write("local/shared/SHARED-SKILLS.md", shared_src)
fl = json.load(open("local/fleet.json"))
for b in fl.get("bots", []):
    if b.get("role") == "retired" or b.get("status") == "retired":
        continue
    s = b.get("slug") or ""
    if not s or not os.path.isdir(f"bots/{s}"):
        continue
    write(f"bots/{s}/kb/ACTIONS.md", actions_src)
PY
