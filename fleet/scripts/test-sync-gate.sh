#!/usr/bin/env bash
# Pre-push gate in sync.sh. Scratch repos only. Slugs ada and bee are fixtures.
# validate.sh here is a stub so the test can choose which failure the gate sees.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL $*" >&2; [ -n "${CAP:-}" ] && printf '%s\n' "$CAP" >&2; exit 1; }
pass() { echo "PASS $*"; }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="$T/gitconfig" LC_ALL=C PYTHONDONTWRITEBYTECODE=1
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.invalid
git config --global commit.gpgsign false

REPO="$T/repo"
REMOTE="$T/remote.git"
mkdir -p "$REPO/fleet/scripts" "$REPO/fleet/schema" "$REPO/bots/ada" "$REPO/bots/bee" "$REPO/local"
cp "$SRC/fleet/scripts/sync.sh" "$REPO/fleet/scripts/sync.sh"
cp "$SRC/fleet/scripts/owners.py" "$REPO/fleet/scripts/owners.py"
cp "$SRC/fleet/scripts/schema_check.py" "$REPO/fleet/scripts/schema_check.py"
cp "$SRC/fleet/scripts/check-staged-config.sh" "$REPO/fleet/scripts/check-staged-config.sh"
cp "$SRC/fleet/OWNERS.json" "$REPO/fleet/OWNERS.json"
cp "$SRC/fleet/schema/"*.schema.json "$REPO/fleet/schema/"
chmod +x "$REPO/fleet/scripts/sync.sh" "$REPO/fleet/scripts/check-staged-config.sh"
cat > "$REPO/fleet/scripts/validate.sh" << 'EOF'
#!/usr/bin/env bash
mode="${GATE_MODE:-ok}"
case "$mode" in
  ok) echo "validate: OK"; exit 0 ;;
  own) echo "FAIL bots/ada/notes.md: broken"; echo "validate: FAILED"; exit 1 ;;
  other) echo "FAIL bots/bee/state.json: broken"; echo "validate: FAILED"; exit 1 ;;
  global) echo "FAIL fleet.json needs exactly one manager"; echo "validate: FAILED"; exit 1 ;;
  mixed) echo "FAIL bots/bee/state.json: broken"; echo "FAIL bots/ada/notes.md: also broken"; echo "validate: FAILED"; exit 1 ;;
  slug) echo "FAIL bee: dead link in the action index"; echo "validate: FAILED"; exit 1 ;;
  hint) echo "FAIL missing bots/bee/bot.json (fleet/scripts/bot-json.sh bee)"; echo "validate: FAILED"; exit 1 ;;
  missing) echo "FAIL missing bots/bee"; echo "validate: FAILED"; exit 1 ;;
  *) echo "FAIL validate stub: unknown mode $mode"; exit 1 ;;
esac
EOF
chmod +x "$REPO/fleet/scripts/validate.sh"
printf '# note\n' > "$REPO/bots/ada/notes.md"
printf '{}\n' > "$REPO/bots/bee/state.json"
printf '%s\n' '{"schemaVersion":2,"owner":"example","owner_name":"Example","templateVersion":"0.12.0","bots":[]}' > "$REPO/local/fleet.json"

git init -q -b main "$REPO"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base" --no-verify
git init -q --bare -b main "$REMOTE"
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" push -q origin HEAD:main

remote_sha() { git -C "$REMOTE" rev-parse HEAD; }
head_sha() { git -C "$REPO" rev-parse HEAD; }

sync_run() {
  local mode="$1" msg="$2" out
  shift 2
  out="$(mktemp)"
  set +e
  (cd "$REPO" && env GATE_MODE="$mode" BOT_NAME=ada BOT_ROLE=worker "$@" fleet/scripts/sync.sh "$msg" bots/ada/notes.md) >"$out" 2>&1
  CAP_RC=$?
  set -e
  CAP="$(cat "$out")"
  rm -f "$out"
}

before="$(remote_sha)"
printf '\nline ok\n' >> "$REPO/bots/ada/notes.md"
sync_run ok "note ok"
[ "$CAP_RC" = 0 ] || fail "clean validate did not push
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "clean validate missing push line
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "clean validate did not move origin"
pass "validate ok still commits and pushes"

before="$(remote_sha)"
printf '\nline own\n' >> "$REPO/bots/ada/notes.md"
sync_run own "note own"
[ "$CAP_RC" != 0 ] || fail "own-path failure pushed
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: refusing commit and push; validate.sh failed" || fail "own-path missing refusal
$CAP"
printf '%s\n' "$CAP" | grep -q "bots/ada/notes.md" || fail "own-path did not name the file
$CAP"
printf '%s\n' "$CAP" | grep -q "owns or staged" || fail "own-path missing owned-path message
$CAP"
[ "$(remote_sha)" = "$before" ] || fail "own-path moved origin"
[ "$(head_sha)" = "$before" ] || fail "own-path created a commit"
pass "failure on this bot's path blocks the commit and the push"

