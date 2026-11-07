#!/usr/bin/env bash
# Clock fixtures for the journal-gap block in selftest.sh.
#
# Clocks, matching the behavioral fixtures that caught run 42315371378:
#   normal                  system clock
#   crossing-midnight       pre-fix sequence. Its text checks must finish on the original
#                           day (local 23:59:00, about 60s of room). The 61s sleep is what
#                           crosses midnight, and the fresh today must then warn. The live
#                           selftest lines then start at local 23:59:40 and must pass.
#   starting-near-midnight  local 23:59:10. That is 50s before midnight, outside the 30s
#                           wait. The live lines must pass without crossing midnight.
#   dst                     America/New_York and Europe/London, fall-back, spring-forward,
#                           and a normal day, at 23:00:03, 23:59:40 and 23:59:45. An
#                           injectable clock (TZ + clock_gettime preload) drives the real
#                           `date -d 'tomorrow 00:00'` used by the live wait.
#
# The live lines are taken from fleet/scripts/selftest.sh. Every journal-gap assertion in
# that block stays as selftest wrote it.
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
  index($0, "s2m=$((") == 1 && index($0, "tomorrow 00:00") { p = 1 }
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
  'tomorrow 00:00' \
  'WARN atlas: activity' \
  'check-journal.sh --strict' \
  '23:59 gap test journaled' \
  'check-journal.sh "$D"' \
  '! grep -q "^WARN atlas"' \
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
S2M_LINE="$(grep -F "tomorrow 00:00" <<<"$LIVE" | head -1)"
if [ -z "$S2M_LINE" ]; then
  echo "FAIL live journal-gap block has no tomorrow-00:00 wait" >&2
  exit 1
fi
# A reverted block is not rejected here. The crossing fixture below runs the pre-fix
# sequence through midnight; stopping at this grep would never reach that crossing.
if grep -F -q 'sleep 61' <<<"$LIVE" || grep -F -q 'date +%H:%M' <<<"$LIVE"; then
  bad "live journal-gap block still uses sleep 61 or a wall-clock journal time"
else
  ok "live journal-gap block keeps every assertion and drops the 61s sleep"
fi

# Injectable clock: real GNU date, with CLOCK_REALTIME pinned, so `tomorrow 00:00` follows the TZ's civil day.
cat > "$T/clk.c" << 'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>
static time_t fake_base(void) {
  const char *s = getenv("FAKE_EPOCH");
  if (!s || !*s) return (time_t)-1;
  return (time_t)strtoll(s, 0, 10);
}
int clock_gettime(clockid_t clk, struct timespec *tp) {
  static int (*real_clock_gettime)(clockid_t, struct timespec *);
  time_t b;
  if (!real_clock_gettime) real_clock_gettime = dlsym(RTLD_NEXT, "clock_gettime");
  if (clk == CLOCK_REALTIME && (b = fake_base()) != (time_t)-1) {
    tp->tv_sec = b; tp->tv_nsec = 0; return 0;
  }
  return real_clock_gettime(clk, tp);
}
int gettimeofday(struct timeval *tv, void *tz) {
  static int (*real_gettimeofday)(struct timeval *, void *);
  time_t b;
  if (!real_gettimeofday) real_gettimeofday = dlsym(RTLD_NEXT, "gettimeofday");
  if (tv && (b = fake_base()) != (time_t)-1) { tv->tv_sec = b; tv->tv_usec = 0; return 0; }
  return real_gettimeofday(tv, tz);
}
time_t time(time_t *t) {
  static time_t (*real_time)(time_t *);
  time_t b;
  if (!real_time) real_time = dlsym(RTLD_NEXT, "time");
  if ((b = fake_base()) != (time_t)-1) { if (t) *t = b; return b; }
  return real_time(t);
}
EOF
if gcc -shared -fPIC -o "$T/clk.so" "$T/clk.c" -ldl >/dev/null 2>"$T/gcc.err"; then
  :
else
  bad "injectable clock: gcc could not build the clock_gettime preload"
  sed 's/^/  /' "$T/gcc.err" >&2 || true
