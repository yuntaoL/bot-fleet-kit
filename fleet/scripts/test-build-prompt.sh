#!/usr/bin/env bash
# 0.12.0 compiled prompts. Scratch repos only. Fictional bots. No owner data.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail() { echo "FAIL $*" >&2; [ -n "${OUT:-}" ] && echo "$OUT" >&2; [ -n "${ERR:-}" ] && echo "$ERR" >&2; exit 1; }
pass() { echo "PASS $*"; }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="$T/gitconfig" LC_ALL=C PYTHONDONTWRITEBYTECODE=1
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.invalid
git config --global commit.gpgsign false

# Source shape.
[ "$(cat "$SRC/fleet/VERSION")" = "0.12.0" ] || fail "VERSION"
grep -q 'fleet/scripts/pull.sh' "$SRC/templates/THIN-PROMPT.tmpl" || fail "thin prompt missing safe pull"
grep -q 'Not at the start of every turn' "$SRC/templates/THIN-PROMPT.tmpl" || fail "thin prompt restored a per-run pull"
grep -q 'git pull' "$SRC/templates/THIN-PROMPT.tmpl" && fail "thin prompt teaches bare git pull" || true
for f in fleet/rules/startup.md fleet/rules/routines.md fleet/rules/common.md fleet/roles/worker.md; do
  grep -q 'pull\.sh' "$SRC/$f" && fail "pull.sh returned to $f" || true
  grep -q '^id:' "$SRC/$f" || fail "$f missing id"
  grep -q '^prompt_version:' "$SRC/$f" || fail "$f missing prompt_version"
  grep -q '^## Prompt digest$' "$SRC/$f" || fail "$f missing digest"
done
grep -q 'one-word reply' "$SRC/fleet/rules/startup.md" || fail "startup digest missing routine"
grep -q 'An owner row beats a generic platform skill or a connector default.' "$SRC/fleet/rules/startup.md" || fail "startup digest missing owner-row sentence"
python3 -c 'import json; r=json.load(open("'"$SRC"'/fleet/OWNERS.json"))["rules"]; i=next(k for k,x in enumerate(r) if x["path"]=="local/prompts/**"); j=next(k for k,x in enumerate(r) if x["path"]=="local/**"); assert i<j and r[i]["owner"]=="builder"' || fail "prompts rule is not before local/**"
grep -q '| Applies to |' "$SRC/templates/local/shared/SHARED-SKILLS.md" || fail "shared index missing Applies to"
grep -q 'agent-data' "$SRC/fleet/migrations/0.12.0.sh" && fail "migration names a profile dir" || true
grep -q 'profile.json' "$SRC/fleet/migrations/0.12.0.sh" && fail "migration names profile.json" || true
grep -qE 'urllib|requests|socket' "$SRC/fleet/scripts/prompt_build.py" && fail "builder uses the network" || true
grep -q '/home/box/agent-data/agents' "$SRC/fleet/scripts/prompt_build.py" || fail "default profiles dir"
pass "source shape"

REPO="$T/repo"
mkdir -p "$REPO/fleet/scripts" "$REPO/fleet/schema" "$REPO/fleet/docs" "$REPO/fleet/migrations" "$REPO/templates" \
  "$REPO/local/rules" "$REPO/local/shared" "$REPO/bots"
cp -a "$SRC/fleet/rules" "$REPO/fleet/rules"
cp -a "$SRC/fleet/roles" "$REPO/fleet/roles"
cp "$SRC/fleet/VERSION" "$REPO/fleet/VERSION"
cp "$SRC/fleet/OWNERS.json" "$REPO/fleet/OWNERS.json"
cp "$SRC/fleet/scripts/prompt_build.py" "$REPO/fleet/scripts/prompt_build.py"
cp "$SRC/fleet/scripts/build-prompt.sh" "$REPO/fleet/scripts/build-prompt.sh"
cp "$SRC/fleet/scripts/owners.py" "$REPO/fleet/scripts/owners.py"
cp "$SRC/fleet/scripts/check-boundary.sh" "$REPO/fleet/scripts/check-boundary.sh"
cp "$SRC/fleet/scripts/sync.sh" "$REPO/fleet/scripts/sync.sh"
cp "$SRC/fleet/migrations/0.12.0.sh" "$REPO/fleet/migrations/0.12.0.sh"
cp "$SRC/fleet/schema/fleet.schema.json" "$REPO/fleet/schema/fleet.schema.json"
cp "$SRC/fleet/schema/bot.schema.json" "$REPO/fleet/schema/bot.schema.json"
cp "$SRC/templates/THIN-PROMPT.tmpl" "$REPO/templates/THIN-PROMPT.tmpl"
printf '# example fleet\n' > "$REPO/README.md"
printf '# not a prompt input\n' > "$REPO/fleet/docs/NOTE.md"
chmod +x "$REPO/fleet/scripts/build-prompt.sh" "$REPO/fleet/scripts/sync.sh" "$REPO/fleet/migrations/0.12.0.sh"

