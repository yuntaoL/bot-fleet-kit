#!/usr/bin/env bash
# Install a pre-commit hook that runs the CURRENT worktree's check-boundary.sh (hooks are shared by all worktrees). Idempotent.
set -euo pipefail
hooks="$(git rev-parse --git-common-dir)/hooks"; mkdir -p "$hooks"; rm -f "$hooks/pre-commit"
cat > "$hooks/pre-commit" <<'H'
#!/usr/bin/env bash
exec bash "$(git rev-parse --show-toplevel)/template/scripts/check-boundary.sh"
H
chmod +x "$hooks/pre-commit"
