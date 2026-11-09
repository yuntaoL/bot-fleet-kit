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
cleanup() {
  [ -n "${LIVE:-}" ] && rm -rf "$LIVE"
  [ -n "${R1:-}" ] && rm -rf "$R1"
  [ -n "${CI_SCRIPT:-}" ] && rm -f "$CI_SCRIPT"
}
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
    errs.append("workflow does not name the classifier")
if "CLASSIFY_BASE_SHA" not in body or "CLASSIFY_HEAD_SHA" not in body:
    errs.append("workflow does not take base and head SHAs from the environment")
if 'git cat-file blob "$BASE:fleet/scripts/classify-ci-paths.sh"' not in body:
    errs.append("skip decision does not read the base classifier blob")
if 'bash "$blob"' not in body:
    errs.append("skip decision does not execute the base blob")
if "100644" not in body or "100755" not in body:
    errs.append("base blob mode check missing")
if "classifier or workflow changed" not in body:
    errs.append("changed classifier or workflow is not fail-closed")
for trusted in (
    "fleet/scripts/classify-ci-paths.sh",
    "fleet/scripts/test-classify-ci-paths.sh",
    ".github/workflows/validate.yml",
):
    if trusted not in body:
        errs.append("trusted path not guarded: %s" % trusted)
if 'MODE="$(fleet/scripts/classify-ci-paths.sh' in body or "bash fleet/scripts/classify-ci-paths.sh" in body:
    errs.append("workflow executes the worktree classifier")
if "state.json" not in body:
    errs.append("workflow no longer says state.json is not inert")
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

echo "== adversarial stdin =="
stdin_out="$(python3 - "$CLS" << 'PY'
import subprocess, sys
cls = sys.argv[1]
cases = [
    ("stdin-nul", b"M\tbots/dr-eggbot/journal/2026-11-06.md\0M\tfleet/VERSION\n", "full"),
    ("stdin-nul-in-path", b"M\tbots/dr-eggbot/journal/2026-11-06.md\0\n", "full"),
    ("stdin-tab", b"M\tbots/dr-eggbot/journal/2026-11-06.md\tfleet/VERSION\n", "full"),
    ("stdin-tab-quoted", b'M\t"bots/dr-eggbot/kb/foo\\tbar.md"\n', "full"),
    ("stdin-newline-quoted", b'M\t"bots/dr-eggbot/kb/foo\\nbar.md"\n', "full"),
    ("stdin-u2028", "M\tbots/dr-eggbot/journal/2026-11-06.md\u2028# M\tfleet/VERSION\n".encode(), "full"),
    ("stdin-u2029", "M\tbots/dr-eggbot/journal/2026-11-06.md\u2029M\tfleet/VERSION\n".encode(), "full"),
    ("stdin-unicode-slug", "M\tbots/n\u00f6nascii/journal/2026-11-06.md\n".encode(), "full"),
    ("stdin-unicode-kb", "M\tbots/dr-eggbot/kb/caf\u00e9.md\n".encode(), "full"),
    ("stdin-comment-hide", b"M\tbots/dr-eggbot/journal/2026-11-06.md\n# M\tfleet/VERSION\n", "full"),
]
failed = 0
for name, data, expect in cases:
    p = subprocess.run([cls, "--stdin"], input=data, capture_output=True)
    out = p.stdout.decode().strip()
    if p.returncode == 0 and out == expect:
        print("PASS %s -> %s" % (name, out))
    else:
        err = p.stderr.decode()[:180]
        print("FAIL %s: got %r want %s exit %s (%s)" % (name, out, expect, p.returncode, err))
        failed = 1
sys.exit(failed)
PY
)"
stdin_rc=$?
printf '%s\n' "$stdin_out"
if [ "$stdin_rc" = 0 ]; then
  pass=$((pass + $(printf '%s\n' "$stdin_out" | grep -c '^PASS ')))
else
  fail=$((fail + $(printf '%s\n' "$stdin_out" | grep -c '^FAIL ')))
  [ "$fail" = 0 ] && fail=1
fi

echo "== base-blob skip decision =="
CI_SCRIPT="$(mktemp)"
if ! python3 - "$WF" "$CI_SCRIPT" << 'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().splitlines()
start = next((i for i, l in enumerate(lines) if l.strip() in ("name: Classify changed paths", "- name: Classify changed paths")), None)
if start is None:
    sys.exit("classify step not found")
run_at = None
for j in range(start, min(start + 40, len(lines))):
    if lines[j].strip() == "run: |":
        run_at = j
        break
    if j > start and lines[j].startswith("      - "):
        break
if run_at is None:
    sys.exit("classify run block not found")
body = []
for l in lines[run_at + 1:]:
    if l.startswith("      - ") or (l.strip() and not l.startswith(" ")):
        break
    body.append(l)
indents = [len(l) - len(l.lstrip(" ")) for l in body if l.strip()]
if not indents:
    sys.exit("classify run block empty")
