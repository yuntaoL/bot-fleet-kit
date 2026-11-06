#!/usr/bin/env bash
# Behavioral tests for classify-ci-paths.sh.
# Each fixtures/*.name-status file has a "# expect: docs-only|full" header.
# Also covers CLI failures, live git ranges, and the workflow contract
# (job name validate, no path filters, only selftest is conditional).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CLS="$ROOT/classify-ci-paths.sh"
FIX="$ROOT/classify-ci-paths-fixtures"
fail=0
pass=0
LIVE=""
cleanup() { [ -n "${LIVE:-}" ] && rm -rf "$LIVE"; }
trap cleanup EXIT

run_cmd() {
  local name="$1" expect="$2"
  shift 2
  local reason_file out rc reason
  reason_file="$(mktemp)"
  out="$("$@" 2>"$reason_file")"
  rc=$?
  reason="$(cat "$reason_file" 2>/dev/null || true)"
  rm -f "$reason_file"
  if [ "$rc" != 0 ]; then
    echo "FAIL $name: exit $rc (expected 0); stdout='$out' stderr='$reason'"
    fail=$((fail+1))
    return
  fi
  if [ "$out" != "$expect" ]; then
    echo "FAIL $name: got '$out' want '$expect' ($reason)"
    fail=$((fail+1))
    return
  fi
  echo "PASS $name -> $out"
  pass=$((pass+1))
}

run() { run_cmd "$1" "$2" "$CLS" "${@:3}"; }

