#!/usr/bin/env bash
# Usage: fleet/scripts/bot-json.sh <slug>|--all [--refresh] [--worktree-base DIR] [--stdout]      (0.10.5+)
#        fleet/scripts/bot-json.sh --mirror <slug>     manager: copy display_name/role from bots/<slug>/bot.json into local/fleet.json
# Generates bots/<slug>/bot.json from templates/bot.json.tmpl. Values: display_name/role/agent_id from local/fleet.json,
# title from bots/<slug>/profile.json, owner_name/timezone/fleet_repo from local/fleet.json (timezone falls back to $TZ,
# /etc/timezone, then UTC; fleet_repo to the origin URL without credentials), kit_version from fleet/VERSION,
# worktree = <worktree base>/<slug>. Never overwrites an existing bot.json; --refresh only updates kit_version
# (upgrade-run.sh runs it after each upgrade) and keeps every other value.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
base="${BOT_FLEET_WORKTREES:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/../bot-fleet-worktrees}"
which=""; refresh=""; out=""; mirror=""
while [ $# -gt 0 ]; do case "$1" in --all) which=--all;; --refresh) refresh=1;; --stdout) out=-;; --mirror) mirror=1;; --worktree-base) base="$2"; shift;; -*) echo "unknown arg $1" >&2; exit 2;; *) which="$1";; esac; shift; done
[ -n "$which" ] || { echo "usage: bot-json.sh <slug>|--all [--refresh] | --mirror <slug>" >&2; exit 2; }
base="$(cd "$base" 2>/dev/null && pwd || echo "$base")"
origin="$(git remote get-url origin 2>/dev/null || true)"
WHICH="$which" BASE="$base" REFRESH="$refresh" OUT="$out" MIRROR="$mirror" ORIGIN="$origin" python3 - <<'PY'
import json, os, re, sys
E=os.environ; F="local/fleet.json"
if not os.path.exists(F): sys.exit("bot-json: no local/fleet.json")
fl=json.load(open(F)); bots=fl.get("bots",[])
if E["MIRROR"]:
    s=E["WHICH"]; bj=json.load(open(f"bots/{s}/bot.json")); n=0
    for b in bots:
        if b["slug"]==s:
            for k,v in (("name",bj["display_name"]),("role",bj["role"])):
                if b.get(k)!=v: b[k]=v; n+=1
    json.dump(fl,open(F,"w"),indent=2,ensure_ascii=False); open(F,"a").write("\n")
    print(f"bot-json: mirrored {s} into {F} ({n} change(s))"); sys.exit(0)
owner=(fl.get("owner_name") or "").strip()
if not owner: sys.exit("bot-json: set \"owner_name\" in local/fleet.json first")
def tz():
    if fl.get("timezone"): return fl["timezone"]
    if E.get("TZ"): return E["TZ"].lstrip(":")
    try: return open("/etc/timezone").read().strip() or "UTC"
    except Exception: return "UTC"
repo=fl.get("fleet_repo") or re.sub(r"//[^/@]*@","//",E.get("ORIGIN",""))
kit=open("fleet/VERSION").read().strip()
tmpl=open("templates/bot.json.tmpl").read()
sel=[b for b in bots if E["WHICH"]=="--all" or b["slug"]==E["WHICH"]]
if not sel: sys.exit(f"bot-json: no bot '{E['WHICH']}' in {F}")
for b in sel:
    s=b["slug"]; d=f"bots/{s}"; p=f"{d}/bot.json"
    if not os.path.isdir(d): print(f"bot-json: skip {s} (no {d}/)"); continue
    env={"WORKTREE":f"{E['BASE']}/{s}","OWNER_NAME":owner,"FLEET_REPO":repo,"KIT_VERSION":kit,"TIMEZONE":tz()}
    if os.path.exists(p) and E["OUT"]!="-":
        if not E["REFRESH"]: print(f"bot-json: keep {p} (exists)"); continue
        j=json.load(open(p)); new={**j, "kit_version":kit}
        if new!=j: json.dump(new,open(p,"w"),indent=2,ensure_ascii=False); open(p,"a").write("\n"); print(f"bot-json: refreshed {p}")
        continue
    title=""
    try: title=json.load(open(f"{d}/profile.json")).get("title","")
    except Exception: pass
    vals={**env,"DISPLAY_NAME":b["name"],"SLUG":s,"ROLE":b["role"],"TITLE":title,"AGENT_ID":b.get("id","")}
    txt=re.sub(r"\{\{(\w+)\}\}",lambda m: json.dumps(vals[m.group(1)],ensure_ascii=False)[1:-1] if m.group(1) in vals else m.group(0),tmpl)
    left=re.findall(r"\{\{[^}]*\}\}",txt)
    if left: sys.exit(f"bot-json: unfilled placeholders {sorted(set(left))}")
    json.loads(txt)
    if E["OUT"]=="-": sys.stdout.write(txt); continue
    open(p,"w").write(txt); print(f"bot-json: wrote {p}")
PY
