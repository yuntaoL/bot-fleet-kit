#!/usr/bin/env bash
# 0.12.0: record prompt_mode files when local/fleet.json does not set it.
# Usage: bash fleet/migrations/0.12.0.sh [--dry-run]
# Idempotent. Does not build prompts, does not mark anything deployed, and does not
# read or write a live platform profile. A fleet that already set prompt_mode is left alone.
# Compiled prompts are opt-in after this upgrade. See fleet/docs/COMPILED-PROMPTS.md.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[ -f local/fleet.json ] || { echo "0.12.0: no local/fleet.json, nothing to do"; exit 0; }
DRY=0; [ "${1:-}" = --dry-run ] && DRY=1
[ "${1:-}" = "" ] || [ "${1:-}" = --dry-run ] || { echo "usage: fleet/migrations/0.12.0.sh [--dry-run]" >&2; exit 2; }
DRY="$DRY" python3 - <<'PY'
import json, os, sys
dry = os.environ.get("DRY") == "1"
path = "local/fleet.json"
root = os.path.realpath(".")
if os.path.islink(path):
    sys.exit("0.12.0: refusing symlink local/fleet.json")
real = os.path.realpath(path)
try:
    if os.path.commonpath([root, real]) != root:
        sys.exit("0.12.0: local/fleet.json resolves outside the repo")
except ValueError:
    sys.exit("0.12.0: local/fleet.json resolves outside the repo")
fl = json.load(open(path, encoding="utf-8"))
if "prompt_mode" in fl:
    print("0.12.0: prompt_mode already set (%s), nothing to do" % fl.get("prompt_mode"))
    sys.exit(0)
if dry:
    print("would: set local/fleet.json prompt_mode to files")
    sys.exit(0)
fl["prompt_mode"] = "files"
with open(path, "w", encoding="utf-8") as f:
    json.dump(fl, f, indent=2, ensure_ascii=False)
    f.write("\n")
print("0.12.0: set prompt_mode files (no prompts built, nothing deployed)")
PY
