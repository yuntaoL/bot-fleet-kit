#!/usr/bin/env bash
# 0.11.0: action index, shared skills index, migration, and builder ownership.
# Scratch repos only. Example names (ada, forge, pip). No owner data.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail() { echo "FAIL $*" >&2; [ -n "${OUT:-}" ] && echo "$OUT" >&2; exit 1; }
pass() { echo "PASS $*"; }
CHECK="$SRC/fleet/scripts/check-actions.sh"
MIG="$SRC/fleet/migrations/0.11.0.sh"

# Rule and template shape (the files the bots actually read).
grep -q 'local/shared/SHARED-SKILLS.md' "$SRC/fleet/rules/startup.md" || fail "startup missing shared index"
grep -q 'bots/<slug>/kb/ACTIONS.md' "$SRC/fleet/rules/startup.md" || fail "startup missing ACTIONS.md"
grep -q 'Before an outside action' "$SRC/fleet/rules/startup.md" || fail "startup missing pre-action step"
grep -q 'go to step 8' "$SRC/fleet/rules/startup.md" || fail "fail-safe pointer not updated"
grep -q 'go to step 7' "$SRC/fleet/rules/startup.md" && fail "stale fail-safe pointer"
grep -q 'SHARED-SKILLS.md' "$SRC/fleet/rules/README.md" || fail "rules README missing pointer"
grep -q 'steps 2-4' "$SRC/fleet/rules/routines.md" || fail "routines.md still on steps 2-3"
grep -q 'startup.md step 6' "$SRC/fleet/rules/routines.md" || fail "routines.md save step not updated"
grep -q 'startup.md step 6' "$SRC/fleet/scripts/check-journal.sh" || fail "journal check still cites step 5"
grep -q '../../../local/shared/SHARED-SKILLS.md' "$SRC/templates/bot/kb/ACTIONS.md" || fail "ACTIONS.md missing shared link"
grep -q 'status: stub' "$SRC/templates/bot/kb/ACTIONS.md" || fail "ACTIONS.md not a stub"
grep -q 'type: actions-index' "$SRC/templates/bot/kb/ACTIONS.md" || fail "ACTIONS.md type"
grep -q 'ACTIONS.md' "$SRC/templates/bot/kb/INDEX.md" || fail "kb INDEX missing ACTIONS row"
grep -q 'type: shared-skills-index' "$SRC/templates/local/shared/SHARED-SKILLS.md" || fail "shared index type"
grep -q 'status: stub' "$SRC/templates/local/shared/SHARED-SKILLS.md" || fail "shared index not a stub"
grep -q '| fleet-change |' "$SRC/templates/local/shared/SHARED-SKILLS.md" || fail "fleet-change row"
grep -q '| rename-bot |' "$SRC/templates/local/shared/SHARED-SKILLS.md" || fail "rename-bot row"
grep -q '"builder"' "$SRC/fleet/schema/owners.schema.json" || fail "owner enum missing builder"
grep -q 'local/shared/SHARED-SKILLS.md' "$SRC/fleet/OWNERS.json" || fail "OWNERS missing shared index rule"
python3 -c 'import json; r=json.load(open("'"$SRC"'/fleet/OWNERS.json"))["rules"]; i=next(k for k,x in enumerate(r) if x["path"]=="local/shared/SHARED-SKILLS.md"); j=next(k for k,x in enumerate(r) if x["path"]=="local/**"); assert i<j and r[i]["owner"]=="builder"' || fail "builder rule is not before local/**"
# Prompts stay thin: they already route through startup.md.
grep -q 'ACTIONS.md' "$SRC/templates/THIN-PROMPT.tmpl" && fail "THIN-PROMPT should not gain ACTIONS.md"
grep -q 'ACTIONS.md' "$SRC/templates/ROUTINE-PROMPT.tmpl" && fail "ROUTINE-PROMPT should not gain ACTIONS.md"
pass "startup, templates, OWNERS, prompts"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.invalid
git config --global commit.gpgsign false

REPO="$T/repo"
mkdir -p "$REPO/fleet/docs" "$REPO/fleet/skills" "$REPO/fleet/scripts" "$REPO/fleet/schema" \
  "$REPO/local/shared/skills" "$REPO/templates/bot/kb" "$REPO/templates/local/shared" "$REPO/bots"
cp -a "$SRC/fleet/skills/." "$REPO/fleet/skills/"
cp "$SRC/fleet/docs/CONTRIBUTING.md" "$REPO/fleet/docs/CONTRIBUTING.md"
cp "$SRC/fleet/OWNERS.json" "$REPO/fleet/OWNERS.json"
cp "$SRC/fleet/scripts/owners.py" "$REPO/fleet/scripts/owners.py"
cp "$SRC/fleet/scripts/check-boundary.sh" "$REPO/fleet/scripts/check-boundary.sh"
cp "$SRC/templates/bot/kb/ACTIONS.md" "$REPO/templates/bot/kb/ACTIONS.md"
cp "$SRC/templates/local/shared/SHARED-SKILLS.md" "$REPO/templates/local/shared/SHARED-SKILLS.md"
cp -a "$SRC/templates/bot" "$REPO/bots/ada"
cp "$SRC/templates/local/shared/SHARED-SKILLS.md" "$REPO/local/shared/SHARED-SKILLS.md"
git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name test