n = min(indents)
text = "\n".join(l[n:] if l.startswith(" " * n) else l for l in body) + "\n"
needle = 'git cat-file blob "$BASE:fleet/scripts/classify-ci-paths.sh"'
if needle not in text or 'bash "$blob"' not in text:
    sys.exit("extracted script is not the base-blob decision")
open(dst, "w", encoding="utf-8").write(text)
PY
then
  echo "FAIL extract-ci-script"
  fail=$((fail+1))
else
  echo "PASS extract-ci-script"
  pass=$((pass+1))
fi

decide() {
  local name="$1" expect="$2" base="$3" head="$4" repo="$5" why="${6:-}"
  local out_file stdout_file rc mode
  out_file="$(mktemp)"
  stdout_file="$(mktemp)"
  (
    cd "$repo" || exit 2
    CLASSIFY_BASE_SHA="$base" CLASSIFY_HEAD_SHA="$head" GITHUB_OUTPUT="$out_file" bash "$CI_SCRIPT"
  ) >"$stdout_file" 2>&1
  rc=$?
  mode="$(sed -n 's/^mode=//p' "$out_file" | tail -1)"
  if [ "$rc" = 0 ] && [ "$mode" = "$expect" ] && { [ -z "$why" ] || grep -q "$why" "$stdout_file"; }; then
    echo "PASS $name -> $mode"
    pass=$((pass+1))
  else
    echo "FAIL $name: mode='${mode:-}' want '$expect' exit $rc"
    sed 's/^/  /' "$stdout_file"
    fail=$((fail+1))
  fi
  rm -f "$out_file" "$stdout_file"
}

if [ -s "$CI_SCRIPT" ]; then
  R1="$(mktemp -d)"
  REPO="$R1/repo"
  mkdir -p "$REPO/fleet/scripts" "$REPO/.github/workflows" "$REPO/bots/dr-eggbot/journal"
  cp "$CLS" "$REPO/fleet/scripts/classify-ci-paths.sh"
  cp "$ROOT/test-classify-ci-paths.sh" "$REPO/fleet/scripts/test-classify-ci-paths.sh"
  cp "$WF" "$REPO/.github/workflows/validate.yml"
  printf 'day one\n' > "$REPO/bots/dr-eggbot/journal/2026-11-06.md"
  printf 'readme\n' > "$REPO/README.md"
  printf '{}\n' > "$REPO/bots/dr-eggbot/state.json"
  gg() { git -C "$REPO" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false "$@"; }
  gg init -q -b main
  gg add -A && gg commit -qm base
  BASE0="$(gg rev-parse HEAD)"
  bits="$(gg ls-tree "$BASE0" fleet/scripts/classify-ci-paths.sh | awk '{print $1}')"
  if [ "$bits" = "100755" ] || [ "$bits" = "100644" ]; then
    echo "PASS base-classifier-mode -> $bits"
    pass=$((pass+1))
  else
    echo "FAIL base-classifier-mode: $bits"
    fail=$((fail+1))
  fi

  printf 'day two\n' > "$REPO/bots/dr-eggbot/journal/2026-11-06.md"
  gg add -A && gg commit -qm journal
  HEAD_JOURNAL="$(gg rev-parse HEAD)"
  decide ci-journal-only docs-only "$BASE0" "$HEAD_JOURNAL" "$REPO" "base classifier reported docs-only"

  # A dirty worktree classifier must not be the skip decision. This copy
  # prints full for every diff; the committed blob still says docs-only.
  cat > "$REPO/fleet/scripts/classify-ci-paths.sh" << 'EOF'
#!/bin/sh
printf '%s\n' full
EOF
  dirty="$(cd "$REPO" && bash fleet/scripts/classify-ci-paths.sh --base "$BASE0" --head "$HEAD_JOURNAL")"
  if [ "$dirty" = "full" ]; then
    echo "PASS dirty-worktree-would-say-full -> $dirty"
    pass=$((pass+1))
  else
    echo "FAIL dirty-worktree-would-say-full: got '$dirty'"
    fail=$((fail+1))
  fi
  decide ci-dirty-worktree-ignored docs-only "$BASE0" "$HEAD_JOURNAL" "$REPO" "base classifier reported docs-only"
  gg checkout -q -- fleet/scripts/classify-ci-paths.sh

  printf '{ "changed": true }\n' > "$REPO/bots/dr-eggbot/state.json"
  gg add -A && gg commit -qm state
  HEAD_STATE="$(gg rev-parse HEAD)"
  decide ci-state-json-not-skippable full "$HEAD_JOURNAL" "$HEAD_STATE" "$REPO" "base classifier did not report docs-only"

  printf '\n# not a behavior change\n' >> "$REPO/fleet/scripts/test-classify-ci-paths.sh"
  gg add -A && gg commit -qm tests
  HEAD_TESTS="$(gg rev-parse HEAD)"
  decide ci-tests-changed full "$HEAD_STATE" "$HEAD_TESTS" "$REPO" "classifier or workflow changed"

  printf '\n# workflow touched\n' >> "$REPO/.github/workflows/validate.yml"
  gg add -A && gg commit -qm workflow
  HEAD_WF="$(gg rev-parse HEAD)"
  decide ci-workflow-changed full "$HEAD_TESTS" "$HEAD_WF" "$REPO" "classifier or workflow changed"

  printf 'hacked\n' >> "$REPO/README.md"
  cat > "$REPO/fleet/scripts/classify-ci-paths.sh" << 'EOF'
