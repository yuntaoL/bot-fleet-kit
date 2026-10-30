#!/usr/bin/env bash
# Usage: fleet/scripts/compat.sh install|check|remove [--dry-run]
# 0.10.0 compatibility links: relative symlinks at the pre-0.10.0 paths (template/..., manager/...) pointing at the
# new layout, so a bot still running an OLD live prompt (which names template/rules/common.md, manager/overrides.md,
# manager/local/*.md, manager/roles/<role>.md, template/rules/routines.md, template/scripts/sync.sh, ...) reads and runs
# exactly the files it would have before. Live prompts change bot by bot; when every live prompt is re-rendered,
# `compat.sh remove` deletes the links (CHANGELOG 0.10.0, "shim cleanup"). Idempotent.
#   install  create missing links (run again after adding a local/rules/*.md file; validate.sh warns until you do)
#   check    print WARN/FAIL lines (missing, dangling or non-link files at compat paths); exit 0
#   remove   delete every compat link (refuses unless BOT_FLEET_REMOVE_COMPAT=1: confirm no live prompt uses old paths)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
cmd="${1:?usage: compat.sh install|check|remove [--dry-run]}"; dry=""; [ "${2:-}" = --dry-run ] && dry=1
# old path <TAB> new path (relative to repo root). Directory links cover files added later.
links(){
  for d in rules docs scripts schema migrations; do [ -d "fleet/$d" ] && printf 'template/%s\tfleet/%s\n' "$d" "$d"; done
  printf 'template/VERSION\tfleet/VERSION\ntemplate/OWNERS.json\tfleet/OWNERS.json\n'
  printf 'template/defaults/THIN-PROMPT.tmpl\ttemplates/THIN-PROMPT.tmpl\ntemplate/defaults/ROUTINE-PROMPT.tmpl\ttemplates/ROUTINE-PROMPT.tmpl\n'
  printf 'template/defaults/bot\ttemplates/bot\ntemplate/defaults/roles\tfleet/roles\n'
  [ -d local ] || return 0
  for f in local/*; do b="${f#local/}"; case "$b" in rules|roles) continue;; esac; [ -e "$f" ] && printf 'manager/%s\t%s\n' "$b" "$f"; done
  printf 'manager/roles\tfleet/roles\n'
  [ -d local/roles ] && printf 'manager/local/roles\tlocal/roles\n'
  for f in local/rules/*.md; do [ -e "$f" ] && printf 'manager/local/%s\t%s\n' "${f#local/rules/}" "$f"; done
  return 0
}
rel(){ python3 -c 'import os,sys;print(os.path.relpath(sys.argv[2],os.path.dirname(sys.argv[1])))' "$1" "$2"; }
case "$cmd" in
  install)
    links | while IFS=$'\t' read -r old new; do
      t="$(rel "$old" "$new")"
      if [ -L "$old" ]; then [ "$(readlink "$old")" = "$t" ] && continue; [ -n "$dry" ] && { echo "would relink $old -> $t"; continue; }; rm "$old"
      elif [ -e "$old" ]; then echo "compat: $old exists and is not a link; left alone" >&2; continue; fi
      [ -n "$dry" ] && { echo "would link $old -> $t"; continue; }
      mkdir -p "$(dirname "$old")"; ln -s "$t" "$old"; git add "$old"; echo "compat: $old -> $t"
    done ;;
  check)
    links | while IFS=$'\t' read -r old new; do
      if [ -L "$old" ]; then [ -e "$old" ] || echo "FAIL compat link $old is dangling (expected -> $new)"
      elif [ -e "$old" ]; then echo "WARN compat path $old is a real file, not a link to $new"
      else echo "WARN compat link $old missing (old prompts reading it will miss $new; run fleet/scripts/compat.sh install)"; fi
    done
    for l in $(git ls-files template manager 2>/dev/null); do [ -L "$l" ] || echo "WARN $l: leftover pre-0.10.0 file (not a compat link)"; done ;;
  remove)
    [ -n "$dry" ] || [ "${BOT_FLEET_REMOVE_COMPAT:-}" = 1 ] || { echo "compat: set BOT_FLEET_REMOVE_COMPAT=1 once every live prompt is re-rendered (check-routines.sh clean, thin prompts re-pasted)" >&2; exit 1; }
    for l in $(git ls-files template manager 2>/dev/null); do [ -L "$l" ] || continue
      [ -n "$dry" ] && { echo "would remove $l"; continue; }; git rm -q "$l"; echo "compat: removed $l"; done
    [ -n "$dry" ] || { rmdir -p template/defaults manager/local 2>/dev/null || true; rmdir template manager 2>/dev/null || true; } ;;
  *) echo "usage: compat.sh install|check|remove [--dry-run]" >&2; exit 2;;
esac