set_bots() {
  python3 - "$REPO" "$@" <<'PY'
import json, sys
root, *items = sys.argv[1:]
bots = []
for item in items:
    parts = item.split(":")
    slug, role = parts[0], parts[1]
    status = parts[2] if len(parts) > 2 else "active"
    bots.append({"slug": slug, "name": slug.title(), "id": "id-" + slug, "role": role, "status": status})
json.dump({"schemaVersion": 2, "owner": "sam", "owner_name": "Sam Example", "templateVersion": "0.11.0", "bots": bots},
          open(root + "/local/fleet.json", "w"), indent=2)
open(root + "/local/fleet.json", "a").write("\n")
PY
}
run() {
  OUT="$(cd "$REPO" && "$@" 2>&1)" && RC=0 || RC=$?
}
set_bots ada:worker
run "$CHECK"
[ "$RC" = 0 ] || fail "stock stubs should warn, not fail"
echo "$OUT" | grep -q '^WARN fleet: stub index, not seeded yet$' || fail "shared stub warn"
echo "$OUT" | grep -q '^WARN ada: stub index, not seeded yet$' || fail "actions stub warn"
echo "$OUT" | grep -q 'check-actions: a=0 e=0 b=0 c=0 d=0 f=0 g=0 h=0 i=0 stub=2 type=0 folder=0 status=0' || fail "stub count: $OUT"
echo "$OUT" | grep -q '^FAIL' && fail "stock stubs produced a FAIL" || true
pass "stock template: stub warns only (no dead links, shared skills listed)"

# Seeded copies of the same rows: a clean bot is silent.
python3 - <<PY
from pathlib import Path
for p in ["$REPO/local/shared/SHARED-SKILLS.md", "$REPO/bots/ada/kb/ACTIONS.md"]:
    t = Path(p).read_text().replace("status: stub", "status: seeded", 1)
    Path(p).write_text(t)
PY
cp "$REPO/local/shared/SHARED-SKILLS.md" "$T/shared.seeded"
cp "$REPO/bots/ada/kb/ACTIONS.md" "$T/actions.seeded"
restore() {
  cp "$T/shared.seeded" "$REPO/local/shared/SHARED-SKILLS.md"
  cp "$T/actions.seeded" "$REPO/bots/ada/kb/ACTIONS.md"
  set_bots ada:worker
  rm -rf "$REPO/bots/ada/kb/prefs" "$REPO/bots/ada/kb/notes" "$REPO/bots/ada/kb/me" "$REPO/bots/ada/kb/mission" "$REPO/bots/ada/skills" "$REPO/bots/bee" "$REPO/bots/oldie" "$REPO/bots/newbot" "$REPO/bots/oldbot" "$REPO/local/shared/skills"
  mkdir -p "$REPO/local/shared/skills"
  cp "$SRC/templates/bot/rules.md" "$REPO/bots/ada/rules.md"
  rm -f "$REPO/bots/ada/routines/"*.json "$REPO/bots/ada/routines/"*.steps.md 2>/dev/null || true
}
restore
run "$CHECK"
[ "$RC" = 0 ] && [ "$OUT" = "check-actions: OK" ] || fail "clean seeded bot: $OUT"
pass "clean seeded bot: OK"

# (a) missing index
rm "$REPO/bots/ada/kb/ACTIONS.md"
run "$CHECK"
[ "$RC" != 0 ] || fail "missing ACTIONS should fail"
echo "$OUT" | grep -q '^FAIL ada: missing bots/ada/kb/ACTIONS.md$' || fail "missing line: $OUT"
pass "(a) missing ACTIONS.md fails"

# (e) dead link, ignored forms are not dead, bare skill name is not dead
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
t = p.read_text()
t = t.replace(
    "skill \`fleet-change\`, \`fleet/skills/fleet-change/SKILL.md\`, \`fleet/docs/CONTRIBUTING.md\`",
    "skill \`fleet-change\`, \`prefs/missing.md\`, [hours](prefs/no-such.md), [web](https://example.com/a.md), \`~/notes.md\`, \`/etc/nope.md\`, \`\$TOKEN\`, skill \`purchases\`",
)
p.write_text(t)
PY
run "$CHECK"
[ "$RC" != 0 ] || fail "dead link should fail"
echo "$OUT" | grep -q 'dead link `prefs/missing.md`' || fail "backtick dead link: $OUT"
echo "$OUT" | grep -q 'dead link `prefs/no-such.md`' || fail "markdown dead link: $OUT"
n="$(echo "$OUT" | grep -c '^FAIL ada: dead link' || true)"
[ "$n" = 2 ] || fail "expected 2 dead links, got $n: $OUT"
echo "$OUT" | grep -q 'purchases' && fail "bare skill name counted as a failure" || true
pass "(e) dead links fail; http, ~, absolute, env, and bare skill name do not"

# (b) standing kb/me/prefs and kb/me/services only; mission-scoped prefs are not flagged
restore
mkdir -p "$REPO/bots/ada/kb/me/prefs" "$REPO/bots/ada/kb/me/services" "$REPO/bots/ada/kb/mission/prefs" "$REPO/bots/ada/kb/prefs" "$REPO/bots/ada/kb/notes"
printf '%s\n' '---' 'type: pref' 'updated: 2026-11-11' '---' '# Hours' 'Example only.' > "$REPO/bots/ada/kb/me/prefs/hours.md"
printf '%s\n' '---' 'type: service' 'updated: 2026-11-11' '---' '# Inbox' 'Example only.' > "$REPO/bots/ada/kb/me/services/inbox.md"
printf '%s\n' '---' 'type: pref' 'updated: 2026-11-11' '---' '# Job' 'Example only.' > "$REPO/bots/ada/kb/mission/prefs/job.md"
printf '%s\n' '---' 'type: pref' 'updated: 2026-11-11' '---' '# Other' 'Example only.' > "$REPO/bots/ada/kb/prefs/hours.md"
printf '%s\n' '---' 'type: preference' 'updated: 2026-11-11' '---' '# Likes' 'Example only.' > "$REPO/bots/ada/kb/notes/likes.md"
run "$CHECK"
[ "$RC" = 0 ] || fail "unindexed pref should warn, not fail: $OUT"
echo "$OUT" | grep -q '^WARN ada: unindexed pref me/prefs/hours.md$' || fail "standing pref: $OUT"
echo "$OUT" | grep -q '^WARN ada: unindexed pref me/services/inbox.md$' || fail "standing service: $OUT"
echo "$OUT" | grep -q 'mission/prefs' && fail "mission-scoped pref was flagged: $OUT" || true
echo "$OUT" | grep -q 'unindexed pref prefs/hours.md' && fail "top-level prefs was flagged: $OUT" || true
echo "$OUT" | grep -q 'notes/likes.md' && fail "front-matter outside me/ was flagged: $OUT" || true
run env BOT_FLEET_STRICT_ACTIONS=1 "$CHECK"
[ "$RC" != 0 ] || fail "strict pref should fail"
echo "$OUT" | grep -q '^FAIL ada: unindexed pref me/prefs/hours.md$' || fail "strict prefix: $OUT"
pass "(b) standing me/prefs and me/services warn; mission-scoped prefs do not"

