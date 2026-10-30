#!/usr/bin/env bash
# Usage: fleet/scripts/check-journal.sh [YYYY-MM-DD=today] [--strict]
# 0.10.5 journal-gap check. Read-only. For each active bot, finds its last activity on the day and its last
# journal line that day, and prints "WARN <slug>: ..." when activity is newer than the journal (or there is no journal).
# Activity = (a) the newest commit that day made by the bot itself (sync.sh subject "<slug>: ...") that does not touch
# its journal for the day (edits by other bots, e.g. a manager rename, are not the bot's activity), and (b) if BOT_FLEET_TRANSCRIPTS
# is set, the newest mtime that day of any file under $BOT_FLEET_TRANSCRIPTS/<slug>/ (platform transcripts, if exported).
# Journal time = the latest "- HH:MM" line in bots/<slug>/journal/<day>.md, or the last commit touching it, whichever is later.
# Exit 0 always (warnings only), unless --strict and there are gaps (exit 1). Used by validate.sh and audit.sh.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
DAY="$(date +%F)"; STRICT=0
for a in "$@"; do case "$a" in --strict) STRICT=1;; ????-??-??) DAY="$a";; *) echo "usage: $0 [YYYY-MM-DD] [--strict]" >&2; exit 2;; esac; done
DAY="$DAY" STRICT="$STRICT" python3 - <<'PY'
import json, os, re, glob, subprocess, sys, datetime as dt
day=os.environ["DAY"]; strict=os.environ["STRICT"]=="1"; F="local/fleet.json"
if not os.path.exists(F): print("check-journal: no local/fleet.json; skipped"); sys.exit(0)
D=dt.date.fromisoformat(day); start=dt.datetime.combine(D,dt.time()).astimezone(); end=start+dt.timedelta(days=1)
def own(slug, j):
    out=subprocess.run(["git","log","--format=@%ct %s","--name-only",f"--since=@{int(start.timestamp())}",f"--until=@{int(end.timestamp())}"],capture_output=True,text=True).stdout
    act=jt=None
    for blk in out.split("\n@")[0:]:
        blk=blk.lstrip("@").strip()
        if not blk: continue
        lines=blk.split("\n"); t,_,subj=lines[0].partition(" "); t=int(t); files=[x for x in lines[1:] if x]
        if j in files: jt=max(jt or 0,t)
        elif subj.startswith(f"{slug}: "): act=max(act or 0,t)
    return act, jt
def fmt(t): return dt.datetime.fromtimestamp(t).strftime("%H:%M") if t else "none"
gaps=0
for b in json.load(open(F)).get("bots",[]):
    if b.get("role")=="retired" or b.get("status") not in (None,"active"): continue
    s=b["slug"]; d=f"bots/{s}"; j=f"{d}/journal/{day}.md"
    act,jt=own(s,j); src="git"
    tr=os.environ.get("BOT_FLEET_TRANSCRIPTS")
    if tr and os.path.isdir(os.path.join(tr,s)):
        for f in glob.glob(os.path.join(tr,s,"**","*"),recursive=True):
            m=os.path.getmtime(f)
            if os.path.isfile(f) and start.timestamp()<=m<end.timestamp() and (act is None or m>act): act=int(m); src="transcript"
    if act is None: continue
    if os.path.exists(j):
        hh=[l[2:7] for l in open(j,errors="ignore") if re.match(r"- \d\d:\d\d",l)]
        if hh:
            h,m=map(int,max(hh).split(":")); lt=int(dt.datetime.combine(D,dt.time(h,m)).astimezone().timestamp())+59
            jt=max(jt or 0, lt)
    # a minute of slack: a journal line written in the same sync as the work counts
    if jt is None or act>jt+60:
        gaps+=1; print(f"WARN {s}: activity at {fmt(act)} ({src}) but last journal line {fmt(jt)} on {day} (per-turn journal rule, startup.md step 5)")
print(f"check-journal: {gaps} gap(s) on {day}" if gaps else f"check-journal: OK ({day})")
sys.exit(1 if strict and gaps else 0)
PY
