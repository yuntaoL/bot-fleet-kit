#!/usr/bin/env bash
# pre-commit hook. BOT_ROLE: manager | builder | worker | retired ; BOT_NAME: your slug.
set -euo pipefail
role="${BOT_ROLE:-worker}"
[ "$role" = "manager" ] && exit 0
[ "$role" = "retired" ] && { echo "check-boundary: retired bots are read-only" >&2; exit 1; }
staged=$(git diff --cached --name-only)
prot=$(echo "$staged" | grep -E '^(rules/|shared/|fleet\.json$)' || true)
[ -n "$prot" ] && { echo "check-boundary: only BOT_ROLE=manager may stage rules/, shared/, fleet.json:" >&2; echo "$prot" >&2; exit 1; }
if [ "$role" = "builder" ] && [ "${BOT_RESTORE:-}" = "1" ]; then allow='^bots/'; else
  [ -z "${BOT_NAME:-}" ] && { echo "check-boundary: set BOT_NAME=<your-slug>" >&2; exit 1; }
  allow="^bots/${BOT_NAME}/"; fi
bad=$(echo "$staged" | grep -v -E "$allow" | grep -v '^$' || true)
[ -n "$bad" ] && { echo "check-boundary: ${BOT_NAME:-builder} ($role) may not stage:" >&2; echo "$bad" >&2; exit 1; }
exit 0