# INDEX.md of the same folder covers the file
printf '%s\n' '---' 'type: index' 'updated: 2026-11-11' '---' '# prefs' > "$REPO/bots/ada/kb/me/prefs/INDEX.md"
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
t = p.read_text().replace("| calendar |", "| calendar | \`me/prefs/INDEX.md\`, ", 1)
p.write_text(t)
PY
run "$CHECK"
echo "$OUT" | grep -q 'me/prefs/hours.md' && fail "INDEX coverage missed: $OUT" || true
echo "$OUT" | grep -q 'me/services/inbox.md' || fail "other standing folder still unindexed: $OUT"
pass "(b) a referenced folder INDEX covers that folder"

# (c) unindexed own skill
restore
mkdir -p "$REPO/bots/ada/skills/sample-calendar"
printf '%s\n' '---' 'name: sample-calendar' '---' '# Example' > "$REPO/bots/ada/skills/sample-calendar/SKILL.md"
run "$CHECK"
[ "$RC" = 0 ] || fail "unindexed skill should warn: $OUT"
echo "$OUT" | grep -q '^WARN ada: unindexed skill sample-calendar$' || fail "own skill: $OUT"
pass "(c) unindexed own skill warns"

# naming it clears (c); a platform skill named only by bare name does not fail
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
t = p.read_text().replace("skill \`fleet-change\`", "skill \`sample-calendar\`, skill \`purchases\`, skill \`fleet-change\`", 1)
p.write_text(t)
PY
run "$CHECK"
[ "$RC" = 0 ] && [ "$OUT" = "check-actions: OK" ] || fail "bare purchases / named own skill: $OUT"
pass "own skill named in Read-first is indexed; bare managed skill is not a FAIL"

# (d) cited in rules.md and in routine steps, not in ACTIONS
restore
printf '\nUse skill `sample-mail` before sending.\n' >> "$REPO/bots/ada/rules.md"
mkdir -p "$REPO/bots/ada/routines"
printf '%s\n' '{"name":"daily","schedule":"daily","steps":["Open skills/sample-trip/SKILL.md and follow it."]}' > "$REPO/bots/ada/routines/daily.json"
printf '%s\n' 'Follow skill `sample-vault`.' > "$REPO/bots/ada/routines/daily.steps.md"
run "$CHECK"
[ "$RC" = 0 ] || fail "citations should warn: $OUT"
echo "$OUT" | grep -q 'skill `sample-mail` cited in bots/ada/rules.md' || fail "rules cite: $OUT"
echo "$OUT" | grep -q 'skill `sample-trip` cited in bots/ada/routines/daily.json' || fail "steps cite: $OUT"
echo "$OUT" | grep -q 'skill `sample-vault` cited in bots/ada/routines/daily.steps.md' || fail "steps file cite: $OUT"
pass "(d) skills cited in rules and routines warn"

# actions stub still warns when nothing else is wrong
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
p.write_text(p.read_text().replace("status: seeded", "status: stub", 1))
PY
run "$CHECK"
[ "$RC" = 0 ] || fail "actions stub should warn: $OUT"
echo "$OUT" | grep -q '^WARN ada: stub index, not seeded yet$' || fail "actions stub line: $OUT"
echo "$OUT" | grep -q '^WARN fleet:' && fail "seeded shared index warned: $OUT" || true
pass "actions stub warns and does not pass silently"

# (f) missing shared index
restore
rm "$REPO/local/shared/SHARED-SKILLS.md"
run "$CHECK"
[ "$RC" != 0 ] || fail "missing shared index should fail"
echo "$OUT" | grep -q '^FAIL fleet: missing local/shared/SHARED-SKILLS.md$' || fail "missing shared: $OUT"
echo "$OUT" | grep -q 'dead link `../../../local/shared/SHARED-SKILLS.md`' || fail "link to missing index should be dead: $OUT"
pass "(f) missing shared index fails"

# (f) stub warns; dead link in the shared index fails
restore
cp "$SRC/templates/local/shared/SHARED-SKILLS.md" "$REPO/local/shared/SHARED-SKILLS.md"
run "$CHECK"
[ "$RC" = 0 ] || fail "shared stub should warn: $OUT"
echo "$OUT" | grep -q '^WARN fleet: stub index, not seeded yet$' || fail "shared stub: $OUT"
printf '\n| ghost | Use nowhere. | none | builder | [gone](does-not-exist.md) |\n' >> "$REPO/local/shared/SHARED-SKILLS.md"
run "$CHECK"
[ "$RC" != 0 ] || fail "shared dead link should fail"
echo "$OUT" | grep -q '^FAIL fleet: dead link `does-not-exist.md`$' || fail "shared dead link: $OUT"
pass "(f) shared stub warns; dead link in it fails"

# (g) fleet skill not listed
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/local/shared/SHARED-SKILLS.md")
lines = [ln for ln in p.read_text().splitlines() if not ln.startswith("| rename-bot |")]
p.write_text("\n".join(lines) + "\n")
PY
run "$CHECK"
[ "$RC" = 0 ] || fail "unlisted fleet skill should warn: $OUT"
echo "$OUT" | grep -q '^WARN fleet: unindexed shared skill rename-bot (fleet/skills/rename-bot)$' || fail "g fleet: $OUT"
mkdir -p "$REPO/local/shared/skills/sample-shared"
printf '%s\n' '---' 'name: sample-shared' '---' '# Example' > "$REPO/local/shared/skills/sample-shared/SKILL.md"
run "$CHECK"
echo "$OUT" | grep -q 'unindexed shared skill sample-shared (local/shared/skills/sample-shared)' || fail "g local: $OUT"
pass "(g) unlisted fleet and local/shared skills warn"