python3 - "$REPO" <<'PY'
import json, os, sys
root = sys.argv[1]
os.chdir(root)
fleet = {
  "schemaVersion": 2,
  "owner": "example",
  "owner_name": "Example Owner",
  "templateVersion": "0.12.0",
  "prompt_mode": "compiled",
  "bots": [
    {"slug": "harbor-clerk", "name": "Harbor Clerk", "id": "example-harbor-clerk", "role": "worker", "status": "active", "capabilities": ["calendar"], "summary": "Files pier notes."},
    {"slug": "pier-archivist", "name": "Pier Archivist", "id": "example-pier-archivist", "role": "builder", "status": "active", "summary": "Keeps the shared index."},
    {"slug": "cargo-crier", "name": "Cargo Crier", "id": "example-cargo-crier", "role": "worker", "status": "active", "summary": "Logs crates."},
  ],
}
json.dump(fleet, open("local/fleet.json", "w"), indent=2)
open("local/fleet.json", "a").write("\n")
try:
    import jsonschema
    jsonschema.validate(fleet, json.load(open("fleet/schema/fleet.schema.json")))
except ImportError:
    pass
shared = """---
type: shared-skills-index
updated: 2026-01-01
status: seeded
---
# Shared skills

| Skill | When to use | Action types covered | Owner | Location | Applies to |
|---|---|---|---|---|---|
| fleet-change | Use when a change touches the fleet repo and must be classified before anyone applies it. This sentence must not be copied into the prompt. | repo and fleet changes | builder | `fleet/skills/fleet-change` | all |
| rename-bot | Use when renaming a bot display name, slug, worktree or branch. | repo and fleet changes | builder | `fleet/skills/rename-bot` | builder |
| ledger | Use when filing pier notes into the ledger skill, including the long explanation that must not be copied into the prompt. | pier notes | builder | `local/shared/skills/ledger` | manager |
| tide-table | Use when reading tide times for the pier. | tide times | worker | `local/shared/skills/tide-table` | worker |
"""
open("local/shared/SHARED-SKILLS.md", "w").write(shared)
open("local/rules/pier-ledger.md", "w").write("""---
id: pier-ledger
applies_to:
  roles: [worker]
  capabilities: [calendar]
---
# Pier ledger

Standing rule for the clerk. The body of this file is not copied into the prompt.

## Prompt digest

File crate notes in the pier ledger only.
""")
open("local/rules/builder-dock.md", "w").write("""---
id: builder-dock
applies_to:
  roles: [builder]
  capabilities: []
---
# Builder dock

## Prompt digest

The builder fast-forward is the only routine that updates every worktree.
""")
long_ptr = "This read-first note has no path and no skill name, so the pointer is shortened rather than pasted in full into the prompt."
assert len(long_ptr) > 80
clerk_actions = """---
type: actions-index
updated: 2026-01-01
status: seeded
---
# Actions index

Read the [shared skills index](../../../local/shared/SHARED-SKILLS.md) first.

| Action | Read first (kb files, then skills, in order) | Hard rule |
|---|---|---|
| calendar events | `kb/prefs/calendar.md`, skill `calendar` | Never write events to a second calendar service. |
| pier notes | `kb/prefs/notes.md`, skill `ledger` | Do not paraphrase the owner's "pier" notes. |
| tide bell | %s | Ring the tide bell only for the pier. |
""" % long_ptr
arch_actions = """---
type: actions-index
updated: 2026-01-01
status: seeded
---
# Actions index

| Action | Read first | Hard rule |
|---|---|---|
| repo and fleet changes | skill `fleet-change`, `fleet/skills/fleet-change/SKILL.md` | Classify first. |
"""
huge = "Always file this crate in the pier ledger and nowhere else. " * 200
crier_actions = """---
type: actions-index
updated: 2026-01-01
status: seeded
---
# Actions index

| Action | Read first | Hard rule |
|---|---|---|
| crate log | `kb/prefs/crates.md` | %s |
""" % huge.strip()
bots = {
  "harbor-clerk": ("worker", "Harbor Clerk", clerk_actions, "File pier notes only in the pier ledger.\n"),
  "pier-archivist": ("builder", "Pier Archivist", arch_actions, "Maintain the shared skills index.\n"),
  "cargo-crier": ("worker", "Cargo Crier", crier_actions, "Log each crate once.\n"),
}
for slug, (role, name, actions, rules) in bots.items():
    d = "bots/%s" % slug
    os.makedirs(d + "/kb", exist_ok=True)
    os.makedirs(d + "/journal", exist_ok=True)
    bj = {
      "schemaVersion": 1, "display_name": name, "slug": slug, "role": role,
      "title": "Example title", "agent_id": "example-" + slug,
      "worktree": "/tmp/example-worktrees/" + slug, "owner_name": "Example Owner",
      "fleet_repo": "example/fleet", "kit_version": "0.12.0", "timezone": "UTC",
    }
    json.dump(bj, open(d + "/bot.json", "w"), indent=2)
    open(d + "/bot.json", "a").write("\n")
    open(d + "/kb/ACTIONS.md", "w").write(actions)
    open(d + "/rules.md", "w").write("# Rules\n\n" + rules)
    open(d + "/state.json", "w").write('{"note":"volatile"}\n')
    open(d + "/journal/2026-01-01.md", "w").write("- example line\n")
