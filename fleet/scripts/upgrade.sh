#!/usr/bin/env bash
# Usage: BOT_ROLE=manager fleet/scripts/upgrade.sh <version> [--dry-run]   (manager's worktree; see fleet/docs/VERSIONING.md)
#   (a pre-0.10.0 fleet runs its old copy: template/scripts/upgrade.sh <version>; it re-executes this file from the tag)
# --dry-run: runs the whole upgrade in a throwaway detached worktree of HEAD, prints the resulting change list
#            (git diff --stat -M) and validate output, then deletes it. Your worktree and branch are not touched.
# Env: BOT_FLEET_UPGRADE_NOFETCH=1 uses an existing local tag v<version> (testing), BOT_FLEET_KEEP_ROLES (pre-0.10 only).
set -euo pipefail
target="${1:?usage: upgrade.sh <version> [--dry-run]}"; target="${target#v}"; DRY=""; [ "${2:-}" = --dry-run ] && DRY=1
cd "$(git rev-parse --show-toplevel)"
git remote get-url upstream >/dev/null 2>&1 || [ -n "${BOT_FLEET_UPGRADE_NOFETCH:-}" ] || { echo "add upstream first: git remote add upstream <template-url>" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "working tree not clean" >&2; exit 1; }
current="$(cat fleet/VERSION 2>/dev/null || cat template/VERSION 2>/dev/null || cat VERSION 2>/dev/null || echo 0.0.0)"
vge(){ [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]; }
vgt(){ vge "$1" "$2" && [ "$1" != "$2" ]; }
vgt 0.3.2 "$current" && vge "$target" 0.4.0 && { echo "upgrade to 0.3.2 first (stepping stone)" >&2; exit 1; }
[ -n "${BOT_FLEET_UPGRADE_NOFETCH:-}" ] || git fetch -q upstream "refs/tags/v$target:refs/tags/v$target" --force
if [ -z "${BOT_FLEET_UPGRADE_REEXEC:-}" ]; then
  tmp="$(mktemp)"; git show "v$target:fleet/scripts/upgrade.sh" > "$tmp" 2>/dev/null || git show "v$target:template/scripts/upgrade.sh" > "$tmp"
  BOT_FLEET_UPGRADE_REEXEC=1 exec bash "$tmp" "$target" ${DRY:+--dry-run}
fi
if [ -n "$DRY" ]; then
  d="$(mktemp -d)/dry"; git worktree add -q --detach "$d" HEAD; trap 'git worktree remove --force "$d" >/dev/null 2>&1; git worktree prune' EXIT
  role="$(git config --get fleet.role || echo manager)"
  (cd "$d" && git config --worktree fleet.role "$role" 2>/dev/null; BOT_ROLE=manager BOT_FLEET_UPGRADE_NOFETCH=1 BOT_FLEET_UPGRADE_REEXEC=1 bash "$0" "$target" >"$d.log" 2>&1) || { cat "$d.log"; echo "dry run: upgrade FAILED (nothing changed here)"; exit 1; }
  cat "$d.log"; echo; echo "## dry run: changes the upgrade would commit"; git -C "$d" diff --stat -M HEAD~1 HEAD | tail -40
  echo "dry run: your worktree is unchanged"; exit 0
fi
# Pre-0.10.0 role copies (manager/roles/*.md) are handled by migration 0.10.0 (dropped; an edited copy stops it).
TEMPLATE_PATHS="fleet templates .github"   # examples/ is template-repo only: never copied, never deleted
LEGACY_PATHS="template rules/common.md rules/README.md docs scripts schema migrations AGENT_GUIDE.md RESTORE.md VERSIONING.md CONTRIBUTING.md VERSION"
for p in $TEMPLATE_PATHS; do git cat-file -e "v$target:$p" 2>/dev/null && git checkout "v$target" -- "$p"; done
for f in $(git ls-files -- $TEMPLATE_PATHS $LEGACY_PATHS); do
  [ -L "$f" ] && case "$f" in template/*) continue;; esac          # 0.10.0 compat links (compat.sh owns them)
  case "$f" in template/*) [ -f fleet/migrations/0.10.0.sh ] && vgt 0.10.0 "$current" && continue;; esac  # migration moves these
  git cat-file -e "v$target:$f" 2>/dev/null || { git rm -q "$f"; echo "removed $f"; }
done
for m in $(ls fleet/migrations/*.sh 2>/dev/null | sort -V); do
  v="$(basename "$m" .sh)"
  if vgt "$v" "$current" && ! vgt "$v" "$target"; then echo "running migration $v"; bash "$m"; fi
done
fleet/scripts/init-fleet.sh >/dev/null
echo "$target" > fleet/VERSION
python3 -c "import json;p='local/fleet.json';f=json.load(open(p));f['templateVersion']='$target';json.dump(f,open(p,'w'),indent=2,ensure_ascii=False);open(p,'a').write('\n')"
chmod +x fleet/scripts/*.sh; fleet/scripts/install-hook.sh
[ -d manager ] || [ -d template ] && fleet/scripts/compat.sh install >/dev/null || true
fleet/scripts/validate.sh || echo "WARNING: validation failed, review before pushing"
git add -A
BOT_FLEET_UPGRADE=1 BOT_ROLE=manager git commit -qm "chore: upgrade template $current -> $target"
[ -d examples ] && echo "note: this fleet has an examples/ folder; it is template-repo only and not managed by upgrades. Remove it by hand if you do not need it (git rm -r examples)." || true
echo "Upgraded $current -> $target. Review with 'git show --stat -M', then: git push origin HEAD:main"