# (g) library: unlisted warns; bot dir or exactly one (private) mark does not; two marks do; listed does not
restore
LIB="$T/library"
mkdir -p "$LIB/sample-lib"
printf '%s\n' '---' 'name: sample-lib' '---' '# Example library skill' > "$LIB/sample-lib/SKILL.md"
run env BOT_FLEET_SKILL_LIBRARY="$LIB" "$CHECK"
[ "$RC" = 0 ] || fail "library warn should not fail: $OUT"
echo "$OUT" | grep -q '^WARN fleet: unindexed library skill sample-lib$' || fail "library: $OUT"
mkdir -p "$REPO/bots/ada/skills/sample-lib"
run env BOT_FLEET_SKILL_LIBRARY="$LIB" "$CHECK"
echo "$OUT" | grep -q 'library skill' && fail "bot skill dir should count as private: $OUT" || true
rmdir "$REPO/bots/ada/skills/sample-lib"
printf '\nsample-lib (private) stays on this bot.\n' >> "$REPO/bots/ada/kb/ACTIONS.md"
run env BOT_FLEET_SKILL_LIBRARY="$LIB" "$CHECK"
echo "$OUT" | grep -q 'library skill' && fail "one (private) mark should be enough: $OUT" || true
mkdir -p "$REPO/bots/bee/kb"
cp "$T/actions.seeded" "$REPO/bots/bee/kb/ACTIONS.md"
printf '\nsample-lib (private) also here.\n' >> "$REPO/bots/bee/kb/ACTIONS.md"
set_bots ada:worker bee:worker
run env BOT_FLEET_SKILL_LIBRARY="$LIB" "$CHECK"
echo "$OUT" | grep -q '^WARN fleet: unindexed library skill sample-lib$' || fail "two private marks: $OUT"
# listed in the shared index: not warned, even with no private mark
python3 - <<PY
from pathlib import Path
p = Path("$REPO/local/shared/SHARED-SKILLS.md")
p.write_text(p.read_text() + "| sample-lib | Use for the example library only. | notes | ada | \`library\` |\n")
PY
run env BOT_FLEET_SKILL_LIBRARY="$LIB" "$CHECK"
echo "$OUT" | grep -q 'library skill' && fail "listed library skill warned: $OUT" || true
unset LIB_RUN
pass "(g) library skill: warn, bot-private exceptions, listed is quiet"

# (h) copying a shared skill name, or its when-to-use text; Read-first does not count
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
t = p.read_text()
t = t.replace("| repo and fleet changes |", "| fleet-change |", 1)
p.write_text(t)
PY
run "$CHECK"
[ "$RC" = 0 ] || fail "copy should warn: $OUT"
echo "$OUT" | grep -q '^WARN ada: ACTIONS.md row copies shared skill fleet-change$' || fail "h name: $OUT"
restore
WHEN="$(python3 - <<PY
from pathlib import Path
for ln in Path("$T/shared.seeded").read_text().splitlines():
    if ln.startswith("| fleet-change |"):
        print(ln.split("|")[2].strip())
        break
PY
)"
[ "${#WHEN}" -ge 40 ] || fail "fixture when-to-use is shorter than 40 chars: $WHEN"
python3 - "$REPO/bots/ada/kb/ACTIONS.md" "$WHEN" <<'PY'
import pathlib, sys
p, when = pathlib.Path(sys.argv[1]), sys.argv[2]
t = p.read_text().replace("| fill in |", "| " + when + " |", 1)
p.write_text(t)
PY
run "$CHECK"
echo "$OUT" | grep -q 'repeats shared when-to-use text for fleet-change' || fail "h when: $OUT"
# The seeded file already names fleet-change in Read-first and must stay clean.
restore
run "$CHECK"
[ "$OUT" = "check-actions: OK" ] || fail "Read-first mention looked like a copy: $OUT"
pass "(h) copied action name and when-to-use warn; Read-first does not"

# (i) no link
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
t = p.read_text().replace("[shared skills index](../../../local/shared/SHARED-SKILLS.md)", "shared skills index", 1)
p.write_text(t)
PY
run "$CHECK"
[ "$RC" = 0 ] || fail "missing link should warn: $OUT"
echo "$OUT" | grep -q '^WARN ada: ACTIONS.md does not link to local/shared/SHARED-SKILLS.md$' || fail "i: $OUT"
pass "(i) no link to the shared index warns"

# retired bot with no index is skipped; no fleet.json skips cleanly
restore
mkdir -p "$REPO/bots/oldie"
set_bots ada:worker oldie:retired
run "$CHECK"
[ "$OUT" = "check-actions: OK" ] || fail "retired bot was checked: $OUT"
mv "$REPO/local/fleet.json" "$T/fleet.json"
run "$CHECK"
[ "$RC" = 0 ] && [ "$OUT" = "check-actions: skipped (no local/fleet.json)" ] || fail "skip: $OUT"
mv "$T/fleet.json" "$REPO/local/fleet.json"
pass "retired bot skipped; no fleet.json skips"

