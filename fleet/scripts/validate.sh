#!/usr/bin/env bash
# Schema + ownership checks. Needs python3 + jsonschema.
# Usage: fleet/scripts/validate.sh [--pre-fleet]
#   --pre-fleet  bootstrap phase 1 (0.8.0+): structure + worktree identity; needs one manager and a builder listed (any status);
#                skips the ACTIVE-role invariants. Default mode WARNS (0.8.0) when there is no active manager/builder;
#                BOT_FLEET_STRICT_ROLES=1 makes those (and 0.9.0 role drift) failures (planned default in a later release).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
MODE=fleet; [ "${1:-}" = "--pre-fleet" ] && MODE=pre-fleet
err=0
python3 fleet/scripts/owners.py audit || err=1
# 0.10.2: shared rules/roles carry no {{...}} fill-ins (only templates/ does)
! grep -rlnE '[{]{2}[A-Z_]+[}]{2}' fleet/rules fleet/roles 2>/dev/null | sed 's/^/FAIL fill-in placeholder in shared file: /' | grep . || err=1
# 0.10.2: private routine steps never tracked
! git ls-files | grep -E '(^|/)private-[^/]*\.steps\.md$' | sed 's/^/FAIL tracked private steps file: /' | grep . || err=1
python3 - <<'PY' || err=1
import json, glob, os, re, sys
try: import jsonschema
except ImportError: sys.exit("validate: pip install jsonschema")
S = {n: json.load(open(f"fleet/schema/{n}.schema.json")) for n in ["fleet","profile","state","routine","owners","bot"]}
err = 0
def chk(path, s):
    global err
    try: jsonschema.validate(json.load(open(path)), S[s])
    except Exception as e: err += 1; print(f"FAIL {path}: {str(e).splitlines()[0]}")
chk("fleet/OWNERS.json","owners")
D="templates"
chk(f"{D}/bot/profile.json","profile"); chk(f"{D}/bot/state.json","state")
for r in glob.glob(f"{D}/bot/routines/*.json"): chk(r,"routine")
F0="local/fleet.json"
for e in ([] if os.path.exists(F0) else glob.glob("examples/*/")):  # examples validated only in the template repo
    chk(f"{e}profile.json","profile"); chk(f"{e}state.json","state")
    for r in glob.glob(f"{e}routines/*.json"): chk(r,"routine")
for r in ["fleet/rules/common.md","fleet/rules/README.md","fleet/rules/startup.md","fleet/rules/routines.md","templates/THIN-PROMPT.tmpl","templates/ROUTINE-PROMPT.tmpl","templates/bot.json.tmpl"]+[f"fleet/roles/{x}.md" for x in ["manager","builder","worker","retired"]]:
    if not os.path.exists(r): err+=1; print(f"FAIL missing {r}")
F="local/fleet.json"
if os.path.exists(F):
    chk(F,"fleet"); fl=json.load(open(F))
    for x in ["manager","builder","worker","retired"]:
        pass  # 0.10.0: roles are read from fleet/roles/ (checked above)
    if fl.get("bots") and [b["role"] for b in fl["bots"]].count("manager")!=1: err+=1; print("FAIL fleet.json needs exactly one manager")
    ov="local/overrides.md"
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
        # 0.10.5: bots/<slug>/bot.json exists, matches its schema and its own slug
        bjp=f"{d}/bot.json"
        if not os.path.exists(bjp): err+=1; print(f"FAIL missing {bjp} (fleet/scripts/bot-json.sh {b['slug']})")
        else:
            chk(bjp,"bot")
            try: bj=json.load(open(bjp))
            except Exception: bj={}
            if bj.get("slug") not in (None,b["slug"]): err+=1; print(f"FAIL {bjp}: slug '{bj.get('slug')}' != folder '{b['slug']}'")
