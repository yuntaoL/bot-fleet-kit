#!/usr/bin/env bash
# 0.2.0: fleet.json schemaVersion 2 (role: manager|builder|worker|retired), role in each profile.json,
# fleet README/CHANGELOG, rules/local/. Idempotent.
set -euo pipefail
scripts/init-fleet-docs.sh
[ -f fleet.json ] || exit 0
python3 - <<'PY'
import json, os
f = json.load(open('fleet.json'))
for b in f.get('bots', []):
    r = b.get('role', 'worker')
    if b.get('status') == 'retired' or r == 'retired': r = 'retired'
    elif b.pop('manager', False) or r in ('primary', 'manager'): r = 'manager'
    elif r != 'builder': r = 'worker'
    b.pop('manager', None); b['role'] = r
    p = f"bots/{b['slug']}/profile.json"
    if os.path.exists(p):
        d = json.load(open(p)); d['role'] = r
        json.dump(d, open(p, 'w'), indent=2, ensure_ascii=False); open(p, 'a').write('\n')
f['schemaVersion'] = 2
json.dump(f, open('fleet.json', 'w'), indent=2, ensure_ascii=False); open('fleet.json', 'a').write('\n')
PY
