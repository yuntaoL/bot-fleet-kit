#!/usr/bin/env bash
# Usage: fleet/scripts/audit.sh [max-age-days=7]   Mechanical part of docs/AUDIT.md. Read-only; prints a report.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
AGE="${1:-7}"
echo "# Fleet audit $(date '+%Y-%m-%d %H:%M %Z')"
echo; echo "## validate"; fleet/scripts/validate.sh 2>&1 | tail -20
echo; echo "## display names (rename drift; read-only)"; fleet/scripts/check-names.sh 2>&1 | tail -20
echo; echo "## journal gaps (per-turn rule; today and yesterday)"; fleet/scripts/check-journal.sh; fleet/scripts/check-journal.sh "$(date -d yesterday +%F 2>/dev/null || date -v-1d +%F)"
echo; echo "## routine prompts (thin-routine drift; read-only)"; fleet/scripts/check-routines.sh 2>&1 | tail -30
AGE="$AGE" python3 - <<'PY'
import json, os, re, glob, subprocess, datetime as dt
age=int(os.environ["AGE"]); now=dt.datetime.now(dt.timezone.utc); out=[]
def gitage(path):
    t=subprocess.run(["git","log","-1","--format=%ct","--",path],capture_output=True,text=True).stdout.strip()
    return (now-dt.datetime.fromtimestamp(int(t),dt.timezone.utc)).days if t else None
fl=json.load(open("local/fleet.json")) if os.path.exists("local/fleet.json") else {"bots":[]}
print("\n## freshness (days since last commit / state.updatedAt)")
for b in fl["bots"]:
    if b.get("role")=="retired" or b.get("status")=="retired": continue
    d=f"bots/{b['slug']}"; s=f"{d}/state.json"; sa="-"
    if os.path.exists(s):
        try:
            u=json.load(open(s)).get("updatedAt","")
            sa=(now-dt.datetime.fromisoformat(u.replace("Z","+00:00"))).days
        except Exception: sa="?"
    fa=gitage(d); ra=gitage(f"{d}/routines"); n=len(glob.glob(f"{d}/routines/*.json"))
    flag=" <- stale" if any(isinstance(x,int) and x>age for x in (fa,sa)) else ""
    print(f"- {b['slug']}: folder {fa}d, routines {ra}d ({n} files), state {sa}d{flag}")
print("\n## sensitive-pattern grep (tracked files; review each hit)")
PAT={"private key":r"-----BEGIN [A-Z ]*PRIVATE KEY","aws key":r"AKIA[0-9A-Z]{16}","github token":r"gh[pousr]_[A-Za-z0-9]{30,}",
"api key":r"\b(sk|xox[bap])-[A-Za-z0-9-]{16,}","password assignment":r"(?i)\b(password|passwd|pwd|api[_-]?key|secret)\s*[:=]\s*\S{6,}",
"card-like number":r"\b(?:\d[ -]?){13,16}\b","ssn-like":r"\b\d{3}-\d{2}-\d{4}\b","email address":r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}"}
files=[f for f in subprocess.run(["git","ls-files"],capture_output=True,text=True).stdout.split("\n") if f and not f.startswith(("fleet/",".github/"))]
hits=0
for f in files:
    try: lines=open(f,errors="ignore").read().split("\n")
    except Exception: continue
    for i,l in enumerate(lines,1):
        for k,p in PAT.items():
            if re.search(p,l): hits+=1; print(f"- {f}:{i} [{k}] {l.strip()[:100]}")
if not hits: print("- none")
print("\n## rules that may enumerate instead of stating a principle (heuristic)")
cand=glob.glob("local/rules/*.md")+glob.glob("fleet/roles/*.md")+glob.glob("local/overrides.md")+glob.glob("bots/*/rules.md")
trig=re.compile(r"(?i)\b(never|no|don't|do not|not|without)\b")
soft=re.compile(r"(?i)(e\.g\.|such as|and similar|use judgment|for example)")
std=re.compile(r"(?i)may add or tighten, never loosen")
def items(seg):  # list items after a negation: comma- or slash-separated (a, b, c / a/b/c)
    seg=re.split(r"[.;:(]",seg,maxsplit=1)[0]
    parts=[x for x in re.split(r",|(?<=\w)/(?=\w)",seg) if x.strip()]
    return len(parts)
h=0
for f in sorted(cand):
    for i,l in enumerate(open(f).read().split("\n"),1):
        if std.search(l) or soft.search(l) or "http" in l: continue
        segs=[l[m.end():] for m in trig.finditer(l)]
        if any(items(s)>=3 for s in segs): h+=1; print(f"- {f}:{i} {l.strip()[:110]}")
if not h: print("- none")
print("\nManual items (docs/AUDIT.md): contradictions/looser layers, open items, live vs. backed-up routines, scope, lessons to promote.")
PY
