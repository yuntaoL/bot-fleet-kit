#!/usr/bin/env python3
"""OWNERS.json engine shared by check-boundary.sh and validate.sh.
usage: owners.py check   (reads `git diff --cached --name-status --no-renames` on stdin; env BOT_NAME, BOT_ROLE, BOT_RESTORE, BOT_FLEET_UPGRADE)
       owners.py audit   (every tracked file matches an owner; two owner classes fail, except MULTI_OWNER_OK)

Role and the pristine shared-skills stub are read from git (HEAD or the index), never the working tree.
A builder may change local/shared/SHARED-SKILLS.md and local/prompts/ only when HEAD:local/fleet.json
gives that slug role builder and a status other than retired or paused.
"""
import sys
sys.dont_write_bytecode = True
import json, os, re, subprocess
import schema_check
ROOT = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
OWN = json.load(open(os.path.join(ROOT, "fleet/OWNERS.json")))["rules"]
# First match wins at commit time. Audit still fails when one tracked path matches two owner
# classes, except these paths, where a narrower rule intentionally shadows a later broader one.
MULTI_OWNER_OK = {
    "local/shared/SHARED-SKILLS.md",  # builder, then local/**
}
def multi_ok(path):
    if path in MULTI_OWNER_OK:
        return True
    # Compiled prompts are builder-owned and also match the later local/** manager rule.
    return path.startswith("local/prompts/")
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
def git_bytes(spec):
    try: return subprocess.check_output(["git", "show", spec], cwd=ROOT, stderr=subprocess.DEVNULL)
    except subprocess.CalledProcessError: return None
def head_fleet():
    """HEAD:local/fleet.json. An unstaged or uncommitted edit does not count."""
    raw = git_bytes("HEAD:local/fleet.json")
    if raw is None: return None
    try: return json.loads(raw.decode())
    except Exception: return None
def fleet_record(slug):
    """Bot row from HEAD:local/fleet.json. An unstaged or uncommitted edit does not count."""
    if not slug: return None
    fl = head_fleet()
    if not fl: return None
    for b in fl.get("bots", []):
        if b.get("slug") == slug: return b
    return None
def board_cfg():
    """(path, coordinator slug) from HEAD fleet.json, or None when the feature is off.

    An invalid path is off. It does not widen writes.
    """
    fl = head_fleet()
    if not fl: return None
    board = fl.get("board")
    if not isinstance(board, dict): return None
    path, coord = board.get("path"), board.get("coordinator")
    if not isinstance(path, str) or not isinstance(coord, str): return None
    if not schema_check.valid_board_path(path): return None
    return path, coord
def index_mode(path):
    r = subprocess.run(["git", "ls-files", "--stage", "--", path], cwd=ROOT, capture_output=True, text=True)
    lines = [ln for ln in r.stdout.splitlines() if ln.strip()]
    if len(lines) != 1:
        return None
    return lines[0].split(" ", 1)[0]
def mode_problem(path, status, allowed=("100644",)):
    """Add and modify must be a regular file. A type change is refused.

    Bot paths allow 100644 and 100755. The board allows 100644 only.
    120000, 160000, and any other mode are refused.
    """
    if status not in ("A", "M", "T"):
        return None
    mode = index_mode(path)
    if status == "T" or mode not in allowed:
        kind = "type change; " if status == "T" else ""
        return "%sstaged mode %s is not a regular file (%s); symlink and gitlink are refused" % (
            kind, mode or "missing", " or ".join(allowed))
    return None
def retired_bot(rec):
    if not rec: return False
    return rec.get("role") == "retired" or rec.get("status") == "retired"
def board_write_allowed(me, role, path, status):
    """None when path is not the configured board. True or False when it is.

    File-level only. A bot may add or update only its own cards; the coordinator's
    scan audits that, because a commit cannot see which row is whose.
    The manager and the coordinator may create or delete the file. Any non-retired
    bot may update it.
    """
    cfg = board_cfg()
    if not cfg or cfg[0] != path: return None
    coord = cfg[1]
    rec = fleet_record(me) if me else None
    if role == "retired" or retired_bot(rec): return False
    manager = role == "manager"
    coord_ok = bool(me) and me == coord and rec is not None and not retired_bot(rec)
    if status in ("A", "D"): return manager or coord_ok
    if manager: return True
    return rec is not None and not retired_bot(rec)
