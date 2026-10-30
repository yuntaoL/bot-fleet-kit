#!/usr/bin/env bash
# Usage: fleet/scripts/render-routine-prompt.sh <slug> [<routine>|--all] [--stdout] [--worktree-base DIR]
# Renders templates/ROUTINE-PROMPT.tmpl (0.9.2+; 0.9.4+ a minimal prompt that defers to fleet/rules/routines.md) for one routine (default --all: every bots/<slug>/routines/*.json)
# into bots/<slug>/routines/<routine>.prompt.md (instance file; paste it as the live routine prompt).
# 0.10.5+: values come from bots/<slug>/bot.json (bot-json.sh); the prompt keeps only the worktree path and routine name; the bot finds its slug via <worktree>/.bot.
# Fails if bot.json is missing, the routine file is missing, or any {{...}} is left unfilled.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
slug="${1:?usage: render-routine-prompt.sh <slug> [<routine>|--all] [--stdout]}"; shift
which=--all; [ $# -gt 0 ] && [ "${1#--}" = "$1" ] && { which="$1"; shift; }
out=file; base="${BOT_FLEET_WORKTREES:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/../bot-fleet-worktrees}"
while [ $# -gt 0 ]; do case "$1" in --stdout) out=-;; --all) which=--all;; --worktree-base) base="$2"; shift;; *) echo "unknown arg $1" >&2; exit 2;; esac; shift; done
base="$(cd "$base" 2>/dev/null && pwd || echo "$base")"
SLUG="$slug" BASE="$base" OUT="$out" WHICH="$which" python3 - <<'PY'
import json, os, re, sys, glob
slug, base, out, which = os.environ["SLUG"], os.environ["BASE"], os.environ["OUT"], os.environ["WHICH"]
fl = json.load(open("local/fleet.json")); owner = (fl.get("owner_name") or "").strip()
if not owner: sys.exit("render-routine-prompt: set \"owner_name\" in local/fleet.json first")
bot = next((b for b in fl["bots"] if b["slug"] == slug), None)
if not bot: sys.exit(f"render-routine-prompt: no bot '{slug}' in local/fleet.json")
bj_path = f"bots/{slug}/bot.json"
if not os.path.exists(bj_path): sys.exit(f"render-routine-prompt: missing {bj_path}; generate it with fleet/scripts/bot-json.sh {slug} (0.10.5+)")
bj = json.load(open(bj_path))
files = sorted(glob.glob(f"bots/{slug}/routines/*.json")) if which == "--all" else [f"bots/{slug}/routines/{which}.json"]
tmpl = open("templates/ROUTINE-PROMPT.tmpl").read()
for f in files:
    if not os.path.exists(f): sys.exit(f"render-routine-prompt: missing {f}")
    r = os.path.basename(f)[:-5]
    vals = {"BOT_NAME": bj["display_name"], "OWNER_NAME": bj["owner_name"], "SLUG": slug, "ROLE": bj["role"], "WORKTREE": bj["worktree"], "ROUTINE": r}
    txt = re.sub(r"\{\{(\w+)\}\}", lambda m: vals.get(m.group(1), m.group(0)), tmpl)
    left = re.findall(r"\{\{[^}]*\}\}", txt)
    if left: sys.exit(f"render-routine-prompt: unfilled placeholders {sorted(set(left))}")
    if out == "-": sys.stdout.write(txt); continue
    p = f"bots/{slug}/routines/{r}.prompt.md"
    open(p, "w").write("<!-- Rendered from templates/ROUTINE-PROMPT.tmpl by render-routine-prompt.sh. Instance file: re-render instead of hand-editing. -->\n" + txt)
    print(f"render-routine-prompt: wrote {p}")
PY
