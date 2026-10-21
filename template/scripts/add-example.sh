#!/usr/bin/env bash
# Usage: BOT_ROLE=manager template/scripts/add-example.sh <example> <slug> [name] [platform-id]
# Copies examples/<example> to bots/<slug>, fills <me>/<wt>/name/id, registers a worker in manager/fleet.json. Does not commit.
set -euo pipefail
ex="${1:?usage: add-example.sh <example> <slug> [name] [platform-id]}"; slug="${2:?slug required}"
cd "$(git rev-parse --show-toplevel)"
[[ "$slug" =~ ^[a-z0-9-]+$ ]] || { echo "bad slug: $slug" >&2; exit 1; }
[ -d "examples/$ex" ] || { echo "no such example: examples/$ex (have: $(ls examples | grep -v README | tr '\n' ' '))" >&2; exit 1; }
[ -e "bots/$slug" ] && { echo "bots/$slug already exists" >&2; exit 1; }
[ -f manager/fleet.json ] || { echo "manager/fleet.json missing; run template/scripts/init-fleet.sh" >&2; exit 1; }
wt="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"; wt="$(dirname "$wt")/bot-fleet-worktrees/$slug"
mkdir -p bots && cp -r "examples/$ex" "bots/$slug" && rm -f "bots/$slug/README.md"
SLUG="$slug" WT="$wt" NAME="${3:-}" ID="${4:-}" python3 - <<'PY'
import json, os, pathlib
s, wt, name, pid = os.environ["SLUG"], os.environ["WT"], os.environ["NAME"], os.environ["ID"]
d = pathlib.Path("bots") / s
for f in d.rglob("*"):
    if f.is_file() and f.suffix in (".md", ".json"):
        t = f.read_text().replace("<wt>", wt).replace("<me>", s).replace("<role>", "worker")
        if pid: t = t.replace("<platform-id>", pid)
        f.write_text(t)
p = d / "profile.json"; pr = json.loads(p.read_text())
if name: pr["name"] = name
p.write_text(json.dumps(pr, indent=2, ensure_ascii=False) + "\n")
fp = pathlib.Path("manager/fleet.json"); fl = json.loads(fp.read_text())
if any(b["slug"] == s for b in fl["bots"]): print(f"fleet.json already has {s}; left as is")
else:
    fl["bots"].append({"slug": s, "name": pr["name"], "id": pid or pr["id"], "role": "worker", "status": "active", "summary": pr["description"][:200]})
    fp.write_text(json.dumps(fl, indent=2, ensure_ascii=False) + "\n")
PY
echo "added bots/$slug from examples/$ex. Remaining placeholders:"; grep -rhoE '<[a-z][a-z0-9+-]*>' "bots/$slug" | sort -u | tr '\n' ' '; echo
echo "Next: fill them, template/scripts/validate.sh, commit as manager (template/scripts/sync.sh), template/scripts/worktree.sh $slug"