def active_builder(slug):
    b = fleet_record(slug)
    if not b or b.get("role") != "builder": return False
    return (b.get("status") or "active") not in ("retired", "paused")
def pristine_shared_skills():
    """Staged local/shared/SHARED-SKILLS.md equals HEAD's template, not the working tree."""
    staged = git_bytes(":local/shared/SHARED-SKILLS.md")
    head = git_bytes("HEAD:templates/local/shared/SHARED-SKILLS.md")
    if staged is None or head is None: return False
    return staged == head
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
        if o == "builder":
            if active_builder(me): continue
            if role == "manager" and st == "A" and path == "local/shared/SHARED-SKILLS.md" and pristine_shared_skills(): continue
            bad.append((path, "builder-owned shared skills index (HEAD fleet.json: active builder, or upgrade.sh; the manager may only add the pristine template stub)"))
            continue
        # A bot's own tree is decided before the board, so a board path can never
        # make another bot's file writable.
        if path.startswith("bots/") or o == "self":
            parts = path.split("/")
            slug = parts[1] if len(parts) > 1 else ""
            allowed = False
            if slug == me and role != "retired": allowed = True
            elif st == "A" and (role in (rule.get("create") or [])) and (role != "builder" or restore): allowed = True
            if not allowed:
                bad.append((path, f"owned by bot '{slug}' (others may only create new files: {rule.get('create', [])})"))
                continue
            problem = mode_problem(path, st, ("100644", "100755"))
            if problem:
                bad.append((path, problem))
            continue
        board_ok = board_write_allowed(me, role, path, st)
        if board_ok is True:
            problem = mode_problem(path, st, ("100644",))
            if problem:
                bad.append((path, problem))
            continue
        if board_ok is False:
            bad.append((path, "shared task board (HEAD fleet.json board): the manager and the coordinator may create or delete it; any non-retired bot may update a regular file. A bot may add or update only its own cards; the coordinator's scan audits that"))
            continue
        if o == "manager":
            if role != "manager": bad.append((path, "manager-owned")); continue
    if bad:
        print(f"check-boundary: rejected for BOT_NAME={me or '?'} BOT_ROLE={role} (see fleet/OWNERS.json):", file=sys.stderr)
        for p, why in bad: print(f"  {p}: {why}", file=sys.stderr)
        sys.exit(1)
def audit():
    files = subprocess.check_output(["git", "ls-files"], text=True, cwd=ROOT).split("\n")
    err = 0
    for f in filter(None, files):
        hits = [r for x, r in RULES if x.match(f)]
        if not hits:
            err += 1; print(f"FAIL unowned path: {f}"); continue
        owners = sorted({r["owner"] for r in hits})
        if len(owners) > 1 and not multi_ok(f):
            err += 1; print(f"FAIL {f} matches several owner classes: {owners}")
    return err
def board_stage():
    """Print the board path when this bot may stage the worktree file. Exit 1 otherwise."""
    cfg = board_cfg()
    if not cfg: sys.exit(1)
    path = cfg[0]
    if os.path.islink(path) or not os.path.isfile(path): sys.exit(1)
    root = os.path.realpath(ROOT)
    real = os.path.realpath(path)
    try:
        if os.path.commonpath([root, real]) != root: sys.exit(1)
    except ValueError:
        sys.exit(1)
    me = os.environ.get("BOT_NAME") or gcfg("fleet.bot")
    role = os.environ.get("BOT_ROLE") or gcfg("fleet.role") or "worker"
    status = "M" if git_bytes("HEAD:" + path) is not None else "A"
    if board_write_allowed(me, role, path, status) is not True: sys.exit(1)
    print(path)
if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit("usage: owners.py check|audit|board-stage")
    if sys.argv[1] == "check": check()
    elif sys.argv[1] == "audit": sys.exit(1 if audit() else 0)
    elif sys.argv[1] == "board-stage": board_stage()
    else: sys.exit("usage: owners.py check|audit|board-stage")