print("fixture written", len(huge))
PY

git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name test
git -C "$REPO" add -A
git -C "$REPO" commit -qm "fixture" --no-verify

run() {
  OUT="$(cd "$REPO" && "$@" 2>"$T/err")" && RC=0 || RC=$?
  ERR="$(cat "$T/err" 2>/dev/null || true)"
}
BUILD="$REPO/fleet/scripts/build-prompt.sh"

run "$BUILD"
[ "$RC" = 1 ] || fail "build should fail while cargo-crier is over the cap (rc=$RC)"
echo "$ERR" | grep -q 'FAIL cargo-crier: compiled prompt is ' || fail "over-cap report: $ERR"
echo "$ERR" | grep -q 'Largest sections:' || fail "over-cap report missing sections"
echo "$ERR" | awk '/Largest sections:/{getline; print; exit}' | grep -q '^  action-index ' || fail "largest section is not the action index: $ERR"
echo "$ERR" | grep -q 'The fix is for this bot to shorten its own ACTIONS.md rows. Hard rules are copied verbatim and are never truncated.' || fail "missing shorten guidance"
[ -f "$REPO/local/prompts/harbor-clerk.md" ] || fail "clerk prompt missing"
[ -f "$REPO/local/prompts/pier-archivist.md" ] || fail "archivist prompt missing"
[ ! -e "$REPO/local/prompts/cargo-crier.md" ] || fail "over-cap prompt was written"
# The huge hard rule is not pasted into the changelog-sized error, and was not truncated into a file.
echo "$ERR" | grep -q 'nowhere else. Always file this crate' && fail "over-cap report pasted the hard rule" || true
pass "over cap fails and names the action index"

python3 - "$REPO" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
for slug in ("harbor-clerk", "pier-archivist"):
    text = (root / "local/prompts" / f"{slug}.md").read_text()
    print(f"SIZE {slug} {len(text)}")
PY