sys.exit(1 if err else 0)
PY
# 0.7.0 knowledge-layout checks: WARN only, never fail
python3 - <<'PY' || true
import glob, os, re
w=0
for idx in ["local/shared/INDEX.md","local/registry/INDEX.md"]+glob.glob("bots/*/kb/INDEX.md")+glob.glob("bots/*/skills/INDEX.md"):
    if not os.path.exists(idx): continue
    base=os.path.dirname(idx)
    for m in re.finditer(r"(?m)^\|\s*`?([A-Za-z0-9_./-]+\.(?:md|json|sh))`?\s*\|", open(idx).read()):
        p=m.group(1)
        if not (os.path.exists(os.path.join(base,p)) or os.path.exists(p)): w+=1; print(f"WARN {idx}: row points to missing {p}")
for f in glob.glob("bots/*/kb/**/*.md", recursive=True):
    if not open(f).read(4).startswith("---"): w+=1; print(f"WARN {f}: no front matter")
if w: print(f"validate: {w} layout warning(s) (not failures)")
PY
# 0.8.0 bootstrap checks: required roles, worktree identity, rendered prompts
MODE="$MODE" python3 - <<'PY' || err=1
import json, os, re, subprocess, sys
mode=os.environ["MODE"]; strict=os.environ.get("BOT_FLEET_STRICT_ROLES")=="1"; F="local/fleet.json"; e=0; w=0
if not os.path.exists(F): sys.exit(0)
fl=json.load(open(F)); bots=fl.get("bots",[])
def fail(m):
    global e; e+=1; print("FAIL "+m)
def warn(m):
    global w; w+=1; print("WARN "+m)
for b in bots:
    p=f"bots/{b['slug']}/THIN-PROMPT.md"
    if os.path.exists(p) and re.search(r"\{\{[^}]*\}\}", open(p).read()): fail(f"{p}: unfilled {{...}} placeholder (re-run render-prompt.sh)")
slugs=[b["slug"] for b in bots]
if len(slugs)!=len(set(slugs)): fail("fleet.json: duplicate slugs")
common=subprocess.run(["git","rev-parse","--path-format=absolute","--git-common-dir"],capture_output=True,text=True).stdout.strip()
base=os.environ.get("BOT_FLEET_WORKTREES") or os.path.join(os.path.dirname(os.path.dirname(common)),"bot-fleet-worktrees")
for b in bots:
    if b["role"]=="retired": continue
    wt=os.path.join(base,b["slug"])
    if os.path.exists(os.path.join(wt,".git")):
        got=subprocess.run(["git","-C",wt,"config","--get","fleet.bot"],capture_output=True,text=True).stdout.strip()
        if got!=b["slug"]: (fail if mode=="pre-fleet" else warn)(f"worktree {wt}: fleet.bot='{got}', expected '{b['slug']}'")
    elif mode=="pre-fleet": fail(f"missing worktree {wt} (run fleet/scripts/worktree.sh {b['slug']})")
# 0.9.1: every worktree dir must match its fleet.bot (a mismatch used to be skipped silently)
wl=subprocess.run(["git","worktree","list","--porcelain"],capture_output=True,text=True).stdout
known={b["slug"] for b in bots}
for blk in wl.strip().split("\n\n"):
    ln=dict(l.split(" ",1) for l in blk.splitlines() if " " in l)
    wt=ln.get("worktree","")
    if os.path.dirname(os.path.abspath(wt))!=os.path.abspath(base): continue
    got=subprocess.run(["git","-C",wt,"config","--get","fleet.bot"],capture_output=True,text=True).stdout.strip()
    d=os.path.basename(wt); br=ln.get("branch","").replace("refs/heads/","")
    if got and got!=d: (fail if mode=="pre-fleet" else warn)(f"worktree dir {wt} != fleet.bot '{got}' (rename: rename-bot skill)")
    if got and br and br!=f"wt/{got}": warn(f"worktree {wt}: branch '{br}', expected 'wt/{got}'")
    if got and got not in known: warn(f"worktree {wt}: fleet.bot '{got}' not in fleet.json")
