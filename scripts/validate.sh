#!/usr/bin/env bash
# Validate fleet.json and bot folders against schema/. Needs python3 + jsonschema (pip install jsonschema).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 - <<'PY'
import json, glob, os, sys
try:
    import jsonschema
except ImportError:
    sys.exit("validate: pip install jsonschema")
S = {n: json.load(open(f"schema/{n}.schema.json")) for n in ["fleet","profile","state","routine"]}
err = 0
def chk(path, s):
    global err
    try: jsonschema.validate(json.load(open(path)), S[s])
    except Exception as e: err += 1; print(f"FAIL {path}: {str(e).splitlines()[0]}")
chk("templates/bot/profile.json","profile"); chk("templates/bot/state.json","state")
for r in glob.glob("templates/bot/routines/*.json"): chk(r,"routine")
if os.path.exists("fleet.json"):
    chk("fleet.json","fleet")
    for b in json.load(open("fleet.json")).get("bots",[]):
        d=f"bots/{b['slug']}"
        if not os.path.isdir(d): err+=1; print(f"FAIL missing {d}"); continue
        chk(f"{d}/profile.json","profile")
        if os.path.exists(f"{d}/state.json"): chk(f"{d}/state.json","state")
        for r in glob.glob(f"{d}/routines/*.json"): chk(r,"routine")
print("validate: OK" if not err else f"validate: {err} error(s)"); sys.exit(1 if err else 0)
PY