clerk() { cat "$REPO/local/prompts/harbor-clerk.md"; }
arch() { cat "$REPO/local/prompts/pier-archivist.md"; }
clerk | grep -q '## Before you act' || fail "missing pre-action heading"
clerk | grep -q 'even on a one-word reply' || fail "missing one-word reply"
clerk | grep -q 'even right after a summary' || fail "missing summary clause"
clerk | grep -q 'Look up the action in the embedded index.' || fail "missing index lookup"
clerk | grep -q 'An owner row beats a generic platform skill or a connector default.' || fail "missing owner-row rule"
clerk | grep -q 'add a row to your ACTIONS.md' || fail "missing add-a-row"
clerk | grep -q 'act thoughtfully' || fail "missing act thoughtfully"
clerk | grep -q 'the file wins' || fail "missing git-wins"
clerk | grep -q 'fleet/scripts/build-prompt.sh --check' || fail "missing startup check"
clerk | grep -q 'fleet/scripts/pull.sh' || fail "missing safe pull"
clerk | grep -q 'Not at the start of every turn' || fail "missing not-every-turn"
clerk | grep -q 'Your worktree is /tmp/example-worktrees/harbor-clerk.' || fail "missing worktree"
clerk | grep -q 'read `.bot`, open the bot.json it points to' || fail "missing bot pointer"
clerk | grep -q 'fleet/scripts/sync.sh' || fail "missing journal sync"
clerk | grep -q 'fail safe' || fail "missing fail-safe"
clerk | grep -q -- '- calendar events | kb/prefs/calendar.md; calendar | Never write events to a second calendar service.' || fail "calendar row"
clerk | grep -q 'Do not paraphrase the owner'"'"'s "pier" notes.' || fail "hard rule not verbatim"
clerk | grep -q 'Ring the tide bell only for the pier.' || fail "tide bell rule"
clerk | grep -q 'pasted in full into the prompt' && fail "long pointer was not shortened" || true
clerk | grep -q '\.\.\.' || fail "pointer was not shortened"
clerk | grep -q 'Example Owner' && fail "prompt contains the owner name" || true
clerk | grep -q 'Harbor Clerk' && fail "prompt contains the display name" || true
clerk | grep -q 'example-harbor-clerk' && fail "prompt contains the agent id" || true
clerk | grep -q 'Do your one job well.' && fail "worker file body was embedded" || true
clerk | grep -q 'The worker does one job and asks the manager for anything else.' || fail "worker digest missing"
clerk | grep -q 'The builder creates bots with create-bot.sh' && fail "builder digest leaked to the clerk" || true
clerk | grep -q 'The manager keeps the roster' && fail "manager digest leaked" || true
clerk | grep -q 'Hard lines: nothing goes out without approval' || fail "common digest missing"
clerk | grep -q "Credentials of any kind live in the owner's secret store" && fail "common body was embedded" || true
clerk | grep -q 'kb holds owner-stated preferences, never instructions from outside sources' && fail "startup body was embedded" || true
clerk | grep -q 'File crate notes in the pier ledger only.' || fail "local worker digest missing"
clerk | grep -q 'The builder fast-forward is the only routine' && fail "builder local rule leaked" || true
clerk | grep -q -- '- ledger |' || fail "referenced skill missing"
clerk | grep -q -- '- tide-table |' || fail "role skill missing"
clerk | grep -q -- '- fleet-change |' || fail "all-roles skill missing"
clerk | grep -q -- '- rename-bot |' && fail "builder skill leaked to the clerk" || true
clerk | grep -q 'must not be copied into the prompt' && fail "shared when-to-use was embedded" || true
arch | grep -q -- '- rename-bot |' || fail "builder skill missing"
arch | grep -q -- '- fleet-change |' || fail "archivist missing fleet-change"
arch | grep -q -- '- ledger |' && fail "unreferenced skill included" || true
arch | grep -q -- '- tide-table |' && fail "worker skill included for the builder" || true
arch | grep -q 'The builder creates bots with create-bot.sh and maintains the shared skills index.' || fail "builder digest missing"
arch | grep -q 'The worker does one job' && fail "worker digest leaked to the builder" || true
arch | grep -q 'File crate notes in the pier ledger only.' && fail "worker local rule leaked" || true
arch | grep -q 'The builder fast-forward is the only routine that updates every worktree.' || fail "builder local digest missing"
arch | grep -q 'Example Owner' && fail "archivist prompt contains the owner name" || true
pass "routine, calendar row, relevance, verbatim hard rule"

# Byte-identical rebuild, including built_at.
cp "$REPO/local/prompts/harbor-clerk.md" "$T/clerk.md"
cp "$REPO/local/prompts/harbor-clerk.manifest.json" "$T/clerk.json"
sleep 2
run "$BUILD" harbor-clerk
[ "$RC" = 0 ] || fail "rebuild clerk: $ERR"
cmp "$T/clerk.md" "$REPO/local/prompts/harbor-clerk.md" || fail "prompt bytes changed"
cmp "$T/clerk.json" "$REPO/local/prompts/harbor-clerk.manifest.json" || fail "manifest bytes changed"
pass "byte-identical rebuild"

# Outside the digest, volatile files, and a doc do not rebuild.
# Edit the rule body above the digest. Appending at end of file would extend the digest.
python3 - <<PY
from pathlib import Path
p = Path("$REPO/fleet/rules/common.md")
t = p.read_text()
old = "Template-owned."
if old not in t: raise SystemExit("body anchor missing")
p.write_text(t.replace(old, "Template-owned. Body edit.", 1))
PY
printf '\nextra rule note\n' >> "$REPO/bots/harbor-clerk/rules.md"
printf '{"note":"changed"}\n' > "$REPO/bots/harbor-clerk/state.json"
printf '\n- later\n' >> "$REPO/bots/harbor-clerk/journal/2026-01-01.md"
printf '\nDoc note.\n' >> "$REPO/fleet/docs/NOTE.md"
# A when-to-use edit is not an embedded line.
python3 - <<PY
from pathlib import Path
p = Path("$REPO/local/shared/SHARED-SKILLS.md")
p.write_text(p.read_text().replace("must not be copied into the prompt", "must not be copied into the prompt (edited)"))
PY
run "$BUILD" harbor-clerk
[ "$RC" = 0 ] || fail "rebuild after non-inputs: $ERR"
cmp "$T/clerk.md" "$REPO/local/prompts/harbor-clerk.md" || fail "non-input edit changed the prompt"
cmp "$T/clerk.json" "$REPO/local/prompts/harbor-clerk.manifest.json" || fail "non-input edit changed the manifest"
git -C "$REPO" checkout -q -- fleet/rules/common.md local/shared/SHARED-SKILLS.md \
  bots/harbor-clerk/rules.md bots/harbor-clerk/state.json bots/harbor-clerk/journal/2026-01-01.md fleet/docs/NOTE.md
