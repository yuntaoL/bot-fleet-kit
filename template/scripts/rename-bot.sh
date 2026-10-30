#!/usr/bin/env bash
# Usage: template/scripts/rename-bot.sh <old-slug> <new-slug> <refs|expand|worktree|contract> [--dry-run]
# Git parts of the rename-bot skill (template/defaults/fleet/skills/rename-bot/SKILL.md).
#   refs      grep the repo for bots/<old>, the old worktree dir and wt/<old> (template/, journals, CHANGELOGs excluded)
#   expand    copy bots/<old>/ -> bots/<new>/ and commit (builder: BOT_RESTORE=1 BOT_ROLE=builder)
#   worktree  move <base>/<old> -> <base>/<new>, rename branch wt/<old> -> wt/<new>, set fleet.bot, prune (run from any checkout)
#   contract  git rm bots/<old>/ and commit (run as the old identity: BOT_NAME=<old>)
# Worktree base: BOT_FLEET_WORKTREES or <parent of shared clone>/bot-fleet-worktrees. --dry-run prints, changes nothing.
set -euo pipefail
old="${1:?usage}"; new="${2:?usage}"; cmd="${3:?usage}"; dry=0; [ "${4:-}" = --dry-run ] && dry=1
[[ "$new" =~ ^[a-z0-9-]+$ ]] || { echo "rename-bot: bad slug '$new'" >&2; exit 2; }
cd "$(git rev-parse --show-toplevel)"
common="$(git rev-parse --path-format=absolute --git-common-dir)"
base="${BOT_FLEET_WORKTREES:-$(dirname "$(dirname "$common")")/bot-fleet-worktrees}"
run(){ echo "+ $*"; [ $dry = 1 ] || "$@"; }
clean(){ [ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ] || { echo "rename-bot: $1 not clean" >&2; exit 1; }; }
case "$cmd" in
  refs)
    git grep -nE "bots/$old([/[:space:]\`'\"]|$)|bot-fleet-worktrees/$old([/[:space:]\`'\"]|$)|wt/$old([^a-z0-9-]|$)" -- . \
      ':!template/**' ':!**/journal/**' ':!**/CHANGELOG.md' ':!**/snapshots/**' || echo "rename-bot: no references"
    ;;
  expand)
    [ -d "bots/$old" ] || { echo "rename-bot: no bots/$old" >&2; exit 1; }
    [ ! -e "bots/$new" ] || { echo "rename-bot: bots/$new exists" >&2; exit 1; }
    clean .; run cp -r "bots/$old" "bots/$new"; run git add "bots/$new"
    run git commit -qm "${BOT_NAME:-$(git config --get fleet.bot || echo builder)}: rename $old -> $new (expand: copy folder)"
    ;;
  worktree)
    o="$base/$old"; n="$base/$new"
    [ -e "$o/.git" ] || { echo "rename-bot: no worktree $o" >&2; exit 1; }
    [ ! -e "$n" ] || { echo "rename-bot: $n exists" >&2; exit 1; }
    clean "$o"
    git -C "$o" status --porcelain --ignored | grep -E '^(\?\?|!!)' | sed 's/^/untracked (moves with dir): /' || true
    run git worktree move "$o" "$n"
    if git show-ref -q --verify "refs/heads/wt/$old"; then run git branch -m "wt/$old" "wt/$new"; fi
    run git -C "$n" branch -q --set-upstream-to=origin/main "wt/$new"
    run git -C "$n" config --worktree fleet.bot "$new"
    run git worktree prune
    ;;
  contract)
    [ -d "bots/$old" ] || { echo "rename-bot: bots/$old already gone"; exit 0; }
    [ -d "bots/$new" ] || { echo "rename-bot: bots/$new missing; expand first" >&2; exit 1; }
    clean .; run git rm -rq "bots/$old"
    run git commit -qm "${BOT_NAME:-$old}: rename $old -> $new (contract: remove old folder)"
    ;;
  *) echo "rename-bot: unknown step '$cmd'" >&2; exit 2;;
esac