fi
# want_sleep empty means the wait must not sleep. A negative or >31s sleep is always a failure.
dst_one() {
  local tz="$1" kind="$2" day="$3" hms="$4" want="$5" want_sleep="$6"
  local epoch got slept label
  label="$tz $kind $day $hms"
  if [ ! -f "$T/clk.so" ]; then
    bad "dst $label: no injectable clock"
    return
  fi
  epoch="$(TZ="$tz" /usr/bin/date -d "$day $hms" +%s)" || { bad "dst $label: could not read that local time"; return; }
  rm -f "$T/slept"
  got="$(
    set -uo pipefail
    export TZ="$tz" LD_PRELOAD="$T/clk.so" FAKE_EPOCH="$epoch"
    sleep() { printf '%s\n' "$1" > "$T/slept"; }
    set -e
    if eval "$S2M_LINE"; then
      :
    fi
    printf '%s\n' "${s2m-}"
  )" || { bad "dst $label: wait line aborted under set -e"; return; }
  slept=""
  [ -f "$T/slept" ] && slept="$(cat "$T/slept")"
  if [ -n "$slept" ] && { [ "$slept" -lt 0 ] || [ "$slept" -gt 31 ]; }; then
    bad "dst $label: slept $slept (negative or huge)"
    return
  fi
  if [ "$got" = "$want" ] && [ "$slept" = "$want_sleep" ]; then
    if [ -n "$want_sleep" ]; then
      ok "dst $label s2m=$got sleep=$slept"
    else
      ok "dst $label s2m=$got no-sleep"
    fi
  else
    bad "dst $label s2m=${got:-empty} (want $want) sleep=${slept:-none} (want ${want_sleep:-none})"
  fi
}
for spec in \
  "America/New_York|fall-back|2026-11-01" \
  "America/New_York|spring-forward|2026-03-08" \
  "America/New_York|normal|2026-07-15" \
  "Europe/London|fall-back|2026-10-25" \
  "Europe/London|spring-forward|2026-03-29" \
  "Europe/London|normal|2026-07-15"
do
  IFS='|' read -r tz kind day <<<"$spec"
  IFS=$' \t\n'
  dst_one "$tz" "$kind" "$day" "23:00:03" 3597 ""
  dst_one "$tz" "$kind" "$day" "23:59:40" 20 "22"
  dst_one "$tz" "$kind" "$day" "23:59:45" 15 "17"
done
unset TZ LD_PRELOAD FAKE_EPOCH

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
  # Pre-fix sequence, assertions unchanged. The text checks run to completion on the
  # original day. Only then does sleep 61 cross midnight. The wall-clock journal line
  # and the fresh today (no explicit day) run after that crossing. The git reset is
  # cleanup and runs after those results are recorded.
  reset_repo
  DAY0="$(date +%F)"
  local start
  start="$(date +%s)"
  rm -f "$T/unfixed-pre.txt" "$T/unfixed-second.txt" "$T/unfixed-post.txt"
  OUT="$(
    set +e
    set -uo pipefail
    exec 2>&1
    cd "$A" || exit 97
    B=bots/atlas
    D="$(date +%F)"
    mkdir -p $B/kb $B/journal && echo gap > $B/kb/gap-test.md && git add $B && BOT_ROLE=manager git commit -qm "atlas: gap test work" --no-verify \
      && c="$(fleet/scripts/check-journal.sh)" && grep -q "^WARN atlas: activity" <<<"$c" && ! fleet/scripts/check-journal.sh --strict >/dev/null && v="$(fleet/scripts/validate.sh 2>&1)" && grep -q "^WARN atlas: activity" <<<"$v"
    pre_rc=$?
    nowf="$(date +%F)"
    left=$(( $(date -d 'tomorrow 00:00' +%s) - $(date +%s) ))
    printf 'PRE rc=%s day=%s left=%s\n' "$pre_rc" "$nowf" "$left" > "$T/unfixed-pre.txt"
    h0="$(git log --format=%H --grep="^atlas: gap test work" -1)"
    if [ "$pre_rc" -ne 0 ] || [ "$nowf" != "$D" ] || [ "$left" -le 0 ] || [ "$left" -gt 61 ]; then
      [ -n "$h0" ] && git reset -q --hard "$h0~1"
      exit 2
    fi
    sleep 61
    printf -- '- %s gap test journaled\n' "$(date +%H:%M)" >> $B/journal/$D.md && git add $B && BOT_ROLE=manager git commit -qm "atlas: journal" --no-verify \
      && c="$(fleet/scripts/check-journal.sh)" && ! grep -q "^WARN atlas" <<<"$c" && grep -q "A run is every chat turn" fleet/rules/startup.md && grep -q "After a context summary" fleet/rules/startup.md && grep -q "Delegation carries the duty" fleet/rules/startup.md && grep -q "Every chat turn is a run" templates/THIN-PROMPT.tmpl
    post_rc=$?
    printf '%s\n' "${c-}" > "$T/unfixed-second.txt"
    printf 'POST rc=%s day=%s\n' "$post_rc" "$(date +%F)" > "$T/unfixed-post.txt"
    h0="$(git log --format=%H --grep="^atlas: gap test work" -1)"
    [ -n "$h0" ] && git reset -q --hard "$h0~1"
    exit "$post_rc"
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
sod_left=$(( $(date -d 'tomorrow 00:00' +%s) - $(date +%s) ))
if [ "$RC" -eq 0 ] && { [ "$sod_left" -lt 120 ] || [ "$ELAPSED" -lt 45 ]; }; then
  ok "normal clock ($(date '+%F %T'), ${ELAPSED}s)"