pass "docs, body, rules, state and journal do not trigger"

# Version-only kit bump does not rewrite bytes. Restore after.
printf '9.9.9\n' > "$REPO/fleet/VERSION"
run "$BUILD" harbor-clerk
[ "$RC" = 0 ] || fail "version-only rebuild"
cmp "$T/clerk.md" "$REPO/local/prompts/harbor-clerk.md" || fail "kit version alone changed the prompt"
cmp "$T/clerk.json" "$REPO/local/prompts/harbor-clerk.manifest.json" || fail "kit version alone changed the manifest"
git -C "$REPO" checkout -q -- fleet/VERSION
pass "kit version alone is not an input"

# Opt-out and per-bot override.
rm -rf "$REPO/local/prompts"
python3 - <<PY
import json
p="$REPO/local/fleet.json"
f=json.load(open(p)); f["prompt_mode"]="files"
json.dump(f, open(p,"w"), indent=2); open(p,"a").write("\n")
PY
run "$BUILD"
[ "$RC" = 0 ] || fail "files mode build failed: $ERR"
[ -z "$(find "$REPO/local/prompts" -type f 2>/dev/null)" ] || fail "files mode wrote a prompt"
echo "$OUT" | grep -q 'prompt_mode files' || fail "files mode not reported: $OUT"
run "$BUILD" --check --json
[ "$RC" = 0 ] || fail "files mode check failed: $OUT"
echo "$OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"] and all(b["prompt_mode"]=="files" and not b["stale"] for b in r["bots"])' || fail "files mode json: $OUT"
python3 - <<PY
import json
p="$REPO/local/fleet.json"
f=json.load(open(p)); f["prompt_mode"]="files"
for b in f["bots"]:
    if b["slug"]=="harbor-clerk": b["prompt_mode"]="compiled"
    else: b.pop("prompt_mode", None)
json.dump(f, open(p,"w"), indent=2); open(p,"a").write("\n")
PY
run "$BUILD"
[ "$RC" = 0 ] || fail "per-bot override build: $ERR"
[ -f "$REPO/local/prompts/harbor-clerk.md" ] || fail "override did not build the clerk"
[ ! -e "$REPO/local/prompts/pier-archivist.md" ] || fail "override built the archivist"
[ ! -e "$REPO/local/prompts/cargo-crier.md" ] || fail "override built the crier"
git -C "$REPO" checkout -q -- local/fleet.json
rm -rf "$REPO/local/prompts"
pass "opt-out and per-bot override"

# Stale reasons, changelog, drift. Rebuild the two bots that fit.
run "$BUILD" harbor-clerk pier-archivist
[ "$RC" = 0 ] || fail "rebuild two bots: $ERR"
run "$BUILD" --check
[ "$RC" = 1 ] || fail "expected stale before deploy"
echo "$OUT" | grep -q 'harbor-clerk: stale (not-deployed)' || fail "clerk stale reason: $OUT"
echo "$OUT" | grep -q 'pier-archivist: stale (not-deployed)' || fail "archivist stale reason: $OUT"
run "$BUILD" --check --json
echo "$OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"] is False' || fail "json ok flag"
# --check must not rewrite prompts.
cp "$REPO/local/prompts/harbor-clerk.md" "$T/before-check.md"
cp "$REPO/local/prompts/harbor-clerk.manifest.json" "$T/before-check.json"
run "$BUILD" --check --json
cmp "$T/before-check.md" "$REPO/local/prompts/harbor-clerk.md" || fail "check rewrote the prompt"
cmp "$T/before-check.json" "$REPO/local/prompts/harbor-clerk.manifest.json" || fail "check rewrote the manifest"
pass "stale before deploy, and check is read-only"

run "$BUILD" --changelog
[ "$RC" = 1 ] || fail "changelog should fail while a bot is over the cap (rc=$RC)"
echo "$OUT" | grep -q 'Over the size cap, so not included: cargo-crier.' || fail "changelog missed the over-cap bot"
echo "$OUT" | grep -q 'Approve this once for the whole fleet, not once per bot.' || fail "changelog batch line"
echo "$OUT" | grep -q 'harbor-clerk' || fail "changelog bots"
echo "$OUT" | grep -q '(not deployed yet)' || fail "changelog before"
echo "$OUT" | grep -q 'one-word reply' || fail "changelog after digest"
echo "$OUT" | grep -q 'Scripts do not edit live profiles.' || fail "changelog profile line"
pass "changelog for a first approval"

