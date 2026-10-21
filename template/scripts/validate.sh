#!/usr/bin/env bash
# Schema + ownership checks. Needs python3 + jsonschema.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
err=0
python3 template/scripts/owners.py audit || err=1
python3 - <<'PY' || err=1
import json, glob, os, re, sys
try: import jsonschema
except ImportError: sys.exit("validate: pip install jsonschema")
S = {n: json.load(open(f"template/schema/{n}.schema.json")) for n in ["fleet","profile","state","routine","owners"]}
err = 0
def chk(path, s):
    global err
    try: jsonschema.validate(json.load(open(path)), S[s])
    except Exception as e: err += 1; print(f"FAIL {path}: {str(e).splitlines()[0]}")
chk("template/OWNERS.json","owners")
D="template/defaults"
chk(f"{D}/bot/profile.json","profile"); chk(f"{D}/bot/state.json","state")
for r in glob.glob(f"{D}/bot/routines/*.json"): chk(r,"routine")
for r in ["template/rules/common.md","template/rules/README.md"]+[f"{D}/roles/{x}.md" for x in ["manager","builder","worker","retired"]]:
    if not os.path.exists(r): err+=1; print(f"FAIL missing {r}")
F="manager/fleet.json"
if os.path.exists(F):
    chk(F,"fleet"); fl=json.load(open(F))
    for x in ["manager","builder","worker","retired"]:
        if not os.path.exists(f"manager/roles/{x}.md"): err+=1; print(f"FAIL missing manager/roles/{x}.md")
    if fl.get("bots") and [b["role"] for b in fl["bots"]].count("manager")!=1: err+=1; print("FAIL fleet.json needs exactly one manager")
    ov="manager/overrides.md"
    if os.path.exists(ov):
        txt=re.sub(r"<!--.*?-->","",open(ov).read(),flags=re.S)
        for e in re.split(r"(?m)^## ",txt)[1:]:
            for k in ["- Date:","- Approved by:","- Approval:"]:
                if k not in e: err+=1; print(f"FAIL overrides entry '{e.splitlines()[0]}' missing '{k}'")
    for b in fl.get("bots",[]):
        d=f"bots/{b['slug']}"
        if not os.path.isdir(d): err+=1; print(f"FAIL missing {d}"); continue
        chk(f"{d}/profile.json","profile")
        if os.path.exists(f"{d}/state.json"): chk(f"{d}/state.json","state")
        for r in glob.glob(f"{d}/routines/*.json"): chk(r,"routine")
        if b["role"]!="retired" and not os.path.exists(f"{d}/rules.md"): err+=1; print(f"FAIL missing {d}/rules.md")
sys.exit(1 if err else 0)
PY
[ $err = 0 ] && echo "validate: OK" || { echo "validate: FAILED"; exit 1; }
