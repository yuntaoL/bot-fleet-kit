#!/usr/bin/env bash
# 0.1.1: ensure fleet.json has "owner" and "templateVersion" keys. Idempotent.
set -euo pipefail
[ -f fleet.json ] || exit 0
python3 - <<'PY'
import json; f=json.load(open('fleet.json')); f.setdefault('owner',''); f.setdefault('templateVersion','0.1.0')
json.dump(f,open('fleet.json','w'),indent=2,ensure_ascii=False); open('fleet.json','a').write('\n')
PY