# S2: placeholders, fences, reference links, %20, and a path that leaves the repo
restore
mkdir -p "$REPO/bots/ada/kb"
printf '%s\n' '---' 'type: note' '---' '# spaced' > "$REPO/bots/ada/kb/note file.md"
python3 - "$REPO" <<'PY'
import os, pathlib, sys
repo = sys.argv[1]
p = pathlib.Path(repo) / "bots/ada/kb/ACTIONS.md"
rel = os.path.relpath("/etc/passwd", str(p.parent))
extra = """
```
[fenced](prefs/fenced-missing.md)
`kb/prefs/x.md`
```
See [missing][ref].
[ref]: prefs/ref-missing.md
Also [spaced](note%20file.md), `kb/prefs/x.md`, `skills/<n>/SKILL.md`, and `bots/<slug>/kb/INDEX.md`.
And [escape](REL).
""".replace("REL", rel)
p.write_text(p.read_text() + extra)
PY
run "$CHECK"
[ "$RC" != 0 ] || fail "escaping link should fail"
echo "$OUT" | grep -q 'dead link `prefs/ref-missing.md`' || fail "reference link: $OUT"
echo "$OUT" | grep -q 'fenced-missing' && fail "fenced link was checked: $OUT" || true
echo "$OUT" | grep -q 'kb/prefs/x.md' && fail "placeholder x.md was a dead link: $OUT" || true
echo "$OUT" | grep -q 'skills/<n>' && fail "angle-bracket placeholder was a dead link: $OUT" || true
echo "$OUT" | grep -q 'note%20file.md' && fail "%20 was not decoded: $OUT" || true
echo "$OUT" | grep -q 'etc/passwd' || fail "path outside the repo was not dead: $OUT"
pass "S2 placeholders, fences, reference links, %20, and paths outside the repo"

# kb/ and skills/ paths resolve against bots/<slug>/, not only next to ACTIONS.md
restore
mkdir -p "$REPO/bots/ada/kb/prefs" "$REPO/bots/ada/skills/vault"
printf '%s\n' '---' 'type: pref' 'updated: 2026-11-11' '---' '# Hours' 'Example only.' > "$REPO/bots/ada/kb/prefs/hours.md"
printf '%s\n' '---' 'name: vault' '---' '# Vault' 'Example only.' > "$REPO/bots/ada/skills/vault/SKILL.md"
printf '\n`kb/prefs/hours.md`\n`skills/vault/SKILL.md`\n`kb/prefs/nope.md`\n' >> "$REPO/bots/ada/kb/ACTIONS.md"
run "$CHECK"
echo "$OUT" | grep -q 'dead link `kb/prefs/hours.md`' && fail "existing kb/prefs/hours.md was dead: $OUT" || true
echo "$OUT" | grep -q 'dead link `skills/vault/SKILL.md`' && fail "existing skills/vault/SKILL.md was dead: $OUT" || true
echo "$OUT" | grep -q 'dead link `kb/prefs/nope.md`' || fail "missing kb/prefs/nope.md should fail: $OUT"
[ "$RC" != 0 ] || fail "missing kb path should fail the check"
pass "S2 kb/ and skills/ resolve under bots/<slug>/; a missing kb path still fails"

# a missing status field warns; a symlinked prefs dir is not walked
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
lines = [ln for ln in p.read_text().splitlines() if not ln.startswith("status:")]
p.write_text("\n".join(lines) + "\n")
PY
run "$CHECK"
[ "$RC" = 0 ] || fail "missing status should warn, not fail: $OUT"
echo "$OUT" | grep -q '^WARN ada: ACTIONS.md front matter has no status$' || fail "missing status: $OUT"
mkdir -p "$T/linked-prefs" "$REPO/bots/ada/kb/me"
printf '%s\n' '---' 'type: pref' 'updated: 2026-11-11' '---' '# Hidden' > "$T/linked-prefs/hidden.md"
ln -s "$T/linked-prefs" "$REPO/bots/ada/kb/me/prefs"
run "$CHECK"
echo "$OUT" | grep -q 'hidden.md' && fail "symlinked prefs dir was followed: $OUT" || true
pass "missing status warns; a symlinked prefs dir is not scanned"

# symlinked indexes are failures and are not read
restore
rm "$REPO/bots/ada/kb/ACTIONS.md"
ln -s /etc/passwd "$REPO/bots/ada/kb/ACTIONS.md"
run "$CHECK"
[ "$RC" != 0 ] || fail "symlinked ACTIONS should fail"
echo "$OUT" | grep -q 'ACTIONS.md is a symlink' || fail "symlink message: $OUT"
echo "$OUT" | grep -q 'root:' && fail "symlink target was read: $OUT" || true
rm "$REPO/bots/ada/kb/ACTIONS.md"
cp "$T/actions.seeded" "$REPO/bots/ada/kb/ACTIONS.md"
rm "$REPO/local/shared/SHARED-SKILLS.md"
ln -s /etc/passwd "$REPO/local/shared/SHARED-SKILLS.md"
run "$CHECK"
[ "$RC" != 0 ] || fail "symlinked shared index should fail"
echo "$OUT" | grep -q 'local/shared/SHARED-SKILLS.md is a symlink' || fail "shared symlink: $OUT"
rm "$REPO/local/shared/SHARED-SKILLS.md"
cp "$T/shared.seeded" "$REPO/local/shared/SHARED-SKILLS.md"
pass "S2 symlinked ACTIONS.md and SHARED-SKILLS.md fail and are not read"

# wrong front matter type warns
restore
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
p.write_text(p.read_text().replace("type: actions-index", "type: index", 1))
PY
run "$CHECK"
[ "$RC" = 0 ] || fail "wrong type should warn: $OUT"
echo "$OUT" | grep -q "ACTIONS.md type is 'index', expected actions-index" || fail "type warn: $OUT"
run env BOT_FLEET_STRICT_ACTIONS=1 "$CHECK"
[ "$RC" != 0 ] || fail "strict type should fail"
pass "ACTIONS.md type other than actions-index warns"

# S3: a roster row with no folder yet does not fail validate
restore
set_bots ada:worker ghost:worker:pre-fleet later:worker
run "$CHECK"
[ "$RC" = 0 ] || fail "missing folder should not fail: $OUT"
echo "$OUT" | grep -q '^WARN ghost: no bots/ghost yet' || fail "pre-fleet warn: $OUT"
echo "$OUT" | grep -q '^WARN later: no bots/later yet' || fail "active-without-folder warn: $OUT"
run env BOT_FLEET_STRICT_ACTIONS=1 "$CHECK"
[ "$RC" = 0 ] || fail "strict still failed a missing folder: $OUT"
echo "$OUT" | grep -q '^FAIL ghost:' && fail "strict promoted a missing folder: $OUT" || true
pass "S3 missing bot folder warns and does not fail, even when strict"