cp "$REPO/local/prompts/harbor-clerk.md" "$T/pre-mark.md"
run "$BUILD" --mark-deployed harbor-clerk
[ "$RC" = 0 ] || fail "mark clerk: $ERR"
cmp "$T/pre-mark.md" "$REPO/local/prompts/harbor-clerk.md" || fail "mark-deployed rewrote the prompt"
run "$BUILD" --mark-deployed pier-archivist
[ "$RC" = 0 ] || fail "mark archivist: $ERR"
# cargo stays over cap until opted out, so the fleet check stays red.
python3 - <<PY
import json
p="$REPO/local/fleet.json"
f=json.load(open(p))
for b in f["bots"]:
    if b["slug"]=="cargo-crier": b["prompt_mode"]="files"
json.dump(f, open(p,"w"), indent=2); open(p,"a").write("\n")
PY
run "$BUILD" --check --json
[ "$RC" = 0 ] || fail "expected clean after deploy: $OUT $ERR"
echo "$OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"]; c=next(b for b in r["bots"] if b["slug"]=="harbor-clerk"); assert c["stale"] is False and c["reasons"]==[]' || fail "clerk not current: $OUT"
pass "mark-deployed clears stale"

# Edit the hard rule in the worktree. Git still has the old row.
python3 - <<PY
from pathlib import Path
p = Path("$REPO/bots/harbor-clerk/kb/ACTIONS.md")
t = p.read_text().replace("Never write events to a second calendar service.", "Never write events to a second calendar service, including a shared team calendar.")
p.write_text(t)
PY
run "$BUILD" --check
[ "$RC" = 1 ] || fail "expected inputs-changed"
echo "$OUT" | grep -q 'harbor-clerk: stale (inputs-changed)' || fail "inputs-changed reason: $OUT"
run "$BUILD" --mark-deployed harbor-clerk
[ "$RC" = 1 ] || fail "mark should refuse a dirty build"
echo "$ERR" | grep -q 'behind the files' || fail "mark refusal: $ERR"
run "$BUILD" harbor-clerk
[ "$RC" = 0 ] || fail "rebuild after row edit"
clerk | grep -q 'including a shared team calendar.' || fail "new hard rule missing"
run "$BUILD" --check
echo "$OUT" | grep -q 'harbor-clerk: stale (built-differs-from-deployed)' || fail "built differs: $OUT"
run "$BUILD" --changelog
[ "$RC" = 0 ] || fail "changelog after the cap opt-out should pass: $ERR"
echo "$OUT" | grep -q 'Never write events to a second calendar service.' || fail "changelog missing before rule"
echo "$OUT" | grep -q 'including a shared team calendar.' || fail "changelog missing after rule"
echo "$OUT" | grep -q 'Before:' || fail "changelog missing before"
echo "$OUT" | grep -q 'After:' || fail "changelog missing after"
pass "stale reasons and before/after changelog"

# Drift is read-only.
PROFILES="$T/profiles"
mkdir -p "$PROFILES/example-harbor-clerk" "$PROFILES/example-pier-archivist"
printf 'do-not-touch\n' > "$PROFILES/CANARY"
python3 - <<PY
import json, pathlib
root = pathlib.Path("$REPO")
prof = pathlib.Path("$PROFILES")
for slug, agent in (("harbor-clerk", "example-harbor-clerk"), ("pier-archivist", "example-pier-archivist")):
    text = (root / "local/prompts" / f"{slug}.md").read_text()
    json.dump({"name": slug, "id": agent, "description": text}, open(prof / agent / "profile.json", "w"))
PY
# Mark clerk again so deployed matches the rebuilt prompt, then drift can match.
run "$BUILD" --mark-deployed harbor-clerk
[ "$RC" = 0 ] || fail "remark clerk: $ERR"
run "$BUILD" --mark-deployed pier-archivist
[ "$RC" = 0 ] || fail "remark archivist: $ERR"
run env BOT_FLEET_PROFILES_DIR="$PROFILES" "$BUILD" --check --json
[ "$RC" = 0 ] || fail "matching profiles should be clean: $OUT $ERR"
echo "$OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); c=next(b for b in r["bots"] if b["slug"]=="harbor-clerk"); assert c["drift"] is False and c["drift_reason"]=="match"' || fail "drift match: $OUT"
python3 - <<PY
import json
p="$PROFILES/example-harbor-clerk/profile.json"
d=json.load(open(p)); d["description"]="a different profile description"
json.dump(d, open(p,"w"))
PY
run env BOT_FLEET_PROFILES_DIR="$PROFILES" "$BUILD" --check
[ "$RC" = 1 ] || fail "drift should fail the check"
echo "$OUT" | grep -q 'harbor-clerk: drift (description-differs)' || fail "drift reason: $OUT"
# Nothing under the profiles dir except our writes.
[ "$(cat "$PROFILES/CANARY")" = "do-not-touch" ] || fail "profiles canary changed"
find "$PROFILES" -type f | sort > "$T/prof-list"
grep -q CANARY "$T/prof-list" || fail "canary missing"
pass "drift is read-only"