if mode=="pre-fleet":
    roles=[b["role"] for b in bots]
    if roles.count("manager")!=1: fail("pre-fleet: fleet.json needs exactly one manager")
    if roles.count("builder")<1: fail("pre-fleet: fleet.json needs at least one builder")
else:
    act=[b for b in bots if b.get("status")=="active"]
    if bots:
        rep=fail if strict else warn
        if [b["role"] for b in act].count("manager")!=1: rep("required roles: need exactly one ACTIVE manager")
        if [b["role"] for b in act].count("builder")<1: rep("required roles: need at least one ACTIVE builder (bot creation and restores)")
    pend=[b["slug"] for b in bots if b.get("status") in ("pre-fleet","converting")]
    if pend: warn(f"bootstrap in progress for {pend}; phase-1 checks: validate.sh --pre-fleet")
# 0.9.2 thin routines: stepsFile exists; rendered routine prompts have no {{...}}
import glob as _g
for b in bots:
    for f in _g.glob(f"bots/{b['slug']}/routines/*.json"):
        try: r=json.load(open(f))
        except Exception: continue
        sf=r.get("stepsFile")
        if not sf: continue
        pre=f"bots/{b['slug']}/routines/"
        if not sf.startswith(pre): warn(f"{f}: stepsFile '{sf}' is not repo-relative (expected {pre}<name>.steps.md)")
        if r.get("private") is True:
            # 0.10.3: private steps are git-ignored and live only in their own bot's worktree
            if not re.fullmatch(r"(bots/[^/]+/routines/)?private-[^/]+\.steps\.md", sf): fail(f"{f}: private routine stepsFile '{sf}' must be routines/private-*.steps.md")
        elif not os.path.exists(sf): fail(f"{f}: stepsFile '{sf}' not found")
    for p in _g.glob(f"bots/{b['slug']}/routines/*.prompt.md"):
        if re.search(r"\{\{[^}]*\}\}", open(p).read()): fail(f"{p}: unfilled {{...}} placeholder (re-run render-routine-prompt.sh)")
# 0.10.0 layout: role files are read from fleet/roles/ (no per-instance copies); compat links for old paths
for x in ["manager","builder","worker","retired"]:
    if os.path.exists(f"local/roles/{x}.md") and open(f"local/roles/{x}.md").read()==open(f"fleet/roles/{x}.md").read():
        warn(f"local/roles/{x}.md is a copy of fleet/roles/{x}.md; local/roles/ holds additions only")
if os.path.isdir("manager") or os.path.isdir("template"):
    r=subprocess.run(["bash","fleet/scripts/compat.sh","check"],capture_output=True,text=True)
    for l in r.stdout.splitlines():
        if l.startswith("WARN "): warn(l[5:])
        elif l.startswith("FAIL "): fail(l[5:])
if w: print(f"validate: {w} bootstrap warning(s) (not failures)")
sys.exit(1 if e else 0)
PY
# 0.10.5 bot.json is the single copy of identity: WARN on hard-coded copies and registry drift (never fails)
python3 - <<'PY2' || true
import json, glob, os, re
F="local/fleet.json"; w=0
if os.path.exists(F):
    fl=json.load(open(F)); reg={b["slug"]:b for b in fl.get("bots",[])}
    ids=[]
    for p in sorted(glob.glob("bots/*/bot.json")):
        try: bj=json.load(open(p))
        except Exception: continue
        s=bj.get("slug",""); ids.append(bj)
        b=reg.get(s)
        if b and b.get("name")!=bj.get("display_name"): w+=1; print(f"WARN {p}: display_name '{bj.get('display_name')}' != local/fleet.json name '{b.get('name')}' (manager: bot-json.sh --mirror {s})")
        if b and b.get("role")!=bj.get("role"): w+=1; print(f"WARN {p}: role '{bj.get('role')}' != local/fleet.json role '{b.get('role')}' (fleet.json is authoritative for role)")
    files=glob.glob("templates/*.tmpl")+glob.glob("bots/*/THIN-PROMPT.md")+glob.glob("bots/*/routines/*.json")+glob.glob("bots/*/routines/*.prompt.md")+glob.glob("bots/*/rules.md")+glob.glob("local/rules/*.md")+glob.glob("fleet/rules/*.md")
    for bj in ids:
        name=bj.get("display_name",""); role=bj.get("role",""); s=bj.get("slug","")
        rx_role=re.compile(r"(?i)(your role is|role:?)\s*`?"+re.escape(role)+r"\b") if role else None
        for f in files:
            try: t=open(f).read()
            except Exception: continue
            if len(name)>=3 and name in t: w+=1; print(f"WARN {f}: hard-codes display name '{name}' (from bots/{s}/bot.json); reference bot.json instead")
            if rx_role and f.startswith(("templates/",f"bots/{s}/THIN-PROMPT",f"bots/{s}/routines/")) and rx_role.search(t): w+=1; print(f"WARN {f}: hard-codes role '{role}' (from bots/{s}/bot.json); reference bot.json instead")
