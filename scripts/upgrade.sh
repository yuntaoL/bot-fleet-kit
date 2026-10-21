#!/usr/bin/env bash
# Usage: BOT_ROLE=manager scripts/upgrade.sh <version>   (see docs/VERSIONING.md)
set -euo pipefail
target="${1:?usage: upgrade.sh <version>}"; target="${target#v}"
cd "$(git rev-parse --show-toplevel)"
git remote get-url upstream >/dev/null 2>&1 || { echo "add upstream first: git remote add upstream <template-url>" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }
current="$(cat VERSION 2>/dev/null || echo 0.0.0)"
git fetch upstream "refs/tags/v$target:refs/tags/v$target" --force
# Re-exec with the TARGET version's upgrade.sh so its path list and logic apply.
if [ -z "${BOT_FLEET_UPGRADE_REEXEC:-}" ]; then
  tmp="$(mktemp)"; git show "v$target:scripts/upgrade.sh" > "$tmp"
  BOT_FLEET_UPGRADE_REEXEC=1 exec bash "$tmp" "$target"
fi
TEMPLATE_PATHS="rules/common.md rules/README.md docs scripts schema migrations templates .github"
LEGACY_PATHS="AGENT_GUIDE.md RESTORE.md VERSIONING.md CONTRIBUTING.md"   # pre-0.2.0 root docs, now in docs/
for p in $TEMPLATE_PATHS; do git cat-file -e "v$target:$p" 2>/dev/null && git checkout "v$target" -- "$p"; done
# Delete files the template removed (template-owned paths only).
for f in $(git ls-files -- $TEMPLATE_PATHS $LEGACY_PATHS); do
  git cat-file -e "v$target:$f" 2>/dev/null || { git rm -q "$f"; echo "removed $f"; }
done
vgt(){ [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && [ "$1" != "$2" ]; }
for m in $(ls migrations/*.sh 2>/dev/null | sort -V); do
  v="$(basename "$m" .sh)"
  if vgt "$v" "$current" && ! vgt "$v" "$target"; then echo "running migration $v"; bash "$m"; fi
done
# Role rules are fleet-owned: never overwrite, only report differences vs the new defaults.
echo "== role-rule defaults vs your rules/roles/ (review and merge by hand; nothing was changed) =="
for f in templates/rules/roles/*.md; do b=$(basename "$f")
  if [ -f "rules/roles/$b" ]; then diff -u "rules/roles/$b" "$f" --label "rules/roles/$b (yours)" --label "$f (v$target default)" || true
  else echo "missing rules/roles/$b (scripts/init-fleet-docs.sh copies defaults)"; fi; done
echo "$target" > VERSION
[ -f fleet.json ] && python3 -c "import json;f=json.load(open('fleet.json'));f['templateVersion']='$target';json.dump(f,open('fleet.json','w'),indent=2,ensure_ascii=False);open('fleet.json','a').write('\n')"
chmod +x scripts/*.sh
scripts/validate.sh || echo "WARNING: validation failed, review before pushing"
git add -A -- $TEMPLATE_PATHS VERSION rules bots shared fleet.json README.md CHANGELOG.md 2>/dev/null || true
BOT_FLEET_UPGRADE=1 BOT_ROLE=manager git commit -qm "chore: upgrade template $current -> $target"
echo "Upgraded $current -> $target. Review with 'git show --stat', then push."