else
  bad "normal clock: live journal-gap block exited $RC after ${ELAPSED}s"
  dump
fi

if pin $((23 * 3600 + 59 * 60 + 10)); then
  echo "== starting-near-midnight (TZ=$TZ local=$(date '+%F %T'), 50s before midnight)"
  run_live
  if [ "$RC" -eq 0 ] && [ "$DAY0" = "$DAY1" ] && [ "$SOD" -ge 86340 ] && [ "$ELAPSED" -lt 40 ]; then
    ok "starting near midnight stays on $DAY1 (23:59:10 is 50s out, outside the 30s wait; $(date '+%T'), ${ELAPSED}s)"
  else
    bad "starting near midnight: rc=$RC day $DAY0->$DAY1 sod=$SOD elapsed=${ELAPSED}s"
    dump
  fi
else
  bad "starting near midnight: could not pin local 23:59:10"
fi

if pin $((23 * 3600 + 59 * 60)); then
  echo "== crossing-midnight pre-fix (TZ=$TZ local=$(date '+%F %T'))"
  run_unfixed
  pre_line=""
  [ -f "$T/unfixed-pre.txt" ] && pre_line="$(cat "$T/unfixed-pre.txt")"
  left="${pre_line##* left=}"
  if [ "$pre_line" = "PRE rc=0 day=$DAY0 left=$left" ] && [ "$left" -gt 0 ] && [ "$left" -le 61 ]; then
    ok "crossing midnight: pre-fix text gates passed on $DAY0 with ${left}s left"
    if [ "$RC" -ne 0 ] && [ "$ELAPSED" -ge 61 ] && [ "$DAY0" != "$DAY1" ] \
      && [ -f "$T/unfixed-post.txt" ] && grep -q "^POST rc=[1-9]" "$T/unfixed-post.txt" && grep -q "day=$DAY1\$" "$T/unfixed-post.txt" \
      && grep -q "^WARN atlas" "$T/unfixed-second.txt" \
      && grep -q "on $DAY1" "$T/unfixed-second.txt"; then
      ok "crossing midnight: sleep 61 crossed into $DAY1 and the fresh today warns (${ELAPSED}s)"
    else
      bad "crossing midnight: pre-fix sequence should fail by crossing midnight (rc=$RC elapsed=${ELAPSED}s day $DAY0->$DAY1)"
      dump
      echo "  post: $(cat "$T/unfixed-post.txt" 2>/dev/null || echo missing)" >&2
      echo "  second check:" >&2
      sed 's/^/  /' "$T/unfixed-second.txt" >&2 || true
    fi
  else
    bad "crossing midnight: pre-fix text gates did not finish before midnight (${pre_line:-missing})"
    dump
  fi
else
  bad "crossing midnight: could not pin local 23:59:00"
fi

if pin $((23 * 3600 + 59 * 60 + 40)); then
  echo "== crossing-midnight live (TZ=$TZ local=$(date '+%F %T'))"
  run_live
  if [ "$RC" -eq 0 ] && [ "$DAY0" != "$DAY1" ] && [ "$SOD" -lt 50 ] && [ "$ELAPSED" -ge 12 ] && [ "$ELAPSED" -lt 55 ]; then
    ok "crossing midnight: live block waits out midnight and passes (${ELAPSED}s, now $(date '+%T'))"
  else
    bad "crossing midnight: live block rc=$RC day $DAY0->$DAY1 sod=$SOD elapsed=${ELAPSED}s"
    dump
  fi
else
  bad "crossing midnight: could not pin local 23:59:40"
fi

echo
echo "journal-gap midnight: $pass passed, $fail failed"
[ "$fail" = 0 ]
