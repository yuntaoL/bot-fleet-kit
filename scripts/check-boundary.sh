#!/usr/bin/env bash
# pre-commit hook. BOT_ROLE: manager | builder | worker | retired ; BOT_NAME: your slug.
set -euo pipefail
role="${BOT_ROLE:-worker}"
st=$(git diff --cached --name-status --no-renames)
staged=$(echo "$st" | awk 'NF{print $2}')
fail(){ echo "check-boundary: $1" >&2; shift; printf '%s\n' "$@" >&2; exit 1; }
[ "$role" = "retired" ] && fail "retired bots are read-only"
# Template-owned files change only via scripts/upgrade.sh (it sets BOT_FLEET_UPGRADE=1).
tmpl=$(echo "$staged" | grep -E '^(rules/common\.md|rules/README\.md|docs/|scripts/|schema/|migrations/|templates/|\.github/)' || true)
[ -n "$tmpl" ] && [ "${BOT_FLEET_UPGRADE:-}" != "1" ] && fail "template-owned files change only via scripts/upgrade.sh (or a human-approved rules/local/overrides.md entry):" $tmpl
# bots/<x>/rules.md: only bot <x> may MODIFY or delete it; manager/builder/upgrade may only create it.
while read -r s f; do
  [[ "$f" =~ ^bots/([^/]+)/rules\.md$ ]] || continue
  owner="${BASH_REMATCH[1]}"
  [ "${BOT_NAME:-}" = "$owner" ] && continue
  [ "$s" = "A" ] && { [ "$role" = manager ] || [ "$role" = builder ] || [ "${BOT_FLEET_UPGRADE:-}" = 1 ]; } && continue
  fail "only $owner edits $f (others request changes by message)"
done <<< "$st"
[ "$role" = "manager" ] && exit 0
prot=$(echo "$staged" | grep -E '^(rules/|shared/|fleet\.json$)' || true)
[ -n "$prot" ] && fail "only BOT_ROLE=manager may stage rules/, shared/, fleet.json:" $prot
if [ "$role" = "builder" ] && [ "${BOT_RESTORE:-}" = "1" ]; then allow='^bots/'; else
  [ -z "${BOT_NAME:-}" ] && fail "set BOT_NAME=<your-slug>"
  allow="^bots/${BOT_NAME}/"; fi
bad=$(echo "$staged" | grep -v -E "$allow" | grep -v '^$' || true)
[ -n "$bad" ] && fail "${BOT_NAME:-builder} ($role) may not stage:" $bad
exit 0
