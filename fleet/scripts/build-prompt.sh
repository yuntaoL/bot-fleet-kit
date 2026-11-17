#!/usr/bin/env bash
# Compile one prompt per bot from the thin prompt, the prompt digests, and that bot's action index.
# Usage:
#   fleet/scripts/build-prompt.sh [slug...]
#   fleet/scripts/build-prompt.sh --check [--json]
#   fleet/scripts/build-prompt.sh --changelog
#   fleet/scripts/build-prompt.sh --mark-deployed <slug>
#   fleet/scripts/build-prompt.sh --check-versions
# prompt_mode files (the default) does not write a compiled prompt.
# Never edits a live platform profile. See fleet/docs/COMPILED-PROMPTS.md.
set -euo pipefail
export LC_ALL=C PYTHONDONTWRITEBYTECODE=1
cd "$(git rev-parse --show-toplevel)"
exec python3 fleet/scripts/prompt_build.py "$@"
