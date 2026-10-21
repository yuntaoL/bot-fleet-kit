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
import re
for r in ["rules/common.md","rules/README.md"]+[f"templates/rules/roles/{x}.md" for x in ["manager","builder","worker","retired"]]:
    if not os.path.exists(r): err+=1; print(f"FAIL missing {r}")
if os.path.exists("fleet.json"):
    for x in ["manager","builder","worker","retired"]:
        if not os.path.exists(f"rules/roles/{x}.md"): err+=1; print(f"FAIL missing rules/roles/{x}.md")
    ov="rules/local/overrides.md"
    if os.path.exists(ov):
        txt=re.sub(r"<!--.*?-->","",open(ov).read(),flags=re.S)
        for e in re.split(r"(?m)^## ",txt)[1:]:
            for k in ["- Date:","- Approved by:","- Approval:"]:
                if k not in e: err+=1; print(f"FAIL overrides entry '{e.splitlines()[0]}' missing '{k}'")
            m=re.search(r"- Date:\s*(\d{4}-\d{2}-\d{2})",e)
            if not m: err+=1; print(f"FAIL overrides entry '{e.splitlines()[0]}' needs Date YYYY-MM-DD")
    for b in json.load(open("fleet.json")).get("bots",[]):
        if b["role"]!="retired" and not os.path.exists(f"bots/{b['slug']}/rules.md"): err+=1; print(f"FAIL missing bots/{b['slug']}/rules.md")
if os.path.exists("fleet.json"):
    fl=json.load(open("fleet.json")); roles=[b["role"] for b in fl.get("bots",[])]
    if fl.get("bots") and roles.count("manager")!=1: err+=1; print("FAIL fleet.json needs exactly one manager")
    for b in fl.get("bots",[]):
        pp=f"bots/{b['slug']}/profile.json"
        if os.path.exists(pp) and json.load(open(pp)).get("role",b["role"])!=b["role"]: err+=1; print(f"FAIL role mismatch {b['slug']}")
print("validate: OK" if not err else f"validate: {err} error(s)"); sys.exit(1 if err else 0)
PY
