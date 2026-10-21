#!/usr/bin/env bash
# Usage: BOT_ROLE=manager template/scripts/upgrade.sh <version>   (run in the manager's worktree; see docs/VERSIONING.md)
set -euo pipefail
target="${1:?usage: upgrade.sh <version>}"; target="${target#v}"
cd "$(git rev-parse --show-toplevel)"
git remote get-url upstream >/dev/null 2>&1 || { echo "add upstream first: git remote add upstream <template-url>" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }
current="$(cat template/VERSION 2>/dev/null || cat VERSION 2>/dev/null || echo 0.0.0)"
vge(){ [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }
vgt(){ vge "$1" "$2" && [ "$1" != "$2" ]; }
vgt 0.3.2 "$current" && vge "$target" 0.4.0 && { echo "upgrade to 0.3.2 first (stepping stone)" >&2; exit 1; }
git fetch -q upstream "refs/tags/v$target:refs/tags/v$target" --force
if [ -z "${BOT_FLEET_UPGRADE_REEXEC:-}" ]; then
  tmp="$(mktemp)"; git show "v$target:template/scripts/upgrade.sh" > "$tmp"
  BOT_FLEET_UPGRADE_REEXEC=1 exec bash "$tmp" "$target"
fi
TEMPLATE_PATHS="template .github"
LEGACY_PATHS="rules/common.md rules/README.md docs scripts schema migrations templates AGENT_GUIDE.md RESTORE.md VERSIONING.md CONTRIBUTING.md VERSION"
for p in $TEMPLATE_PATHS; do git cat-file -e "v$target:$p" 2>/dev/null && git checkout "v$target" -- "$p"; done
for f in $(git ls-files -- $TEMPLATE_PATHS $LEGACY_PATHS); do
  git cat-file -e "v$target:$f" 2>/dev/null || { git rm -q "$f"; echo "removed $f"; }
done
for m in $(ls template/migrations/*.sh 2>/dev/null | sort -V); do
  v="$(basename "$m" .sh)"
  if vgt "$v" "$current" && ! vgt "$v" "$target"; then echo "running migration $v"; bash "$m"; fi
done
template/scripts/init-fleet.sh >/dev/null
echo "== role defaults (template/defaults/roles) vs manager/roles: review and merge by hand; nothing changed =="
for f in template/defaults/roles/*.md; do b=$(basename "$f")
  diff -q "manager/roles/$b" "$f" >/dev/null 2>&1 || echo "  differs: manager/roles/$b  (diff -u manager/roles/$b $f)"; done
echo "$target" > template/VERSION
python3 -c "import json;p='manager/fleet.json';f=json.load(open(p));f['templateVersion']='$target';json.dump(f,open(p,'w'),indent=2,ensure_ascii=False);open(p,'a').write('\n')"
chmod +x template/scripts/*.sh; template/scripts/install-hook.sh
template/scripts/validate.sh || echo "WARNING: validation failed, review before pushing"
git add -A
BOT_FLEET_UPGRADE=1 BOT_ROLE=manager git commit -qm "chore: upgrade template $current -> $target"
echo "Upgraded $current -> $target. Review with 'git show --stat', then: git push origin HEAD:main"