# S4: the action label 'vault' does not index a vault skill; `sync` after skill \`name\` is not a skill
restore
mkdir -p "$REPO/bots/ada/skills/vault"
printf '%s\n' '---' 'name: vault' '---' '# Example' > "$REPO/bots/ada/skills/vault/SKILL.md"
run "$CHECK"
echo "$OUT" | grep -q '^WARN ada: unindexed skill vault$' || fail "vault label hid the skill: $OUT"
printf '\nUse skill `purchases` then save with `sync`.\n' >> "$REPO/bots/ada/rules.md"
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/ada/kb/ACTIONS.md")
t = p.read_text().replace("skill \`fleet-change\`", "skill \`purchases\`, skill \`fleet-change\`", 1)
p.write_text(t)
PY
run env BOT_FLEET_STRICT_ACTIONS=1 "$CHECK"
echo "$OUT" | grep -q 'skill `sync`' && fail "sync was treated as a skill: $OUT" || true
echo "$OUT" | grep -q 'skill `purchases`' && fail "indexed purchases was still cited: $OUT" || true
echo "$OUT" | grep -q 'unindexed skill vault' || fail "vault still hidden under strict: $OUT"
pass "S4 vault label does not hide a vault skill; sync is not a cited skill"

# migration: create missing stubs, never overwrite, second run is a no-op
mkdir -p "$REPO/bots/newbot/kb" "$REPO/bots/oldbot/kb" "$REPO/bots/oldie/kb"
printf 'custom oldbot actions, leave me\n' > "$REPO/bots/oldbot/kb/ACTIONS.md"
printf 'custom shared index, leave me\n' > "$REPO/local/shared/SHARED-SKILLS.md"
set_bots newbot:worker oldbot:worker oldie:retired ada:worker
old_sum="$(sha256sum "$REPO/bots/oldbot/kb/ACTIONS.md" | awk '{print $1}')"
shared_sum="$(sha256sum "$REPO/local/shared/SHARED-SKILLS.md" | awk '{print $1}')"
run bash "$MIG" --dry-run
echo "$OUT" | grep -q 'would: write bots/newbot/kb/ACTIONS.md' || fail "dry-run newbot: $OUT"
echo "$OUT" | grep -q 'SHARED-SKILLS' && fail "dry-run would overwrite shared index: $OUT" || true
echo "$OUT" | grep -q oldbot && fail "dry-run would touch oldbot: $OUT" || true
echo "$OUT" | grep -q oldie && fail "dry-run would touch retired: $OUT" || true
[ ! -f "$REPO/bots/newbot/kb/ACTIONS.md" ] || fail "dry-run wrote a file"
run bash "$MIG"
cmp -s "$REPO/templates/bot/kb/ACTIONS.md" "$REPO/bots/newbot/kb/ACTIONS.md" || fail "newbot stub != template"
[ "$(sha256sum "$REPO/bots/oldbot/kb/ACTIONS.md" | awk '{print $1}')" = "$old_sum" ] || fail "oldbot changed"
[ "$(sha256sum "$REPO/local/shared/SHARED-SKILLS.md" | awk '{print $1}')" = "$shared_sum" ] || fail "shared index overwritten"
[ ! -f "$REPO/bots/oldie/kb/ACTIONS.md" ] || fail "retired bot gained ACTIONS.md"
run bash "$MIG"
[ -z "$OUT" ] || fail "second migration run was not a no-op: $OUT"
rm "$REPO/local/shared/SHARED-SKILLS.md"
run bash "$MIG" --dry-run
echo "$OUT" | grep -q 'would: write local/shared/SHARED-SKILLS.md' || fail "dry-run shared: $OUT"
[ ! -f "$REPO/local/shared/SHARED-SKILLS.md" ] || fail "dry-run created shared index"
run bash "$MIG"
cmp -s "$REPO/templates/local/shared/SHARED-SKILLS.md" "$REPO/local/shared/SHARED-SKILLS.md" || fail "shared stub != template"
[ "$(sha256sum "$REPO/bots/oldbot/kb/ACTIONS.md" | awk '{print $1}')" = "$old_sum" ] || fail "oldbot changed on shared seed"
run bash "$MIG"
[ -z "$OUT" ] || fail "migration not a no-op after shared seed: $OUT"
pass "migration seeds missing stubs, leaves existing bytes, second run is a no-op"

# F3: a committed symlinked kb and a symlinked local/shared are not written through
SYM="$T/symrepo"
mkdir -p "$SYM/templates/bot/kb" "$SYM/templates/local/shared" "$SYM/bots/real/kb" "$SYM/bots/linkbot" "$T/outside-kb" "$T/outside-shared"
cp "$SRC/templates/bot/kb/ACTIONS.md" "$SYM/templates/bot/kb/ACTIONS.md"
cp "$SRC/templates/local/shared/SHARED-SKILLS.md" "$SYM/templates/local/shared/SHARED-SKILLS.md"
ln -s "$T/outside-kb" "$SYM/bots/linkbot/kb"
ln -s "$T/outside-shared" "$SYM/local-shared-link"
mkdir -p "$SYM/local"
# local/shared itself is the symlink the migration must refuse
ln -s "$T/outside-shared" "$SYM/local/shared"
python3 - "$SYM" <<'PY'
import json, sys
root = sys.argv[1]
json.dump({"schemaVersion": 2, "owner": "sam", "owner_name": "Sam Example", "templateVersion": "0.11.0",
           "bots": [{"slug": "linkbot", "name": "Linkbot", "id": "id-linkbot", "role": "worker", "status": "active"},
                    {"slug": "real", "name": "Real", "id": "id-real", "role": "worker", "status": "active"}]},
          open(root + "/local/fleet.json", "w"), indent=2)
