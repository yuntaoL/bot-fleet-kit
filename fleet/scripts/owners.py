#!/usr/bin/env python3
"""OWNERS.json engine shared by check-boundary.sh and validate.sh.
usage: owners.py check   (reads `git diff --cached --name-status --no-renames` on stdin; env BOT_NAME, BOT_ROLE, BOT_RESTORE, BOT_FLEET_UPGRADE)
       owners.py audit   (every tracked file has exactly one owner class)"""
import json, os, re, subprocess, sys
ROOT = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
OWN = json.load(open(os.path.join(ROOT, "fleet/OWNERS.json")))["rules"]
def rx(g):
    out = ""; i = 0
    while i < len(g):
        if g.startswith("**", i): out += ".*"; i += 2
        elif g[i] == "*": out += "[^/]*"; i += 1
        else: out += re.escape(g[i]); i += 1
    return re.compile("^" + out + "$")
RULES = [(rx(r["path"]), r) for r in OWN]
def owner(path):
    for r, rule in RULES:
        if r.match(path): return rule
    return None
def gcfg(k):
    try: return subprocess.check_output(["git", "config", "--get", k], text=True, cwd=ROOT).strip()
    except subprocess.CalledProcessError: return ""
def check():
    role = os.environ.get("BOT_ROLE") or gcfg("fleet.role") or "worker"
    me = os.environ.get("BOT_NAME") or gcfg("fleet.bot")
    upgrade = os.environ.get("BOT_FLEET_UPGRADE") == "1" and role == "manager"
    restore = os.environ.get("BOT_RESTORE") == "1" and role == "builder"
    bad = []
    for line in sys.stdin:
        if not line.strip(): continue
        st, path = line.split("\t", 1); path = path.strip(); st = st[0]
        if upgrade: continue
        rule = owner(path)
        if role == "retired": bad.append((path, "retired bots are read-only")); continue
        if rule is None: bad.append((path, "no owner in fleet/OWNERS.json")); continue
        o = rule["owner"]
        if o == "template": bad.append((path, "template-owned: changes only via scripts/upgrade.sh")); continue
        if o == "manager":
            if role != "manager": bad.append((path, "manager-owned")); continue
        elif o == "self":
            slug = path.split("/")[1]
            if slug == me and role != "retired": continue
            if st == "A" and (role in rule.get("create", [])) and (role != "builder" or restore): continue
            bad.append((path, f"owned by bot '{slug}' (others may only create new files: {rule.get('create', [])})"))
    if bad:
        print(f"check-boundary: rejected for BOT_NAME={me or '?'} BOT_ROLE={role} (see fleet/OWNERS.json):", file=sys.stderr)
        for p, why in bad: print(f"  {p}: {why}", file=sys.stderr)
        sys.exit(1)
def audit():
    files = subprocess.check_output(["git", "ls-files"], text=True, cwd=ROOT).split("\n")
    err = 0
    for f in filter(None, files):
        m = [r["owner"] for x, r in RULES if x.match(f)]
        if not m: err += 1; print(f"FAIL unowned path: {f}")
        elif len(set(m)) > 1: err += 1; print(f"FAIL {f} matches several owner classes: {sorted(set(m))}")
    return err
if __name__ == "__main__":
    if sys.argv[1] == "check": check()
    elif sys.argv[1] == "audit": sys.exit(1 if audit() else 0)