echo "== fixture files =="
shopt -s nullglob
fix_count=0
for f in "$FIX"/*.name-status; do
  fix_count=$((fix_count+1))
  name="$(basename "$f" .name-status)"
  expect="$(sed -n 's/^# expect: //p' "$f" | head -1)"
  if [ -z "$expect" ]; then
    echo "FAIL $name: missing '# expect:' header"
    fail=$((fail+1))
    continue
  fi
  run "$name" "$expect" --name-status-file "$f"
done
if [ "$fix_count" -eq 0 ]; then
  echo "FAIL no fixture files in $FIX"
  fail=$((fail+1))
fi

echo "== extra CLI cases =="
run zero-base full --base 0000000000000000000000000000000000000000 --head abcdef
run zero-head full --base abcdef --head 0000000000000000000000000000000000000000
run no-args full
run help-flag full --help
run base-only full --base abcdef0
run bad-sha full --base not-a-sha --head abcdef0
run missing-file full --name-status-file "$ROOT/no-such-file.name-status"
run unknown-flag full --nope

reason_file="$(mktemp)"
out="$(printf '' | "$CLS" --stdin --base abcdef0 --head abcdef1 2>"$reason_file")"
rc=$?
reason="$(cat "$reason_file" 2>/dev/null || true)"; rm -f "$reason_file"
if [ "$rc" = 0 ] && [ "$out" = "full" ]; then echo "PASS stdin-and-range -> $out"; pass=$((pass+1)); else echo "FAIL stdin-and-range: got '$out' want 'full' ($reason) exit $rc"; fail=$((fail+1)); fi

out="$(printf 'A\tbots/dr-eggbot/journal/2026-11-06.md\n' | "$CLS" --stdin 2>"$reason_file")"
rc=$?
reason="$(cat "$reason_file" 2>/dev/null || true)"; rm -f "$reason_file"
if [ "$rc" = 0 ] && [ "$out" = "docs-only" ]; then echo "PASS stdin-journal -> $out"; pass=$((pass+1)); else echo "FAIL stdin-journal: got '$out' want 'docs-only' ($reason) exit $rc"; fail=$((fail+1)); fi
out="$(printf '' | "$CLS" --stdin 2>"$reason_file")"
rc=$?
reason="$(cat "$reason_file" 2>/dev/null || true)"; rm -f "$reason_file"
if [ "$rc" = 0 ] && [ "$out" = "full" ]; then echo "PASS stdin-empty -> $out"; pass=$((pass+1)); else echo "FAIL stdin-empty: got '$out' want 'full' ($reason) exit $rc"; fail=$((fail+1)); fi

echo "== workflow contract =="
WF="$ROOT/../../.github/workflows/validate.yml"
reason_file="$(mktemp)"
if python3 - "$WF" >"$reason_file" << 'PY'
import sys
path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()
body = "\n".join(lines)
errs = []
if "paths-ignore" in body:
    errs.append("paths-ignore is present")
if not any(l.strip() == "name: validate" for l in lines):
    errs.append("workflow or job display name is not validate")
if "  validate:" not in body:
    errs.append("job id validate missing")
if "on: [push, pull_request]" not in body:
    errs.append("triggers changed")
steps = []
cur = None
for l in lines:
    if l.startswith("      - "):
        if cur:
            steps.append(cur)
        rest = l.strip()[2:].strip()
        cur = {"if": None, "run": None}
        if rest.startswith("if:"):
            cur["if"] = rest
        if rest.startswith("run:"):
            cur["run"] = rest.split("run:", 1)[1].strip()
    elif cur is not None:
        s = l.strip()
        if s.startswith("if:"):
            cur["if"] = s
        if s.startswith("run:"):
            cur["run"] = s.split("run:", 1)[1].strip()
if cur:
    steps.append(cur)
wanted = {
    "fleet/scripts/validate.sh": None,
    "fleet/scripts/audit.sh": None,
    "fleet/scripts/test-classify-ci-paths.sh": None,
    "fleet/scripts/selftest.sh": "conditional",
}
found = {st["run"]: st["if"] for st in steps if st["run"] in wanted}
for script, cond in wanted.items():
    if script not in found:
        errs.append("missing step %s" % script)
        continue
    iff = found[script]
    if cond is None and iff is not None:
        errs.append("%s is conditional (%s)" % (script, iff))
    if cond == "conditional":
        if not iff or "docs-only" not in iff or "!=" not in iff:
            errs.append("selftest if is not fail-closed: %s" % iff)
for st in steps:
    if st["if"] and "docs-only" in st["if"] and st["run"] != "fleet/scripts/selftest.sh":
        errs.append("docs-only condition on %s" % st["run"])
if "classify-ci-paths.sh" not in body:
    errs.append("workflow does not run the classifier")
if any(l.strip().startswith("paths:") for l in lines):
    errs.append("paths key present")
if errs:
    print("\n".join(errs))
    sys.exit(1)
print("ok")
PY
then
  echo "PASS workflow-contract -> full-selftest-only-when-not-docs-only"
  pass=$((pass+1))
else
  echo "FAIL workflow-contract: $(cat "$reason_file")"
  fail=$((fail+1))
fi
rm -f "$reason_file"

echo "== live git ranges =="
LIVE="$(mktemp -d)"
cp "$CLS" "$LIVE/classify.sh"
chmod +x "$LIVE/classify.sh"
git -C "$LIVE" init -q -b main
mkdir -p "$LIVE/bots/dr-eggbot/journal" "$LIVE/bots/dr-eggbot/kb/audits" "$LIVE/fleet/scripts"
printf 'day one\n' > "$LIVE/bots/dr-eggbot/journal/2026-11-06.md"
printf -- '---\ntype: index\n---\n' > "$LIVE/bots/dr-eggbot/kb/INDEX.md"
printf 'secret\n' > "$LIVE/bots/dr-eggbot/secrets.md"
printf '#!/bin/sh\ntrue\n' > "$LIVE/fleet/scripts/validate.sh"
g() { git -C "$LIVE" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false "$@"; }
g add -A && g commit -qm init
prev="$(git -C "$LIVE" rev-parse HEAD)"

commit_range() {
  local name="$1" expect="$2"
  if ! g add -A || ! g commit -qm "$name"; then
    echo "FAIL $name: commit failed"
    fail=$((fail+1))
    return
  fi
  local head
  head="$(git -C "$LIVE" rev-parse HEAD)"
  local reason_file out rc reason
  reason_file="$(mktemp)"
  out="$(cd "$LIVE" && ./classify.sh --base "$prev" --head "$head" 2>"$reason_file")"
  rc=$?
  reason="$(cat "$reason_file" 2>/dev/null || true)"
  rm -f "$reason_file"
  if [ "$rc" = 0 ] && [ "$out" = "$expect" ]; then
    echo "PASS $name -> $out"
    pass=$((pass+1))
  else
    echo "FAIL $name: got '$out' want '$expect' ($reason) exit $rc"
    echo "  git diff:"
    git -C "$LIVE" -c color.ui=false diff --no-ext-diff --no-textconv --name-status --find-renames --find-copies "$prev" "$head" -- | sed 's/^/  /'
    fail=$((fail+1))
  fi
  prev="$head"
}

printf 'day two\n' > "$LIVE/bots/dr-eggbot/journal/2026-11-06.md"
commit_range live-journal-modify docs-only
printf -- '---\ntype: index\n---\nmore\n' > "$LIVE/bots/dr-eggbot/kb/INDEX.md"
commit_range live-kb-modify docs-only
printf -- '---\ntype: note\n---\n' > "$LIVE/bots/dr-eggbot/kb/audits/note.md"
commit_range live-kb-add docs-only
printf 'new day\n' > "$LIVE/bots/dr-eggbot/journal/2026-11-07.md"
commit_range live-journal-add docs-only
g mv bots/dr-eggbot/journal/2026-11-07.md bots/dr-eggbot/journal/2026-11-08.md
commit_range live-rename-journal docs-only
g rm -q bots/dr-eggbot/journal/2026-11-08.md
commit_range live-delete-journal full
printf 'secret changed\n' > "$LIVE/bots/dr-eggbot/secrets.md"
commit_range live-secrets full
printf '#!/bin/sh\nfalse\n' > "$LIVE/fleet/scripts/validate.sh"
commit_range live-script full

reason_file="$(mktemp)"
out="$(cd "$LIVE" && ./classify.sh --base "$prev" --head "$prev" 2>"$reason_file")"
rc=$?
reason="$(cat "$reason_file" 2>/dev/null || true)"; rm -f "$reason_file"
if [ "$rc" = 0 ] && [ "$out" = "full" ]; then echo "PASS live-empty-range -> $out"; pass=$((pass+1)); else echo "FAIL live-empty-range: got '$out' want 'full' ($reason) exit $rc"; fail=$((fail+1)); fi

out="$(cd "$LIVE" && ./classify.sh --base "$prev" --head 0123456789abcdef0123456789abcdef01234567 2>"$reason_file")"
rc=$?
reason="$(cat "$reason_file" 2>/dev/null || true)"; rm -f "$reason_file"
if [ "$rc" = 0 ] && [ "$out" = "full" ]; then echo "PASS live-bad-sha -> $out"; pass=$((pass+1)); else echo "FAIL live-bad-sha: got '$out' want 'full' ($reason) exit $rc"; fail=$((fail+1)); fi

# Copy detection ignores tiny files. Grow the journal, then copy those bytes to a
# new day while rewriting the source. --find-copies records status C, which must
# not be treated as an add of an allowlisted path.
python3 -c 'print("journal line\n"*20, end="")' > "$LIVE/bots/dr-eggbot/journal/2026-11-06.md"
commit_range live-journal-long docs-only
cp "$LIVE/bots/dr-eggbot/journal/2026-11-06.md" "$LIVE/bots/dr-eggbot/journal/2026-11-09.md"
printf 'rewritten journal that does not resemble the old one at all, extra words here\n' > "$LIVE/bots/dr-eggbot/journal/2026-11-06.md"
commit_range live-copy-journal full

echo
echo "classify-ci-paths tests: $pass passed, $fail failed ($fix_count fixture files)"
[ "$fail" = 0 ]