if w: print(f"validate: {w} bot.json warning(s) (not failures)")
PY2
# 0.10.5 .bot pointer (warn only): each bot worktree's untracked .bot names bots/<slug>/bot.json and agrees with
# that bot.json, the worktree's fleet.bot config and the rendered prompt's worktree path
python3 - <<'PY3' || true
import json, os, re, subprocess
def g(*a, cwd=None):
    r=subprocess.run(["git",*a],cwd=cwd,capture_output=True,text=True); return r.stdout.strip() if r.returncode==0 else ""
w=0
def warn(m):
    global w; w+=1; print(f"WARN {m}")
if g("ls-files","--",".bot"): warn(".bot is tracked; it must stay untracked (git rm --cached .bot)")
for wt in [l[9:] for l in g("worktree","list","--porcelain").splitlines() if l.startswith("worktree ")]:
    cfg=g("config","--worktree","--get","fleet.bot",cwd=wt); bp=os.path.join(wt,".bot")
    if not os.path.exists(bp):
        if cfg: warn(f"{wt}: no .bot (fleet/scripts/bot-pointer.sh {cfg} {wt}, or worktree.sh {cfg})")
        continue
    line=open(bp).read().strip(); m=re.fullmatch(r"bots/([a-z0-9-]+)/bot\.json",line)
    if not m: warn(f"{bp}: '{line}' is not bots/<slug>/bot.json"); continue
    s=m.group(1); bj=os.path.join(wt,line)
    if not os.path.exists(bj): warn(f"{bp}: points to missing {line}"); continue
    try: j=json.load(open(bj))
    except Exception: warn(f"{bp}: {line} is not valid JSON"); continue
    if j.get("slug")!=s: warn(f"{bp}: names '{s}' but {line} has slug '{j.get('slug')}'")
    if cfg and cfg!=s: warn(f"{bp}: names '{s}' but this worktree's fleet.bot is '{cfg}'")
    if j.get("worktree") and os.path.realpath(j["worktree"])!=os.path.realpath(wt): warn(f"{bp}: {line} worktree '{j['worktree']}' != this worktree '{wt}'")
    tp=os.path.join(wt,f"bots/{s}/THIN-PROMPT.md")
    if os.path.exists(tp):
        pm=re.search(r"Your worktree is (\S+?)\.(\s|$)",open(tp).read())
        if pm and os.path.realpath(pm.group(1))!=os.path.realpath(wt): warn(f"{bp}: rendered prompt bots/{s}/THIN-PROMPT.md names worktree '{pm.group(1)}', not '{wt}' (re-render, or fix .bot)")
if w: print(f"validate: {w} .bot warning(s) (not failures)")
PY3
# 0.10.5 journal gaps (warn only): activity today with no journal line after it
bash fleet/scripts/check-journal.sh 2>/dev/null | grep "^WARN" || true
[ $err = 0 ] && echo "validate: OK ($MODE)" || { echo "validate: FAILED"; exit 1; }
