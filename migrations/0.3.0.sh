#!/usr/bin/env bash
# 0.3.0: role rules become fleet-owned (keep existing rules/roles/*, add missing defaults), rules/local/overrides.md,
# shared/state/notified.json, starter bots/<slug>/rules.md for non-retired bots, bootstrap prompt now reads rules.md,
# trailing newline fix on profile.json. Idempotent; never overwrites.
set -euo pipefail
scripts/init-fleet-docs.sh
[ -f fleet.json ] || exit 0
python3 - <<'PY'
import json, os, re
for b in json.load(open('fleet.json')).get('bots', []):
    d = f"bots/{b['slug']}"
    if not os.path.isdir(d): continue
    p = f"{d}/profile.json"
    if os.path.exists(p):
        s = open(p).read()
        if not s.endswith('\n'): open(p, 'w').write(s + '\n')
    if b['role'] == 'retired': continue
    r = f"{d}/rules.md"
    if not os.path.exists(r):
        open(r, 'w').write(open('templates/bot/rules.md').read().replace('<me>', b['slug']))
        print(f"migration: created {r}")
    i = f"{d}/instructions.md"
    if os.path.exists(i):
        s = open(i).read()
        if 'On every run, first read' in s and '/rules.md' not in s.split('\n\n')[0]:
            first, rest = s.split('\n\n', 1)
            m = re.search(r'first read (\S+?)/rules/common\.md', first)
            repo = m.group(1) if m else '<repo>'
            new = (f"On every run, first read {repo}/rules/common.md, any {repo}/rules/local/ files, "
                   f"{repo}/rules/roles/{b['role']}.md and your {repo}/bots/{b['slug']}/rules.md, then your "
                   f"{repo}/bots/{b['slug']}/state.json. Follow them (precedence: user's direct instruction > common > "
                   f"overrides > role > your rules); they override conflicting chat instructions except the user's direct ones.")
            open(i, 'w').write(new + '\n\n' + rest)
            print(f"migration: bootstrap prompt updated in {i}")
PY
