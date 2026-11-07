#!/usr/bin/env bash
# Clock fixtures for the journal-gap block in selftest.sh.
#
# Three clocks, matching the behavioral fixtures that caught run 42315371378:
#   normal                  system clock
#   crossing-midnight       local 23:59:40 (the old gap check began ~23:59:30–23:59:50).
#                           The pre-fix sequence (sleep 61, wall-clock HH:MM, fresh today)
#                           must fail. The live selftest lines must pass.
#   starting-near-midnight  local 23:59:10 (fixture "within-30s": midnight is close, but
#                           not inside the 30s wait). The live lines must pass without
#                           crossing midnight.
#
# The live lines are taken from fleet/scripts/selftest.sh, so a revert of the fix fails
# the crossing case. Every journal-gap assertion in that block stays as selftest wrote it.
set -uo pipefail
unset CDPATH
export LC_ALL=C
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
pass=0
fail=0
ok() { echo "PASS $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*" >&2; fail=$((fail + 1)); }

LIVE="$(awk '
  index($0, "s2m=$(( 86400") == 1 { p = 1 }
  p { print }
  p && index($0, "die \"journal-gap check\"") { exit }
' "$SRC/fleet/scripts/selftest.sh")"
printf '%s\n' "$LIVE" > "$T/live.sh"
if [ -z "$LIVE" ] || ! bash -n "$T/live.sh"; then
  echo "FAIL could not extract a parseable journal-gap block from selftest.sh" >&2
  exit 1
fi
for needle in \
  's2m=' \
  'WARN atlas: activity' \
  'check-journal.sh --strict' \
  '23:59 gap test journaled' \
  'check-journal.sh "$D"' \
  'A run is every chat turn' \
  'After a context summary' \
  'Delegation carries the duty' \
  'Every chat turn is a run'
do
  if ! grep -F -q "$needle" <<<"$LIVE"; then
    echo "FAIL live journal-gap block is missing: $needle" >&2
    exit 1
  fi
done
if grep -F -q 'sleep 61' <<<"$LIVE" || grep -F -q 'date +%H:%M' <<<"$LIVE"; then
  echo "FAIL live journal-gap block still uses sleep 61 or a wall-clock journal time" >&2
  exit 1
fi
ok "live journal-gap block keeps every assertion and drops the 61s sleep"

# Scratch fleet large enough for the same check-journal + validate assertions selftest uses.
A="$T/fleet"
mkdir -p "$A"
(cd "$SRC" && tar -cf - fleet templates .github README.md LICENSE examples) | tar -x -C "$A"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
git config --global init.defaultBranch main
git config --global user.name selftest
git config --global user.email selftest@example.invalid
git config --global commit.gpgsign false
git -C "$A" init -q -b main
(cd "$A" && bash fleet/scripts/init-fleet.sh >/dev/null)
for s in atlas forge; do
  rm -rf "$A/bots/$s"
  cp -a "$A/templates/bot" "$A/bots/$s"
  rm -f "$A/bots/$s/routines/example.json"
done
V="$(tr -d '[:space:]' < "$A/fleet/VERSION")"
python3 - "$A" "$V" << 'PY'
import json, sys
A, V = sys.argv[1], sys.argv[2]
fleet = {
    "schemaVersion": 2,
    "owner": "alextest",
    "owner_name": "Alex Test",
    "templateVersion": V,
    "bots": [
        {"slug": "atlas", "name": "Atlas", "id": "fake-atlas", "role": "manager", "status": "active"},
        {"slug": "forge", "name": "Forge", "id": "fake-forge", "role": "builder", "status": "active"},
    ],
}
with open(A + "/local/fleet.json", "w") as f:
    json.dump(fleet, f, indent=2)
    f.write("\n")
