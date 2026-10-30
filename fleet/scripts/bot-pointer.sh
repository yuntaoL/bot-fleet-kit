#!/usr/bin/env bash
# Usage: fleet/scripts/bot-pointer.sh <slug> [worktree-dir]   (0.10.5+; default dir: current worktree root)
#        fleet/scripts/bot-pointer.sh --read [worktree-dir]   print the slug the pointer names (exit 1 if missing/bad)
# Writes the untracked per-worktree pointer <worktree>/.bot holding one line: bots/<slug>/bot.json
# This is how a bot finds its identity knowing only its worktree path (no slug, name or role in any prompt).
# Keeps .bot out of git via the shared <git-common-dir>/info/exclude. Idempotent. Called by worktree.sh,
# create-bot.sh, rename-bot.sh (worktree step) and migrations/0.10.5.sh.
set -euo pipefail
if [ "${1:-}" = --read ]; then
  d="${2:-$(git rev-parse --show-toplevel)}"; [ -f "$d/.bot" ] || { echo "bot-pointer: no $d/.bot" >&2; exit 1; }
  l="$(head -n1 "$d/.bot" | tr -d '[:space:]')"
  [[ "$l" =~ ^bots/([a-z0-9-]+)/bot\.json$ ]] || { echo "bot-pointer: bad $d/.bot ('$l')" >&2; exit 1; }
  [ -f "$d/$l" ] || { echo "bot-pointer: $d/.bot points to missing $l" >&2; exit 1; }
  echo "${BASH_REMATCH[1]}"; exit 0
fi
slug="${1:?usage: bot-pointer.sh <slug> [worktree-dir] | --read [worktree-dir]}"
[[ "$slug" =~ ^[a-z0-9-]+$ ]] || { echo "bot-pointer: bad slug '$slug'" >&2; exit 2; }
d="${2:-$(git rev-parse --show-toplevel)}"; d="$(cd "$d" && pwd)"
want="bots/$slug/bot.json"
[ "$(cat "$d/.bot" 2>/dev/null)" = "$want" ] || { printf '%s\n' "$want" > "$d/.bot"; echo "bot-pointer: wrote $d/.bot -> $want"; }
ex="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)/info/exclude"; mkdir -p "$(dirname "$ex")"
grep -qxF '/.bot' "$ex" 2>/dev/null || echo '/.bot' >> "$ex"
