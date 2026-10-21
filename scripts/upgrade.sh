#!/usr/bin/env bash
# Usage: BOT_ROLE=manager scripts/upgrade.sh <version>   (see VERSIONING.md)
set -euo pipefail
target="${1:?usage: upgrade.sh <version>}"; target="${target#v}"
cd "$(git rev-parse --show-toplevel)"
git remote get-url upstream >/dev/null 2>&1 || { echo "add upstream first: git remote add upstream <template-url>" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }
current="$(cat VERSION 2>/dev/null || echo 0.0.0)"
git fetch upstream "refs/tags/v$target:refs/tags/v$target"
PATHS="scripts schema migrations templates AGENT_GUIDE.md RESTORE.md VERSIONING.md .github"
for p in $PATHS; do git checkout "v$target" -- "$p" 2>/dev/null || true; done
vgt(){ [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }
for m in $(ls migrations/*.sh 2>/dev/null | sort -V); do
  v="$(basename "$m" .sh)"
  if vgt "$v" "$current" && ! vgt "$v" "$target"; then echo "running migration $v"; bash "$m"; fi
done
echo "$target" > VERSION
[ -f fleet.json ] && python3 -c "import json;f=json.load(open('fleet.json'));f['templateVersion']='$target';json.dump(f,open('fleet.json','w'),indent=2,ensure_ascii=False);open('fleet.json','a').write('\n')"
scripts/validate.sh || echo "WARNING: validation failed, review before pushing"
chmod +x scripts/*.sh
git add -A $PATHS VERSION fleet.json 2>/dev/null || true; git add -A bots shared 2>/dev/null || true
BOT_ROLE=manager git commit -m "chore: upgrade template $current -> $target"
echo "Upgraded $current -> $target. Review with 'git show', then push."
