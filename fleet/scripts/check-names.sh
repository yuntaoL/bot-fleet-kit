#!/usr/bin/env bash
# Usage: fleet/scripts/check-names.sh [profiles-dir]      Read-only. Rename-drift check (0.9.1, rename-bot skill).
# Compares each non-retired bot's live display name with local/fleet.json `name` (matched by `id`) and its
# local/registry/INDEX.md row. Live names come from <profiles-dir>/<id>/profile.json `name`
# (default BOT_FLEET_PROFILES or /home/box/agent-data/agents). Prints one DRIFT line per mismatch; exit 3 if any, 0 if none.
# Changes nothing: on drift the builder notifies the manager (old + new name); the manager asks the owner.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
P="${1:-${BOT_FLEET_PROFILES:-/home/box/agent-data/agents}}"
P="$P" python3 - <<'PY'
import json, os, sys
P=os.environ["P"]; F="local/fleet.json"
if not os.path.exists(F) or not os.path.isdir(P): print(f"check-names: skipped (no {F} or {P})"); sys.exit(0)
reg=open("local/registry/INDEX.md").read() if os.path.exists("local/registry/INDEX.md") else ""
d=0
for b in json.load(open(F)).get("bots",[]):
    if b.get("role")=="retired" or b.get("status")=="retired": continue
    pf=os.path.join(P,b.get("id",""),"profile.json")
    if not os.path.exists(pf): print(f"check-names: {b['slug']}: no live profile ({pf})"); continue
    live=(json.load(open(pf)).get("name") or "").strip()
    if live and live!=b["name"]:
        d+=1; print(f"DRIFT {b['slug']}: fleet.json name '{b['name']}' != live name '{live}' (id {b['id']})")
    elif reg and live and b["name"] in reg.replace(live,"") and live not in reg:
        d+=1; print(f"DRIFT {b['slug']}: live name '{live}' missing from local/registry/INDEX.md (row still says '{b['name']}')")
print(f"check-names: {d} drift(s)" if d else "check-names: OK")
sys.exit(3 if d else 0)
PY
