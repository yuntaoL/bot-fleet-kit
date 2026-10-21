#!/usr/bin/env bash
# pre-commit hook: reject staged files outside bots/$BOT_NAME/ unless BOT_ROLE=manager
set -euo pipefail
[ "${BOT_ROLE:-}" = "manager" ] && exit 0
if [ -z "${BOT_NAME:-}" ]; then echo "check-boundary: set BOT_NAME=<your-slug> (or BOT_ROLE=manager)" >&2; exit 1; fi
bad=$(git diff --cached --name-only | grep -v "^bots/${BOT_NAME}/" || true)
if [ -n "$bad" ]; then echo "check-boundary: $BOT_NAME may only commit bots/$BOT_NAME/. Offending:" >&2; echo "$bad" >&2; exit 1; fi
