#!/usr/bin/env bash
# 0.4.0: folder-owned layout. Moves fleet files into manager/, drops profile.json "role" (fleet.json is authoritative),
# rewrites bootstrap prompts and old repo paths in bot files to the bot's own worktree. Idempotent.
set -euo pipefail
mv_(){ [ -e "$1" ] || return 0; [ -e "$2" ] && { echo "keep existing $2 (left $1)"; return 0; }; mkdir -p "$(dirname "$2")"; git mv -k "$1" "$2" 2>/dev/null || mv "$1" "$2"; echo "moved $1 -> $2"; }
for f in rules/roles/*.md; do [ -e "$f" ] && mv_ "$f" "manager/roles/$(basename "$f")"; done
mv_ rules/local/overrides.md manager/overrides.md
for f in rules/local/*.md; do [ -e "$f" ] || continue; [ "$(basename "$f")" = README.md ] && { git rm -qf "$f" 2>/dev/null || rm -f "$f"; continue; }; mv_ "$f" "manager/local/$(basename "$f")"; done
for g in rules/local/.gitkeep bots/.gitkeep; do git rm -qf "$g" 2>/dev/null || rm -f "$g"; done
if [ -d shared ]; then (cd shared && find . -type f) | while read -r f; do mv_ "shared/${f#./}" "manager/shared/${f#./}"; done; fi
mv_ fleet.json manager/fleet.json
mv_ CHANGELOG.md manager/CHANGELOG.md
rmdir -p rules/local rules/roles shared/state shared/skills shared 2>/dev/null || true
[ -f manager/fleet.json ] || exit 0
python3 - <<'PY'
import json, os, re, glob
fleet = json.load(open('manager/fleet.json'))
repo = os.path.abspath('.')
for b in fleet['bots']:
    s, role = b['slug'], b['role']; d = f"bots/{s}"
    if not os.path.isdir(d): continue
    p = f"{d}/profile.json"
    if os.path.exists(p):
        j = json.load(open(p))
        if 'role' in j:
            j.pop('role'); json.dump(j, open(p, 'w'), indent=2, ensure_ascii=False); open(p, 'a').write('\n')
    # old prompt's repo path (falls back to this clone)
    i = f"{d}/instructions.md"; old = repo
    if os.path.exists(i):
        m = re.search(r'first read (\S+?)/(?:template/)?rules/common\.md', open(i).read(), re.I)
        if m: old = m.group(1)
    wt = os.path.join(os.path.dirname(old.rstrip('/')) if 'bot-fleet-worktrees' not in old else os.path.dirname(os.path.dirname(old)), 'bot-fleet-worktrees', s)
    if role == 'retired':
        if os.path.exists(i):
            t = open(i).read(); parts = t.split('\n\n', 1)
            if parts[0].startswith('On every run') and len(parts) > 1: open(i, 'w').write(parts[1]); print(f"retired: removed bootstrap prompt from {i}")
        continue
    prompt = (f"On every run, work only in your own worktree {wt} (create it with template/scripts/worktree.sh {s} if missing). "
              f"First read {wt}/template/rules/common.md, {wt}/manager/overrides.md, any {wt}/manager/local/ files, "
              f"{wt}/manager/roles/{role}.md and your {wt}/bots/{s}/rules.md, then your {wt}/bots/{s}/state.json. "
              f"Follow them (precedence: user's direct instruction > common > overrides > role > your rules); they override conflicting chat instructions except the user's direct ones. "
              f"Save changes with template/scripts/sync.sh \"<message>\" from your worktree.")
    if os.path.exists(i):
        t = open(i).read()
        parts = t.split('\n\n', 1)
        if parts[0].startswith('On every run'):
            t = prompt + ('\n\n' + parts[1] if len(parts) > 1 else '\n')
        elif 'work only in your own worktree' not in t:
            t = prompt + '\n\n' + t
        open(i, 'w').write(t)
    # rewrite old absolute paths in this bot's other text files (routine prompts etc.)
    reps = [(f"{old}/rules/common.md", f"{wt}/template/rules/common.md"), (f"{old}/rules/local/", f"{wt}/manager/local/"),
            (f"{old}/rules/roles/", f"{wt}/manager/roles/"), (f"{old}/shared/", f"{wt}/manager/shared/"),
            (f"{old}/fleet.json", f"{wt}/manager/fleet.json"), (f"{old}/bots/", f"{wt}/bots/"),
            (f"{old}/scripts/", f"{wt}/template/scripts/")]
    for f in glob.glob(f"{d}/**/*", recursive=True):
        if f == i or not os.path.isfile(f) or not f.endswith(('.md', '.json')): continue
        t = open(f).read(); n = t
        for a, c in reps: n = n.replace(a, c)
        if n != t: open(f, 'w').write(n); print(f"paths updated: {f}")
PY
