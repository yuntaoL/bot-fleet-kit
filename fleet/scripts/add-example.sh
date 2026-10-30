#!/usr/bin/env bash
# Usage: BOT_ROLE=manager fleet/scripts/add-example.sh <example> <slug> [name] [platform-id]
# Fetches examples/<example> from the PUBLIC template at tag v$EXAMPLE_VERSION (default: fleet/VERSION) into a temp dir,
# copies it to bots/<slug>, fills <me>/<wt>/<role>/name/id, registers a worker in local/fleet.json. Does not commit.
# Source repo: $TEMPLATE_URL, else the 'upstream' remote, else the public bot-fleet-template.
set -euo pipefail
ex="${1:?usage: add-example.sh <example> <slug> [name] [platform-id]}"; slug="${2:?slug required}"
cd "$(git rev-parse --show-toplevel)"
[[ "$slug" =~ ^[a-z0-9-]+$ ]] || { echo "bad slug: $slug" >&2; exit 1; }
[ -e "bots/$slug" ] && { echo "bots/$slug already exists" >&2; exit 1; }
[ -f local/fleet.json ] || { echo "local/fleet.json missing; run fleet/scripts/init-fleet.sh" >&2; exit 1; }
url="${TEMPLATE_URL:-$(git remote get-url upstream 2>/dev/null || echo https://github.com/yuntaoL/bot-fleet-template.git)}"
ver="${EXAMPLE_VERSION:-$(cat fleet/VERSION)}"; ver="${ver#v}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --branch "v$ver" "$url" "$tmp/t" 2>/dev/null || { echo "cannot fetch tag v$ver from $url (examples need template >= 0.5.0; set EXAMPLE_VERSION)" >&2; exit 1; }
src="$tmp/t/examples/$ex"
[ -d "$src" ] || { echo "no example '$ex' in $url v$ver (have: $(ls "$tmp/t/examples" 2>/dev/null | grep -v README | tr '\n' ' '))" >&2; exit 1; }
wt="$(dirname "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")")/bot-fleet-worktrees/$slug"
mkdir -p bots && cp -r "$src" "bots/$slug" && rm -f "bots/$slug/README.md"
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
fp = pathlib.Path("local/fleet.json"); fl = json.loads(fp.read_text())
if any(b["slug"] == s for b in fl["bots"]): print(f"fleet.json already has {s}; left as is")
else:
    fl["bots"].append({"slug": s, "name": pr["name"], "id": pid or pr["id"], "role": "worker", "status": "active", "summary": pr["description"][:200]})
    fp.write_text(json.dumps(fl, indent=2, ensure_ascii=False) + "\n")
PY
echo "added bots/$slug from $url v$ver examples/$ex. Remaining placeholders:"; grep -rhoE '<[a-z][a-z0-9+-]*>' "bots/$slug" | sort -u | tr '\n' ' '; echo
echo "Next: fill them, fleet/scripts/validate.sh, commit as manager (fleet/scripts/sync.sh), fleet/scripts/worktree.sh $slug"
