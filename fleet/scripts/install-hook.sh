#!/usr/bin/env bash
# Install a pre-commit hook (shared by all worktrees) that runs, from the CURRENT worktree:
#   1. the confidential scanner (instance local/shared/scripts/confidential-scan.sh if present, else fleet/scripts/confidential-scan.sh)
#   2. check-boundary.sh
# Idempotent; rerunning (e.g. from upgrade.sh) keeps the scanner.
set -euo pipefail
hooks="$(git rev-parse --git-common-dir)/hooks"; mkdir -p "$hooks"; rm -f "$hooks/pre-commit"
cat > "$hooks/pre-commit" <<'H'
#!/usr/bin/env bash
top="$(git rev-parse --show-toplevel)"
for s in "$top/local/shared/scripts/confidential-scan.sh" "$top/fleet/scripts/confidential-scan.sh"; do
  [ -f "$s" ] && { bash "$s" --staged || exit 1; break; }
done
exec bash "$top/fleet/scripts/check-boundary.sh"
H
chmod +x "$hooks/pre-commit"
