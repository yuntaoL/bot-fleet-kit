#!/usr/bin/env bash
# 0.10.0: split template/ into fleet/ (used as-is) + templates/ (placeholders, starters); rename manager/ to local/.
# Usage: bash fleet/migrations/0.10.0.sh [--dry-run]   (upgrade.sh runs it; idempotent; --dry-run prints and changes nothing)
#  1. role copies: manager/roles/<role>.md are dropped (bots now read fleet/roles/<role>.md). An edited copy STOPS the
#     migration before anything changes: move the additions to manager/local/roles/<role>.md, reset the copy, rerun.
#  2. git mv: manager/local/roles -> local/roles, manager/local/* -> local/rules/, manager/* -> local/*,
#     template/* -> fleet/* or templates/* (an old file whose new path already exists, e.g. after upgrade.sh checked
#     out the new release, is git rm'd instead).
#  3. path references: rewrite-paths.py on current-state text only: bots/*/ (rules, instructions, memory, kb, skills,
#     routine json and steps), local/ and README.md. NOT rewritten: journals, CHANGELOGs, *.old-prompt.md (rollback
#     copies of what was live), rendered *.prompt.md / THIN-PROMPT.md (they record the live prompt; re-rendered per bot at
#     rollout), secrets.md, local/shared/state/ (data). History stays true to what happened; old paths in it still resolve
#     through step 4 until cleanup.
#  4. compat links at the old paths (fleet/scripts/compat.sh install) so un-switched live prompts keep working.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
DRY=""; [ "${1:-}" = --dry-run ] && DRY=1
run(){ if [ -n "$DRY" ]; then echo "would: $*"; else "$@"; fi; }
mv_(){ # git mv $1 -> $2, or drop $1 if $2 already exists
  [ -e "$1" ] || [ -L "$1" ] || return 0; [ -L "$1" ] && [ "${1%%/*}" != bots ] && return 0   # compat link from a previous run
  if [ -e "$2" ]; then cmp -s "$1" "$2" || [ "${1%%/*}" = template ] || { echo "STOP: both $1 and $2 exist and differ" >&2; exit 1; }
    run git rm -q "$1"; [ -n "$DRY" ] || echo "dropped $1 ($2 exists)"; return 0; fi
  [ -n "$DRY" ] || mkdir -p "$(dirname "$2")"; run git mv "$1" "$2"; [ -n "$DRY" ] || echo "moved $1 -> $2"
}
# 1. role copies
edited=""
for f in manager/roles/*.md; do [ -f "$f" ] && [ ! -L "$f" ] && [ ! -L manager/roles ] || continue; b="$(basename "$f")"
  same=""; for d in "fleet/roles/$b" "template/defaults/roles/$b"; do [ -f "$d" ] && cmp -s "$f" "$d" && same=1; done
  git show "HEAD:template/defaults/roles/$b" 2>/dev/null | cmp -s - "$f" && same=1
  [ -n "$same" ] || edited="$edited $f"
done
[ -z "$edited" ] || { echo "STOP: edited role copies:$edited. Move the additions to manager/local/roles/<role>.md, reset the copy to the template default, commit, rerun. Nothing was changed." >&2; exit 1; }
for f in manager/roles/*.md; do [ -f "$f" ] && [ ! -L "$f" ] && [ ! -L manager/roles ] || continue; run git rm -q "$f"; [ -n "$DRY" ] || echo "dropped $f (read fleet/roles/$(basename "$f"))"; done
# 2. moves (tracked files only; compat links are skipped)
if [ -d manager/local ] && [ ! -L manager/local ]; then
  for f in $(git ls-files manager/local/roles); do mv_ "$f" "local/roles/${f#manager/local/roles/}"; done
  for f in $(git ls-files manager/local); do case "$f" in manager/local/roles/*) continue;; esac; mv_ "$f" "local/rules/${f#manager/local/}"; done
fi
for f in $(git ls-files manager); do [ -L "$f" ] && continue; mv_ "$f" "local/${f#manager/}"; done
for f in $(git ls-files template); do [ -L "$f" ] && continue
  case "$f" in
    template/defaults/THIN-PROMPT.tmpl|template/defaults/ROUTINE-PROMPT.tmpl) n="templates/${f#template/defaults/}";;
    template/defaults/fleet/skills/*) n="fleet/skills/${f#template/defaults/fleet/skills/}";;
    template/defaults/fleet/*) n="templates/local/${f#template/defaults/fleet/}";;
    template/defaults/roles/*) n="fleet/roles/${f#template/defaults/roles/}";;
    template/defaults/*) n="templates/${f#template/defaults/}";;
    *) n="fleet/${f#template/}";;
  esac; mv_ "$f" "$n"
done
[ -n "$DRY" ] || { find manager template -depth -type d -empty -delete 2>/dev/null || true; }
# 3. path references in current-state text (see header for what is skipped and why)
RW="fleet/scripts/rewrite-paths.py"; [ -f "$RW" ] || RW="template/scripts/rewrite-paths.py"
files=$(git ls-files bots local README.md 2>/dev/null | grep -vE '(^|/)journal/|CHANGELOG|\.old-prompt\.md$|\.prompt\.md$|(^|/)THIN-PROMPT\.md$|(^|/)secrets\.md$|^local/shared/state/' | while read -r f; do [ -L "$f" ] || [ ! -f "$f" ] || echo "$f"; done)
if [ -n "$files" ] && [ -f "$RW" ]; then python3 "$RW" ${DRY:+--dry-run} $files; [ -n "$DRY" ] || git add -- $files; fi
# 4. compat links
if [ -f fleet/scripts/compat.sh ]; then bash fleet/scripts/compat.sh install ${DRY:+--dry-run}; fi
echo "migration 0.10.0: ${DRY:+dry run }done"
