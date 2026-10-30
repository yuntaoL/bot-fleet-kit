#!/usr/bin/env bash
# Usage: template/scripts/check-routines.sh [agent-data-dir]     Read-only (0.9.2+). Thin-routine drift check.
# For each non-retired bot, compares every live routine prompt it can read
# (<agent-data-dir>/<id>/automations/*.json with "name" and "prompt"; default AGENT_DATA or /home/box/agent-data/agents)
# with the rendered thin prompt from render-routine-prompt.sh (0.9.4+: the minimal prompt pointing at template/rules/routines.md). Also flags routine files with only a legacy `prompt`.
# Unreadable live data is skipped, not failed. Prints WARN lines; exit 0 always (audit input, not a gate).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
AG="${1:-${AGENT_DATA:-/home/box/agent-data/agents}}"
AG="$AG" python3 - <<'PY'
import json, os, glob, subprocess
AG=os.environ["AG"]; F="manager/fleet.json"; w=0
if not os.path.exists(F): print("check-routines: skipped (no manager/fleet.json)"); raise SystemExit
norm=lambda s: "\n".join(l.rstrip() for l in s.strip().splitlines() if not l.startswith("<!-- Rendered"))
for b in json.load(open(F)).get("bots",[]):
    if b.get("role")=="retired" or b.get("status")=="retired": continue
    for f in sorted(glob.glob(f"bots/{b['slug']}/routines/*.json")):
        r=json.load(open(f))
        if "prompt" in r and not ("steps" in r or "stepsFile" in r): w+=1; print(f"WARN {f}: legacy fat prompt; move it into `steps` and use the thin routine prompt")
    live=os.path.join(AG,b.get("id",""),"automations")
    if not os.path.isdir(live): continue
    for a in sorted(glob.glob(f"{live}/*.json")):
        try: j=json.load(open(a)); name=j.get("name",""); prompt=j.get("prompt","")
        except Exception: continue
        if not name or not prompt: continue
        slugname=name.strip().lower().replace(" ","-")
        rr=subprocess.run(["template/scripts/render-routine-prompt.sh",b["slug"],slugname,"--stdout"],capture_output=True,text=True)
        if rr.returncode!=0: w+=1; print(f"WARN {b['slug']}: live routine '{name}' has no bots/{b['slug']}/routines/{slugname}.json"); continue
        if norm(prompt)!=norm(rr.stdout): w+=1; print(f"WARN {b['slug']}: live routine '{name}' is not the rendered thin prompt (render-routine-prompt.sh {b['slug']} {slugname})")
print(f"check-routines: {w} warning(s)" if w else "check-routines: OK")
PY