#!/bin/sh
printf '%s\n' docs-only
EOF
  gg add -A && gg commit -qm weaken
  HEAD_WEAK="$(gg rev-parse HEAD)"
  head_out="$(bash "$REPO/fleet/scripts/classify-ci-paths.sh" --base "$BASE0" --head "$HEAD_WEAK" 2>/dev/null)"
  base_blob="$(mktemp)"
  base_err="$(mktemp)"
  gg cat-file blob "$BASE0:fleet/scripts/classify-ci-paths.sh" > "$base_blob"
  base_out="$(cd "$REPO" && bash "$base_blob" --base "$BASE0" --head "$HEAD_WEAK" 2>"$base_err")"
  rm -f "$base_blob" "$base_err"
  if [ "$head_out" = "docs-only" ]; then
    echo "PASS weakened-head-says-docs-only -> $head_out"
    pass=$((pass+1))
  else
    echo "FAIL weakened-head-says-docs-only: got '$head_out'"
    fail=$((fail+1))
  fi
  if [ "$base_out" = "full" ]; then
    echo "PASS base-blob-says-full -> $base_out"
    pass=$((pass+1))
  else
    echo "FAIL base-blob-says-full: got '$base_out'"
    fail=$((fail+1))
  fi
  decide ci-weakened-head-cannot-flip full "$BASE0" "$HEAD_WEAK" "$REPO" "classifier or workflow changed"

  decide ci-zero-base full "0000000000000000000000000000000000000000" "$HEAD_JOURNAL" "$REPO" "missing or zero SHA"
  decide ci-unknown-base full "0123456789abcdef0123456789abcdef01234567" "$HEAD_JOURNAL" "$REPO" "fail-closed"

  MISS="$R1/missing"
  mkdir -p "$MISS/bots/dr-eggbot/journal"
  printf 'day one\n' > "$MISS/bots/dr-eggbot/journal/2026-11-06.md"
  git -C "$MISS" init -q -b main
  git -C "$MISS" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false add -A
  git -C "$MISS" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false commit -qm base
  miss_base="$(git -C "$MISS" rev-parse HEAD)"
  printf 'day two\n' > "$MISS/bots/dr-eggbot/journal/2026-11-06.md"
  git -C "$MISS" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false add -A
  git -C "$MISS" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false commit -qm journal
  miss_head="$(git -C "$MISS" rev-parse HEAD)"
  decide ci-missing-base-blob full "$miss_base" "$miss_head" "$MISS" "not a regular file"

  LINK="$R1/link"
  mkdir -p "$LINK/fleet/scripts" "$LINK/.github/workflows" "$LINK/bots/dr-eggbot/journal"
  cat > "$LINK/fleet/scripts/real.sh" << 'EOF'
#!/bin/sh
printf '%s\n' docs-only
EOF
  ln -s real.sh "$LINK/fleet/scripts/classify-ci-paths.sh"
  cp "$ROOT/test-classify-ci-paths.sh" "$LINK/fleet/scripts/test-classify-ci-paths.sh"
  cp "$WF" "$LINK/.github/workflows/validate.yml"
  printf 'day one\n' > "$LINK/bots/dr-eggbot/journal/2026-11-06.md"
  git -C "$LINK" init -q -b main
  git -C "$LINK" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false add -A
  git -C "$LINK" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false commit -qm base
  link_base="$(git -C "$LINK" rev-parse HEAD)"
  link_bits="$(git -C "$LINK" ls-tree "$link_base" fleet/scripts/classify-ci-paths.sh | awk '{print $1}')"
  printf 'day two\n' > "$LINK/bots/dr-eggbot/journal/2026-11-06.md"
  git -C "$LINK" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false add -A
  git -C "$LINK" -c user.email=test@example.invalid -c user.name=test -c commit.gpgsign=false commit -qm journal
  link_head="$(git -C "$LINK" rev-parse HEAD)"
  if [ "$link_bits" = "120000" ]; then
    echo "PASS symlink-classifier-mode -> $link_bits"
    pass=$((pass+1))
  else
    echo "FAIL symlink-classifier-mode: $link_bits"
    fail=$((fail+1))
  fi
  decide ci-symlink-classifier-full full "$link_base" "$link_head" "$LINK" "not a regular file"
fi

echo
echo "classify-ci-paths tests: $pass passed, $fail failed ($fix_count fixture files)"
[ "$fail" = 0 ]