before="$(remote_sha)"
printf '\nline other\n' >> "$REPO/bots/ada/notes.md"
sync_run other "note other"
[ "$CAP_RC" = 0 ] || fail "other-bot failure blocked the push
$CAP"
printf '%s\n' "$CAP" | grep -q "another bot's files" || fail "other-bot missing warning
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "other-bot did not push
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "other-bot did not move origin"
pass "failure only in another bot's file warns and still pushes"

before="$(remote_sha)"
printf '\nline global\n' >> "$REPO/bots/ada/notes.md"
sync_run global "note global"
[ "$CAP_RC" != 0 ] || fail "unattributed failure pushed
$CAP"
printf '%s\n' "$CAP" | grep -q "could not be attributed" || fail "unattributed missing explanation
$CAP"
printf '%s\n' "$CAP" | grep -q "SYNC_SKIP_GATE=1" || fail "unattributed missing escape hatch
$CAP"
[ "$(remote_sha)" = "$before" ] || fail "unattributed moved origin"
pass "unattributed failure blocks and names SYNC_SKIP_GATE=1"

before="$(remote_sha)"
printf '\nline mixed\n' >> "$REPO/bots/ada/notes.md"
sync_run mixed "note mixed"
[ "$CAP_RC" != 0 ] || fail "mixed failure pushed
$CAP"
printf '%s\n' "$CAP" | grep -q "owns or staged" || fail "mixed failure was not treated as owned
$CAP"
[ "$(remote_sha)" = "$before" ] || fail "mixed moved origin"
pass "a failure that also names this bot's path blocks"

before="$(remote_sha)"
printf '\nline slug\n' >> "$REPO/bots/ada/notes.md"
sync_run slug "note slug"
[ "$CAP_RC" = 0 ] || fail "slug-only other-bot failure blocked
$CAP"
printf '%s\n' "$CAP" | grep -q "another bot's files" || fail "slug-only missing warning
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "slug-only did not push"
pass "FAIL <other-slug>: with no path warns and still pushes"

before="$(remote_sha)"
printf '\nline hint\n' >> "$REPO/bots/ada/notes.md"
sync_run hint "note hint"
[ "$CAP_RC" = 0 ] || fail "hint path blocked the push
$CAP"
printf '%s\n' "$CAP" | grep -q "another bot's files" || fail "hint path missing warning
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "hint path did not push
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "hint path did not move origin"
pass "a parenthetical kit path does not hide another bot's file"

before="$(remote_sha)"
printf '\nline missing\n' >> "$REPO/bots/ada/notes.md"
sync_run missing "note missing"
[ "$CAP_RC" = 0 ] || fail "missing other-bot folder blocked the push
$CAP"
printf '%s\n' "$CAP" | grep -q "another bot's files" || fail "missing folder was not another bot
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "missing folder did not push"
pass "FAIL missing bots/<other> warns and still pushes"

before="$(remote_sha)"
printf '\nline skip\n' >> "$REPO/bots/ada/notes.md"
sync_run own "note skip" SYNC_SKIP_GATE=1
[ "$CAP_RC" = 0 ] || fail "SYNC_SKIP_GATE=1 did not push
$CAP"
printf '%s\n' "$CAP" | grep -q "SYNC_SKIP_GATE=1 is set" || fail "escape hatch was not loud
$CAP"
printf '%s\n' "$CAP" | grep -q "NOT checked by validate.sh" || fail "escape hatch did not say the push was unchecked
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "escape hatch did not push
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "escape hatch did not move origin"
pass "SYNC_SKIP_GATE=1 warns and pushes despite an owned failure"

# A committed deletion of validate.sh is how a fixture tree lacks the gate.
# The next sync must keep the old push behavior and must not invent a failure.
git -C "$REPO" rm -q fleet/scripts/validate.sh
git -C "$REPO" commit -qm "drop validate stub" --no-verify
git -C "$REPO" push -q origin HEAD:main
before="$(remote_sha)"
printf '\nline novalidate\n' >> "$REPO/bots/ada/notes.md"
sync_run ok "note novalidate"
[ "$CAP_RC" = 0 ] || fail "missing validate.sh blocked sync
$CAP"
printf '%s\n' "$CAP" | grep -q "validate.sh failed" && fail "missing validate.sh ran a gate
$CAP" || true
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "missing validate.sh did not push
$CAP"
[ "$(remote_sha)" != "$before" ] || fail "missing validate.sh did not move origin"
pass "a tree without validate.sh keeps the previous sync push behavior"

echo "sync-gate tests: PASS"