PY
git init -q -b main "$SYM"
git -C "$SYM" config user.email test@example.invalid
git -C "$SYM" config user.name test
git -C "$SYM" add -A
git -C "$SYM" commit -qm "symlinks" --no-verify
set +e
sym_out="$(cd "$SYM" && bash "$MIG" 2>&1)"
sym_rc=$?
set -e
[ "$sym_rc" != 0 ] || fail "migration followed a symlink: $sym_out"
echo "$sym_out" | grep -q 'is a symlink' || fail "migration symlink error: $sym_out"
[ ! -e "$T/outside-kb/ACTIONS.md" ] || fail "migration wrote through the kb symlink"
[ ! -e "$T/outside-shared/SHARED-SKILLS.md" ] || fail "migration wrote through the local/shared symlink"
# the safe bot still receives a stub; the bad paths do not make the whole run a silent success
[ -f "$SYM/bots/real/kb/ACTIONS.md" ] || fail "migration skipped a safe bot"
pass "F3 migration refuses a symlinked kb and a symlinked local/shared"

# Ownership: builder may commit the shared index; worker and manager may not edit it; upgrade may.
# Manager may add the pristine template stub (bootstrap).
for s in schema_check.py check-staged-config.sh confidential-scan.sh sync.sh install-hook.sh; do
  cp "$SRC/fleet/scripts/$s" "$REPO/fleet/scripts/$s"
done
cp -a "$SRC/fleet/schema/." "$REPO/fleet/schema/"
chmod +x "$REPO/fleet/scripts/"*.sh
# A committable tree: seeded shared index is an edit away from the template, so the
# pristine-stub allowance does not cover it. Commit the baseline without the hook.
set_bots ada:worker forge:builder pip:worker
mkdir -p "$REPO/bots/forge" "$REPO/bots/pip" "$REPO/local"
printf 'forge\n' > "$REPO/bots/forge/rules.md"
printf '# overrides\n' > "$REPO/local/overrides.md"
printf '# test fleet\n' > "$REPO/README.md"
cp "$T/shared.seeded" "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -A
git -C "$REPO" commit -qm "baseline" --no-verify
git init -q --bare -b main "$T/origin.git"
git -C "$REPO" remote add origin "$T/origin.git"
git -C "$REPO" push -q origin HEAD:main
(cd "$REPO" && fleet/scripts/install-hook.sh)
commit_as() { # role slug message ; sets RC
  OUT="$(cd "$REPO" && BOT_NAME="$2" BOT_ROLE="$1" git commit -qm "$3" 2>&1)" && RC=0 || RC=$?
}
# builder (fleet.json), even if the env role says worker
echo 'builder edit' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as worker forge "forge: shared index"
[ "$RC" = 0 ] || fail "builder commit rejected: $OUT"
pass "builder (fleet.json role) may commit SHARED-SKILLS.md"
# env role builder is not enough when fleet.json says manager
echo 'manager pretending' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as builder ada "ada: shared index"
[ "$RC" != 0 ] || fail "non-builder with BOT_ROLE=builder was allowed"
echo "$OUT" | grep -q 'builder-owned' || fail "expected builder-owned rejection: $OUT"
git -C "$REPO" reset -q --hard HEAD
# worker
echo 'worker edit' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as worker pip "pip: shared index"
[ "$RC" != 0 ] || fail "worker commit was allowed"
git -C "$REPO" reset -q --hard HEAD
# manager edit
echo 'manager edit' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as manager ada "ada: shared index"
[ "$RC" != 0 ] || fail "manager edit was allowed"
git -C "$REPO" reset -q --hard HEAD
# upgrade path
echo 'upgrade edit' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
OUT="$(cd "$REPO" && BOT_FLEET_UPGRADE=1 BOT_NAME=ada BOT_ROLE=manager git commit -qm "upgrade: shared index" 2>&1)" && RC=0 || RC=$?
[ "$RC" = 0 ] || fail "upgrade commit rejected: $OUT"
pass "worker and manager cannot edit the shared index; upgrade can"
# manager may add the pristine stub; a worker may not
git -C "$REPO" rm -q local/shared/SHARED-SKILLS.md
OUT="$(cd "$REPO" && BOT_FLEET_UPGRADE=1 BOT_ROLE=manager git commit -qm "upgrade: drop stub" 2>&1)" && RC=0 || RC=$?
[ "$RC" = 0 ] || fail "upgrade could not remove the index: $OUT"
cp "$SRC/templates/local/shared/SHARED-SKILLS.md" "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as worker pip "pip: add stub"
[ "$RC" != 0 ] || fail "worker add of the stub was allowed"
git -C "$REPO" reset -q HEAD
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as manager ada "ada: add stub"
[ "$RC" = 0 ] || fail "manager add of the pristine stub was rejected: $OUT"
pass "manager may add the pristine template stub; a worker may not"

# F1a: an unstaged role flip does not authorize a worker
python3 - "$REPO/local/fleet.json" <<'PY'
import json, sys
p = sys.argv[1]
fl = json.load(open(p))
for b in fl["bots"]:
    if b["slug"] == "pip":
        b["role"] = "builder"