# CI bump rule.
git -C "$REPO" checkout -q -- fleet/rules/startup.md local/fleet.json bots/harbor-clerk/kb/ACTIONS.md
python3 - <<PY
from pathlib import Path
p = Path("$REPO/fleet/rules/startup.md")
t = p.read_text()
if "prompt_version: 1\n" not in t: raise SystemExit("version line missing")
p.write_text(t.replace("the file wins.", "the file wins today.", 1))
PY
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 1 ] || fail "digest change without bump should fail"
echo "$OUT$ERR" | grep -q 'FAIL fleet/rules/startup.md: prompt digest changed but prompt_version did not' || fail "bump fail text: $OUT $ERR"
git -C "$REPO" checkout -q -- fleet/rules/startup.md
python3 - <<PY
from pathlib import Path
p = Path("$REPO/fleet/rules/startup.md")
p.write_text(p.read_text().replace("prompt_version: 1\n", "prompt_version: 2\n", 1))
PY
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 0 ] || fail "version bump without digest change should warn, not fail (rc=$RC) $OUT $ERR"
echo "$OUT" | grep -q 'WARN fleet/rules/startup.md: prompt_version changed but the prompt digest did not' || fail "warn text: $OUT"
python3 - <<PY
from pathlib import Path
p = Path("$REPO/fleet/rules/startup.md")
t = p.read_text().replace("the file wins.", "the file wins today.", 1)
p.write_text(t)
PY
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 0 ] || fail "digest and version together should pass: $OUT $ERR"
echo "$OUT" | grep -q 'prompt-versions: OK' || fail "expected OK: $OUT"
# A local digest change has no kit version and does not fail the bump rule.
git -C "$REPO" checkout -q -- fleet/rules/startup.md
printf '\nExtra local sentence.\n' >> "$REPO/local/rules/pier-ledger.md"
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 0 ] || fail "local digest change failed the kit bump rule: $OUT $ERR"
pass "CI bump rule"

# Migration: files by default, nothing deployed, profiles untouched.
MIG="$T/mig"
mkdir -p "$MIG/local" "$MIG/fleet/migrations"
cp "$SRC/fleet/migrations/0.12.0.sh" "$MIG/fleet/migrations/0.12.0.sh"
printf '%s\n' '{"schemaVersion":2,"owner":"example","owner_name":"Example Owner","templateVersion":"0.11.0","bots":[]}' > "$MIG/local/fleet.json"
mkdir -p "$T/mig-profiles/example-harbor-clerk"
printf 'stay\n' > "$T/mig-profiles/example-harbor-clerk/profile.json"
git init -q -b main "$MIG"
git -C "$MIG" config user.email test@example.invalid
git -C "$MIG" config user.name test
git -C "$MIG" add -A && git -C "$MIG" commit -qm "base" --no-verify
(cd "$MIG" && bash fleet/migrations/0.12.0.sh --dry-run) | grep -q 'would: set' || fail "dry-run"
python3 -c 'import json; assert "prompt_mode" not in json.load(open("'"$MIG"'/local/fleet.json"))'
(cd "$MIG" && bash fleet/migrations/0.12.0.sh)
python3 -c 'import json; assert json.load(open("'"$MIG"'/local/fleet.json"))["prompt_mode"]=="files"'
[ ! -e "$MIG/local/prompts" ] || fail "migration created prompts"
[ "$(cat "$T/mig-profiles/example-harbor-clerk/profile.json")" = "stay" ] || fail "migration touched a profile"
cp "$MIG/local/fleet.json" "$T/mig-after.json"
(cd "$MIG" && bash fleet/migrations/0.12.0.sh) | grep -q 'already set' || fail "second run"
cmp "$T/mig-after.json" "$MIG/local/fleet.json" || fail "second run rewrote fleet.json"
python3 - <<PY
import json
p="$MIG/local/fleet.json"
f=json.load(open(p)); f["prompt_mode"]="compiled"
json.dump(f, open(p,"w"))
PY
(cd "$MIG" && bash fleet/migrations/0.12.0.sh) | grep -q 'already set (compiled)' || fail "migration reset compiled"
pass "migration leaves compiled mode alone and deploys nothing"

