#!/usr/bin/env bash
# Read-only snapshot of every bot (profile, settings, automations, memory store, git folder, worktree HEAD/status) OUTSIDE git.
# Usage: snapshot-fleet.sh [label]  -> $SNAPSHOT_ROOT/<YYYY-MM-DD-HHMM>[-label]/<slug>/ + MANIFEST.sha256 (mode 700).
# Always a NEW timestamped folder; refuses to overwrite. Never commit snapshots.
# Env: AGENT_DATA (default /home/box/agent-data/agents), SNAPSHOT_ROOT (default /home/box/fleet-snapshots),
#      FLEET_REPO (default: this repo), WORKTREES (default: parent dir of this worktree).
set -euo pipefail
REPO=${FLEET_REPO:-$(git rev-parse --show-toplevel)}; AG=${AGENT_DATA:-/home/box/agent-data/agents}
ROOT=${SNAPSHOT_ROOT:-/home/box/fleet-snapshots}; WT=${WORKTREES:-$(dirname "$REPO")}
LABEL=${1:-}; OUT="$ROOT/$(date +%F-%H%M)${LABEL:+-$LABEL}"
[ -e "$OUT" ] && { echo "refusing to overwrite existing snapshot $OUT" >&2; exit 1; }
mkdir -p "$OUT"; chmod 700 "$ROOT" "$OUT"
for d in "$AG"/*/; do
  [ -f "$d/profile.json" ] || continue
  id=$(basename "$d"); name=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('name',''))" "$d/profile.json")
  slug=$(python3 -c "import sys,re;n=sys.argv[1].split('·')[0].strip().lower();print(re.sub(r'[^a-z0-9]+','-',n).strip('-'))" "$name")
  s="$OUT/$slug"; mkdir -p "$s/agent"; echo "$id" > "$s/agent-id"; echo "$name" > "$s/name"
  cp -p "$d/profile.json" "$d/settings.json" "$s/agent/" 2>/dev/null || true
  [ -d "$d/automations" ] && cp -rp "$d/automations" "$s/agent/"
  for f in store.db store.db-wal store.db-shm; do [ -f "$d/$f" ] && cp -p "$d/$f" "$s/agent/"; done
  git -C "$REPO" cat-file -e "origin/main:bots/$slug" 2>/dev/null && git -C "$REPO" archive origin/main "bots/$slug" | tar -x -C "$s" 2>/dev/null || true
  w="$WT/$slug"
  if [ -d "$w/.git" ] || [ -f "$w/.git" ]; then git -C "$w" rev-parse HEAD > "$s/worktree-HEAD"; git -C "$w" status --porcelain > "$s/worktree-status"; echo "$w" > "$s/worktree-path"; fi
done
git -C "$REPO" rev-parse origin/main > "$OUT/origin-main" 2>/dev/null || true
(cd "$OUT" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 -r sha256sum > MANIFEST.sha256)
echo "snapshot: $OUT"
