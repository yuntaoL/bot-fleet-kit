#!/usr/bin/env bash
# Usage: template/scripts/render-prompt.sh <slug> [--stdout] [--worktree-base DIR]
# Renders template/defaults/THIN-PROMPT.tmpl for one bot from manager/fleet.json (owner_name, bot name, role)
# into bots/<slug>/THIN-PROMPT.md (instance file). Fails if owner_name is empty or any {{...}} is left unfilled.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
slug="${1:?usage: render-prompt.sh <slug> [--stdout] [--worktree-base DIR]}"; shift
out="bots/$slug/THIN-PROMPT.md"; base="${BOT_FLEET_WORKTREES:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/../bot-fleet-worktrees}"
while [ $# -gt 0 ]; do case "$1" in --stdout) out=-;; --worktree-base) base="$2"; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac; shift; done
base="$(cd "$base" 2>/dev/null && pwd || echo "$base")"
SLUG="$slug" BASE="$base" OUT="$out" python3 - <<'PY'
import json, os, re, sys
slug, base, out = os.environ["SLUG"], os.environ["BASE"], os.environ["OUT"]
fl = json.load(open("manager/fleet.json"))
owner = (fl.get("owner_name") or "").strip()
if not owner: sys.exit("render-prompt: set \"owner_name\" in manager/fleet.json first (the owner's display name)")
bot = next((b for b in fl["bots"] if b["slug"] == slug), None)
if not bot: sys.exit(f"render-prompt: no bot '{slug}' in manager/fleet.json")
vals = {"BOT_NAME": bot["name"], "OWNER_NAME": owner, "SLUG": slug, "ROLE": bot["role"], "WORKTREE": f"{base}/{slug}"}
txt = open("template/defaults/THIN-PROMPT.tmpl").read()
txt = re.sub(r"\{\{(\w+)\}\}", lambda m: vals.get(m.group(1), m.group(0)), txt)
left = re.findall(r"\{\{[^}]*\}\}", txt)
if left: sys.exit(f"render-prompt: unfilled placeholders {sorted(set(left))}")
hdr = f"<!-- Rendered from template/defaults/THIN-PROMPT.tmpl by render-prompt.sh. Instance file: re-render instead of hand-editing the first block. -->\n"
if out == "-": sys.stdout.write(txt)
else:
    os.makedirs(os.path.dirname(out), exist_ok=True); open(out, "w").write(hdr + txt); print(f"render-prompt: wrote {out}")
PY
