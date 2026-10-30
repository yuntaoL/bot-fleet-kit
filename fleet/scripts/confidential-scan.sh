#!/usr/bin/env bash
# Confidentiality scanner. Patterns (extended regex, one per line) live OUTSIDE git:
#   $FLEET_PRIVATE_DIR/confidential-patterns.txt (default ~/.fleet-private/); optional confidential-allow.txt.
# Usage: confidential-scan.sh [--staged|--all]. Prints path:line only, never the matched text. Exit 1 on hit; 0 if no pattern file.
set -u
cd "$(git rev-parse --show-toplevel)"
dir="${FLEET_PRIVATE_DIR:-$HOME/.fleet-private}"; pat="$dir/confidential-patterns.txt"; allow="$dir/confidential-allow.txt"
[ -r "$pat" ] || { echo "confidential-scan: no pattern file ($pat); skipping" >&2; exit 0; }
mode="${1:---staged}"; hits=0
check() { local h=0; while IFS= read -r l; do
    txt="${l#*:*:}"; loc="${l%%:"$txt"}"
    if [ -r "$allow" ] && printf '%s' "$txt" | grep -qiEf "$allow"; then continue; fi
    echo "confidential-scan: HIT $loc" >&2; h=1
  done; return $h; }
if [ "$mode" = --all ]; then
  git grep -nIiE -f "$pat" -- . | check || hits=1
else
  while IFS= read -r f; do [ -n "$f" ] || continue
    git show ":$f" 2>/dev/null | grep -nIiE -f "$pat" | sed "s|^|$f:|" | check || hits=1
  done < <(git diff --cached --name-only --diff-filter=AM)
fi
[ $hits -eq 0 ] && echo "confidential-scan: clean ($mode)" >&2
exit $hits