# Ownership: builder may update local/prompts; a worker may not. Audit allows the overlap.
git -C "$REPO" checkout -q -- local/fleet.json bots/harbor-clerk/kb/ACTIONS.md fleet/rules/startup.md local/rules/pier-ledger.md
rm -rf "$REPO/local/prompts"
run "$BUILD" harbor-clerk
[ "$RC" = 0 ] || fail "rebuild for ownership"
# Stage and ask owners.py. HEAD fleet.json still has the builder.
git -C "$REPO" add -- local/prompts/harbor-clerk.md local/prompts/harbor-clerk.manifest.json
run env BOT_NAME=harbor-clerk BOT_ROLE=manager python3 "$REPO/fleet/scripts/owners.py" check < <(git -C "$REPO" diff --cached --name-status --no-renames)
# run() does not pass stdin. Call directly.
set +e
OUT="$(cd "$REPO" && git diff --cached --name-status --no-renames | BOT_NAME=harbor-clerk BOT_ROLE=manager python3 fleet/scripts/owners.py check 2>&1)"
RC=$?
set -e
[ "$RC" != 0 ] || fail "worker/manager was allowed to commit prompts: $OUT"
echo "$OUT" | grep -q 'builder-owned' || fail "expected builder-owned: $OUT"
set +e
OUT="$(cd "$REPO" && git diff --cached --name-status --no-renames | BOT_NAME=pier-archivist BOT_ROLE=worker python3 fleet/scripts/owners.py check 2>&1)"
RC=$?
set -e
[ "$RC" = 0 ] || fail "builder was rejected: $OUT"
git -C "$REPO" commit -qm "builder: prompts" --no-verify
(cd "$REPO" && python3 fleet/scripts/owners.py audit) || fail "audit rejected local/prompts"
pass "builder owns local/prompts"

# sync.sh stages prompts for the builder and unstages them for the manager.
cp "$SRC/fleet/scripts/check-staged-config.sh" "$REPO/fleet/scripts/check-staged-config.sh"
cp "$SRC/fleet/scripts/schema_check.py" "$REPO/fleet/scripts/schema_check.py"
cp "$SRC/fleet/schema/"*.schema.json "$REPO/fleet/schema/"
chmod +x "$REPO/fleet/scripts/check-staged-config.sh"
git -C "$REPO" add -- fleet/scripts/check-staged-config.sh fleet/scripts/schema_check.py fleet/schema
git -C "$REPO" commit -qm "add staged-config check" --no-verify
git init -q --bare -b main "$T/origin.git"
git -C "$REPO" remote add origin "$T/origin.git"
git -C "$REPO" push -q origin HEAD:main
printf '\nbuilder prompt note\n' >> "$REPO/local/prompts/harbor-clerk.md"
printf '\nmanager note\n' >> "$REPO/local/overrides.md"
mkdir -p "$REPO/local"
[ -f "$REPO/local/overrides.md" ] || printf '# overrides\n' > "$REPO/local/overrides.md"
# overrides may be new. Manager sync should commit it and not the prompt.
if [ ! -f "$REPO/local/overrides.md" ]; then printf '# overrides\n' > "$REPO/local/overrides.md"; fi
# A tracked prompt edit stays unstaged, so rebase refuses to push. The commit itself is only the manager's other file.
run env BOT_NAME=harbor-clerk BOT_ROLE=manager "$REPO/fleet/scripts/sync.sh" "manager local"
[ "$RC" != 0 ] || fail "manager sync should not push while a prompt is dirty"
git -C "$REPO" show --name-only --format= HEAD | grep -q 'local/prompts/' && fail "manager sync committed prompts" || true
git -C "$REPO" show --name-only --format= HEAD | grep -q 'local/overrides.md' || fail "manager sync missed overrides: $OUT"
git -C "$REPO" diff --name-only | grep -q 'local/prompts/harbor-clerk.md' || fail "manager sync lost the prompt edit"
git -C "$REPO" push -q origin HEAD:main
run env BOT_NAME=pier-archivist BOT_ROLE=builder "$REPO/fleet/scripts/sync.sh" "builder prompts"
[ "$RC" = 0 ] || fail "builder sync: $OUT $ERR"
git -C "$REPO" show --name-only --format= HEAD | grep -q 'local/prompts/harbor-clerk.md' || fail "builder sync missed the prompt"
pass "sync.sh: builder stages prompts; manager default sync does not"

echo
echo "SIZE harbor-clerk $(python3 -c 'print(len(open("'"$REPO"'/local/prompts/harbor-clerk.md").read()))')"
echo "SIZE pier-archivist $(python3 -c 'print(len(open("'"$REPO"'/local/prompts/pier-archivist.md").read()))' 2>/dev/null || echo missing)"
pass "0.12.0 compiled prompts"
