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
# 0.9.0 role files: manager/roles/*.md are template-owned copies. Unedited ones (equal to the current default
# or the target default) are replaced automatically; an edited one stops the upgrade with a diff, before anything changes.
# Move the additions to manager/local/roles/<role>.md, reset the file, and rerun. BOT_FLEET_KEEP_ROLES=1 skips the stop
# and leaves edited role files untouched (listed only).
edited=""
for b in $(git ls-tree --name-only "v$target:template/defaults/roles/" 2>/dev/null); do
  [ -f "manager/roles/$b" ] || continue
  git show "v$target:template/defaults/roles/$b" | cmp -s - "manager/roles/$b" && continue
  git show "HEAD:template/defaults/roles/$b" 2>/dev/null | cmp -s - "manager/roles/$b" && continue
  edited="$edited $b"
done
if [ -n "$edited" ] && [ -z "${BOT_FLEET_KEEP_ROLES:-}" ]; then
  echo "STOP: these role files were edited locally:$edited" >&2
  for b in $edited; do git show "v$target:template/defaults/roles/$b" | diff -u --label "v$target:template/defaults/roles/$b" - --label "manager/roles/$b" "manager/roles/$b" >&2 || true; done
  echo "Move the additions to manager/local/roles/<role>.md, reset the file to the current template default, commit, and rerun (or BOT_FLEET_KEEP_ROLES=1 to keep them as they are). Nothing was changed." >&2
  exit 1
fi
TEMPLATE_PATHS="template .github"   # examples/ is template-repo only: never copied, never deleted
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
mkdir -p manager/roles
for f in template/defaults/roles/*.md; do b=$(basename "$f")
  cmp -s "$f" "manager/roles/$b" && continue
  case " $edited " in *" $b "*) echo "  kept edited manager/roles/$b (BOT_FLEET_KEEP_ROLES); diff -u $f manager/roles/$b";;
    *) cp "$f" "manager/roles/$b"; echo "  updated manager/roles/$b from template";; esac
done
echo "$target" > template/VERSION
python3 -c "import json;p='manager/fleet.json';f=json.load(open(p));f['templateVersion']='$target';json.dump(f,open(p,'w'),indent=2,ensure_ascii=False);open(p,'a').write('\n')"
chmod +x template/scripts/*.sh; template/scripts/install-hook.sh
template/scripts/validate.sh || echo "WARNING: validation failed, review before pushing"
git add -A
BOT_FLEET_UPGRADE=1 BOT_ROLE=manager git commit -qm "chore: upgrade template $current -> $target"
[ -d examples ] && echo "note: this fleet has an examples/ folder; it is template-repo only and not managed by upgrades. Remove it by hand if you do not need it (git rm -r examples)." || true
echo "Upgraded $current -> $target. Review with 'git show --stat', then: git push origin HEAD:main"
