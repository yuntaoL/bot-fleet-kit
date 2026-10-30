#!/usr/bin/env bash
# Usage: fleet/scripts/bootstrap.sh [template-repo-url]   First-time setup of a fleet clone (docs/ADOPTION.md). Idempotent.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config user.email >/dev/null || { echo "bootstrap: set git identity first: git config user.name '...' && git config user.email '...'" >&2; exit 1; }
chmod +x fleet/scripts/*.sh
fleet/scripts/install-hook.sh
git config branch.main.remote origin; git config --replace-all branch.main.merge refs/heads/main
if [ -n "${1:-}" ] && ! git remote get-url upstream >/dev/null 2>&1; then git remote add upstream "$1"; fi
git config remote.upstream.tagOpt --no-tags 2>/dev/null || true
python3 -c "import jsonschema" 2>/dev/null || pip install -q jsonschema 2>/dev/null || pip install -q --user --break-system-packages jsonschema 2>/dev/null || echo "bootstrap: install jsonschema for validate.sh"
case "$(basename "$(git remote get-url origin 2>/dev/null)" .git)" in bot-fleet-kit|bot-fleet-template) ;; *)
  fleet/scripts/init-fleet.sh
  git add -A README.md local bots
  git diff --cached --quiet || BOT_ROLE=manager git commit -qm "manager: bootstrap fleet files"
  ;; esac
echo "bootstrap: done. Next: add bots to local/fleet.json, then fleet/scripts/worktree.sh --all"
