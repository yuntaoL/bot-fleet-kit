#!/usr/bin/env bash
# Usage: BOT_ROLE=manager fleet/scripts/upgrade.sh <version> [--dry-run]   (manager's worktree; see fleet/docs/VERSIONING.md)
# Stable starter: fetches tag v<version>, unpacks that version's scripts into .git/fleet-upgrade/ (inside .git, so never
# tracked), then execs THAT version's upgrade script against this worktree. The target version always upgrades itself.
# Engine lookup in the tag: fleet/scripts/upgrade-run.sh (0.10.1+), else fleet/scripts/upgrade.sh (0.10.0),
# else template/scripts/upgrade.sh (0.9.x and older).
# Env: BOT_FLEET_UPGRADE_NOFETCH=1 uses an existing local tag v<version> (testing).
set -euo pipefail
target="${1:?usage: upgrade.sh <version> [--dry-run]}"; target="${target#v}"
cd "$(git rev-parse --show-toplevel)"
if [ -z "${BOT_FLEET_UPGRADE_NOFETCH:-}" ]; then
  git remote get-url upstream >/dev/null 2>&1 || { echo "add upstream first: git remote add upstream <template-url>" >&2; exit 1; }
  git fetch -q upstream "refs/tags/v$target:refs/tags/v$target" --force
fi
git rev-parse -q --verify "v$target^{commit}" >/dev/null || { echo "no tag v$target" >&2; exit 1; }
dir="$(git rev-parse --absolute-git-dir)/fleet-upgrade/v$target"; rm -rf "$dir"; mkdir -p "$dir"
for e in fleet/scripts/upgrade-run.sh fleet/scripts/upgrade.sh template/scripts/upgrade.sh; do
  git cat-file -e "v$target:$e" 2>/dev/null || continue
  [ "$e" = template/scripts/upgrade.sh ] && [ "${2:-}" = --dry-run ] && { echo "v$target predates --dry-run; nothing changed" >&2; exit 1; }
  git archive "v$target" "$(dirname "$e")" | tar -x -C "$dir"
  echo "upgrade: running $e from v$target"
  BOT_FLEET_UPGRADE_NOFETCH=1 BOT_FLEET_UPGRADE_REEXEC=1 exec bash "$dir/$e" "$@"
done
echo "v$target has no upgrade script" >&2; exit 1