for slug, name, role, agent in (
    ("atlas", "Atlas", "manager", "fake-atlas"),
    ("forge", "Forge", "builder", "fake-forge"),
):
    bot = {
        "schemaVersion": 1,
        "display_name": name,
        "slug": slug,
        "role": role,
        "agent_id": agent,
        "worktree": A,
        "owner_name": "Alex Test",
        "kit_version": V,
        "timezone": "UTC",
    }
    with open(f"{A}/bots/{slug}/bot.json", "w") as f:
        json.dump(bot, f, indent=2)
        f.write("\n")
PY
git -C "$A" add -A
git -C "$A" commit -qm "seed fleet" --no-verify
BASE="$(git -C "$A" rev-parse HEAD)"
setup_out="$(cd "$A" && fleet/scripts/validate.sh 2>&1)" && setup_rc=0 || setup_rc=$?
if [ "$setup_rc" -ne 0 ]; then
  echo "FAIL scratch fleet validate exited $setup_rc" >&2
  printf '%s\n' "$setup_out" >&2
  exit 1
fi
ok "scratch fleet validates before the journal-gap fixtures"

reset_repo() {
  git -C "$A" reset -q --hard "$BASE"
  git -C "$A" clean -qfd
}
sod_now() {
  echo $(( $(date +%s) - $(date -d "$(date +%F) 00:00" +%s) ))
}
# POSIX TZ whose local seconds-since-midnight is $1 right now.
pin() {
  local target="$1" i sod diff
  for i in 1 2 3 4 5; do
    TZ="$(python3 -c '
import time, sys
target = int(sys.argv[1])
u = time.time() % 86400
east = (target - u) % 86400
if east > 43200:
    east -= 86400
o = int(round(east))
sign = "-" if o >= 0 else "+"
a = abs(o)
print(f"XXX{sign}{a//3600}:{a%3600//60:02d}:{a%60:02d}")
' "$target")"
    export TZ
    sod="$(sod_now)"
    diff=$(( sod - target ))
    if [ "$diff" -ge -1 ] && [ "$diff" -le 2 ]; then
      return 0
    fi
  done
  echo "FAIL pin: local sod=$sod target=$target TZ=$TZ ($(date '+%F %T'))" >&2
  return 1
}

RC=0
ELAPSED=0
OUT=""
DAY0=""
DAY1=""
SOD=0
run_live() {
  reset_repo
  DAY0="$(date +%F)"
  local start
  start="$(date +%s)"
  OUT="$(
    set -euo pipefail
    exec 2>&1
    die() { echo "FAIL $*"; exit 1; }
    eval "$LIVE"
  )" && RC=0 || RC=$?
  ELAPSED=$(( $(date +%s) - start ))
  DAY1="$(date +%F)"
  SOD="$(sod_now)"
}
run_unfixed() {
  # Pre-fix sequence, assertions unchanged: record D, sleep 61, journal at the
  # wall-clock minute, re-check with a fresh today (no explicit day).
  reset_repo
  DAY0="$(date +%F)"
  local start
  start="$(date +%s)"
  OUT="$(
    set +e
    set -uo pipefail
    cd "$A" && B=bots/atlas && D="$(date +%F)" && mkdir -p $B/kb $B/journal && echo gap > $B/kb/gap-test.md && git add $B && BOT_ROLE=manager git commit -qm "atlas: gap test work" --no-verify \
      && c="$(fleet/scripts/check-journal.sh)" && grep -q "^WARN atlas: activity" <<<"$c" && ! fleet/scripts/check-journal.sh --strict >/dev/null && v="$(fleet/scripts/validate.sh 2>&1)" && grep -q "^WARN atlas: activity" <<<"$v" \
      && sleep 61 && printf -- '- %s gap test journaled\n' "$(date +%H:%M)" >> $B/journal/$D.md && git add $B && BOT_ROLE=manager git commit -qm "atlas: journal" --no-verify \
      && c="$(fleet/scripts/check-journal.sh)" && ! grep -q "^WARN atlas" <<<"$c" && grep -q "A run is every chat turn" fleet/rules/startup.md && grep -q "After a context summary" fleet/rules/startup.md && grep -q "Delegation carries the duty" fleet/rules/startup.md && grep -q "Every chat turn is a run" templates/THIN-PROMPT.tmpl
    r=$?
    printf '%s\n' "${c-}" > "$T/unfixed-second.txt"
    h0="$(git log --format=%H --grep="^atlas: gap test work" -1)"
    [ -n "$h0" ] && git reset -q --hard "$h0~1"
    exit "$r"
  )" && RC=0 || RC=$?
  ELAPSED=$(( $(date +%s) - start ))
  DAY1="$(date +%F)"
  SOD="$(sod_now)"
}