json.dump(fl, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
echo 'worker via dirty roster' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as worker pip "pip: shared index"
[ "$RC" != 0 ] || fail "unstaged role flip authorized a worker"
echo "$OUT" | grep -q 'builder-owned' || fail "F1a rejection: $OUT"
git -C "$REPO" reset -q --hard HEAD
pass "F1a unstaged role flip cannot commit SHARED-SKILLS.md"

# F1b: a dirty working-tree template is not the pristine stub
git -C "$REPO" rm -q local/shared/SHARED-SKILLS.md
OUT="$(cd "$REPO" && BOT_FLEET_UPGRADE=1 BOT_ROLE=manager git commit -qm "upgrade: drop for pristine attack" 2>&1)" && RC=0 || RC=$?
[ "$RC" = 0 ] || fail "could not drop the index: $OUT"
printf 'ARBITRARY TEMPLATE BYTES\n' > "$REPO/templates/local/shared/SHARED-SKILLS.md"
printf 'ARBITRARY TEMPLATE BYTES\n' > "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as manager ada "ada: fake pristine"
[ "$RC" != 0 ] || fail "dirty template authorized arbitrary bytes"
echo "$OUT" | grep -q 'builder-owned' || fail "F1b rejection: $OUT"
git -C "$REPO" reset -q --hard HEAD
git -C "$REPO" checkout -q -- templates/local/shared/SHARED-SKILLS.md
cp "$SRC/templates/local/shared/SHARED-SKILLS.md" "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
OUT="$(cd "$REPO" && BOT_FLEET_UPGRADE=1 BOT_NAME=ada BOT_ROLE=manager git commit -qm "upgrade: restore stub" 2>&1)" && RC=0 || RC=$?
[ "$RC" = 0 ] || fail "could not restore the stub: $OUT"
pass "F1b a dirty working-tree template cannot make arbitrary bytes pristine"

# S1: a retired builder is blocked. Status is read from HEAD, so commit the roster first.
python3 - "$REPO/local/fleet.json" <<'PY'
import json, sys
p = sys.argv[1]
fl = json.load(open(p))
for b in fl["bots"]:
    if b["slug"] == "forge":
        b["status"] = "retired"
json.dump(fl, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
git -C "$REPO" add -- local/fleet.json
commit_as manager ada "ada: retire forge"
[ "$RC" = 0 ] || fail "manager could not retire forge: $OUT"
echo 'retired builder edit' >> "$REPO/local/shared/SHARED-SKILLS.md"
git -C "$REPO" add -- local/shared/SHARED-SKILLS.md
commit_as builder forge "forge: shared index"
[ "$RC" != 0 ] || fail "retired builder was allowed to commit"
echo "$OUT" | grep -q 'builder-owned' || fail "S1 rejection: $OUT"
git -C "$REPO" reset -q --hard HEAD
python3 - "$REPO/local/fleet.json" <<'PY'
import json, sys
p = sys.argv[1]
fl = json.load(open(p))
for b in fl["bots"]:
    if b["slug"] == "forge":
        b["status"] = "active"
json.dump(fl, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
git -C "$REPO" add -- local/fleet.json
commit_as manager ada "ada: restore forge"
[ "$RC" = 0 ] || fail "manager could not restore forge: $OUT"
pass "S1 a retired builder cannot commit the shared index"

# sync.sh: a manager's default local/ add must not take the shared index.
# The shared edit stays unstaged, so rebase refuses to push (existing sync rule).
# The commit itself is only the manager's other local file.
echo 'builder via sync' >> "$REPO/local/shared/SHARED-SKILLS.md"
echo 'manager local note' >> "$REPO/local/overrides.md"
run env BOT_NAME=ada BOT_ROLE=manager "$REPO/fleet/scripts/sync.sh" "ada: local note"
[ "$RC" != 0 ] || fail "manager sync should not push while the shared index is dirty"
git -C "$REPO" show --name-only --format= HEAD | grep -q '^local/overrides.md$' || fail "manager sync missed overrides: $OUT"
git -C "$REPO" show --name-only --format= HEAD | grep -q 'SHARED-SKILLS.md' && fail "manager sync committed the shared index" || true
git -C "$REPO" diff --name-only | grep -q 'SHARED-SKILLS.md' || fail "manager sync lost the unstaged shared edit"
git -C "$REPO" push -q origin HEAD:main
run env BOT_NAME=forge BOT_ROLE=builder "$REPO/fleet/scripts/sync.sh" "forge: shared index"
[ "$RC" = 0 ] || fail "builder sync failed: $OUT"
git -C "$REPO" show --name-only --format= HEAD | grep -q '^local/shared/SHARED-SKILLS.md$' || fail "builder sync did not commit the index: $OUT"
pass "sync.sh: builder stages the shared index; manager default sync does not"

# S5: two owner classes fail audit, except the documented shared-skills path
AUDIT="$T/auditrepo"
mkdir -p "$AUDIT/fleet/scripts" "$AUDIT/local/shared" "$AUDIT/local"
cp "$SRC/fleet/scripts/owners.py" "$AUDIT/fleet/scripts/owners.py"
cp "$SRC/fleet/OWNERS.json" "$AUDIT/fleet/OWNERS.json"
printf 'index\n' > "$AUDIT/local/shared/SHARED-SKILLS.md"
printf 'note\n' > "$AUDIT/local/overrides.md"
git init -q -b main "$AUDIT"
git -C "$AUDIT" config user.email test@example.invalid
git -C "$AUDIT" config user.name test
git -C "$AUDIT" add -A
git -C "$AUDIT" commit -qm "audit base" --no-verify
(cd "$AUDIT" && python3 fleet/scripts/owners.py audit) || fail "documented shared-skills overlap should pass audit"
python3 - "$AUDIT/fleet/OWNERS.json" <<'PY'
import json, sys
p = sys.argv[1]
own = json.load(open(p))
own["rules"].insert(0, {"path": "local/extra.md", "owner": "template"})
json.dump(own, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
printf 'extra\n' > "$AUDIT/local/extra.md"
git -C "$AUDIT" add -A
git -C "$AUDIT" commit -qm "overlap" --no-verify
set +e
audit_out="$(cd "$AUDIT" && python3 fleet/scripts/owners.py audit 2>&1)"
audit_rc=$?
set -e
[ "$audit_rc" != 0 ] || fail "overlapping owners were not caught"
echo "$audit_out" | grep -q 'local/extra.md matches several owner classes' || fail "S5 message: $audit_out"
echo "$audit_out" | grep -q 'SHARED-SKILLS.md matches several' && fail "exception path was flagged: $audit_out" || true
pass "S5 audit fails two owner classes, except SHARED-SKILLS.md"

echo "test-check-actions: OK"