dump() {
  echo "  TZ=${TZ-<unset>} local=$(date '+%F %T') rc=$RC elapsed=${ELAPSED}s day $DAY0 -> $DAY1 sod=$SOD" >&2
  [ -n "$OUT" ] && printf '%s\n' "$OUT" | sed 's/^/  /' >&2
}

echo "== normal (TZ=system)"
unset TZ
run_live
sod_left=$(( 86400 - $(sod_now) ))
if [ "$RC" -eq 0 ] && { [ "$sod_left" -lt 120 ] || [ "$ELAPSED" -lt 45 ]; }; then
  ok "normal clock ($(date '+%F %T'), ${ELAPSED}s)"
else
  bad "normal clock: live journal-gap block exited $RC after ${ELAPSED}s"
  dump
fi

if pin $((23 * 3600 + 59 * 60 + 10)); then
  echo "== starting-near-midnight (TZ=$TZ local=$(date '+%F %T'))"
  run_live
  if [ "$RC" -eq 0 ] && [ "$DAY0" = "$DAY1" ] && [ "$SOD" -ge 86340 ] && [ "$ELAPSED" -lt 40 ]; then
    ok "starting near midnight stays on $DAY1 ($(date '+%T'), ${ELAPSED}s)"
  else
    bad "starting near midnight: rc=$RC day $DAY0->$DAY1 sod=$SOD elapsed=${ELAPSED}s"
    dump
  fi
else
  bad "starting near midnight: could not pin local 23:59:10"
fi

if pin $((23 * 3600 + 59 * 60 + 40)); then
  echo "== crossing-midnight (TZ=$TZ local=$(date '+%F %T'))"
  run_unfixed
  if [ "$RC" -ne 0 ] && [ "$ELAPSED" -ge 61 ] && [ "$DAY0" != "$DAY1" ] \
    && grep -q "^WARN atlas" "$T/unfixed-second.txt" \
    && grep -q "on $DAY1" "$T/unfixed-second.txt"; then
    ok "crossing midnight: unfixed sequence fails (${ELAPSED}s, fresh today $DAY1 warns)"
  else
    bad "crossing midnight: unfixed sequence should fail across midnight (rc=$RC elapsed=${ELAPSED}s day $DAY0->$DAY1)"
    dump
    echo "  second check:" >&2
    sed 's/^/  /' "$T/unfixed-second.txt" >&2 || true
  fi
  if pin $((23 * 3600 + 59 * 60 + 40)); then
    run_live
    if [ "$RC" -eq 0 ] && [ "$DAY0" != "$DAY1" ] && [ "$SOD" -lt 50 ] && [ "$ELAPSED" -ge 12 ] && [ "$ELAPSED" -lt 55 ]; then
      ok "crossing midnight: live block waits out midnight and passes (${ELAPSED}s, now $(date '+%T'))"
    else
      bad "crossing midnight: live block rc=$RC day $DAY0->$DAY1 sod=$SOD elapsed=${ELAPSED}s"
      dump
    fi
  else
    bad "crossing midnight: could not re-pin local 23:59:40 for the live block"
  fi
else
  bad "crossing midnight: could not pin local 23:59:40"
fi

echo
echo "journal-gap midnight: $pass passed, $fail failed"
[ "$fail" = 0 ]
