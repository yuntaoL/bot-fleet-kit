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
export BOT_FLEET_PROFILES_DIR="$T/no-profiles"
mkdir -p "$BOT_FLEET_PROFILES_DIR"
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.invalid
git config --global commit.gpgsign false

# Source shape.
[ "$(cat "$SRC/fleet/VERSION")" = "0.12.1" ] || fail "VERSION"
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
grep -F -q '4. If no row exists, act thoughtfully: do the reversible part, and before anything irreversible (send, buy, book, post, delete) stop and ask the owner; when the same ask repeats, add a row to your ACTIONS.md.' "$SRC/fleet/rules/startup.md" || fail "startup digest missing step 4"
grep -q 'kb/INDEX.md' "$SRC/fleet/rules/startup.md" || fail "startup digest missing re-read list"
grep -F -q 'Look up the action in the embedded index and in Shared skills.' "$SRC/fleet/rules/startup.md" || fail "startup digest missing shared-skills lookup"
grep -F -q 'At the start of a run, and again after a summary, re-read kb/INDEX.md' "$SRC/fleet/rules/startup.md" || fail "re-read is not limited to the start of a run and a summary"
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
cp "$SRC/fleet/scripts/schema_check.py" "$REPO/fleet/scripts/schema_check.py"
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
import os, sys
sys.path.insert(0, sys.argv[1] + "/fleet/scripts")
import prompt_build as pb
cell = pb.pad_strip(" Keep the end   ")
assert cell == "Keep the end  ", repr(cell)
try:
    pb.split_cells("| Keep the end \\|")
    raise SystemExit("escaped pipe compiled")
except ValueError as e:
    assert "closing pipe" in str(e), e
text = """| Generic skill it overrides | Action | Read first |
|---|---|---|
| platform calendar | calendar events | `kb/prefs/calendar.md` |
"""
rows, prefs = pb.skill_rows(text)
assert rows == [], rows
assert prefs and prefs[0]["cells"][0] == "platform calendar", prefs
bad = """| Skill | Location |
|---|---|
| Not A Skill | `fleet/skills/nope` |
"""
try:
    pb.skill_rows(bad)
    raise SystemExit("bad skill id was kept")
except ValueError as e:
    assert "skill id" in str(e), e
own = pb.over_cap_report("y", 9000, 8000, [("thin", "t" * 1000), ("shared-skills", "s" * 2000), ("action-index", "a" * 6000)], [])
assert "Cut this bot's own action index: cut 1000 characters, or ask the owner about the cap." in own, own
assert "Do not trim" not in own, own
tie = pb.over_cap_report("z", 9000, 8000, [("thin", "t" * 1000), ("shared-skills", "s" * 4000), ("action-index", "a" * 4000)], [])
assert "Cut the shared skills: cut 1000 characters, or ask the owner about the cap." in tie, tie
assert "Cut this bot's own action index" not in tie, tie
try:
    pb.split_cells("  | a | b |", "local/shared/SHARED-SKILLS.md", 4)
    raise SystemExit("indented row was accepted")
except ValueError as e:
    assert "indented" in str(e) and "local/shared/SHARED-SKILLS.md:4" in str(e), e
try:
    pb.split_cells("| a | b | ", "local/shared/SHARED-SKILLS.md", 9)
    raise SystemExit("trailing space after the pipe was accepted")
except ValueError as e:
    assert "whitespace after the last pipe" in str(e) and "local/shared/SHARED-SKILLS.md:9" in str(e), e
pb.check_applies(["worker", "all", "harbor-clerk"], ["harbor-clerk"], "skill ledger")
try:
    pb.check_applies(["worker worker"], ["harbor-clerk"], "preference 'paint'")
    raise SystemExit("malformed applies was accepted")
except ValueError as e:
    assert "comma-separated" in str(e), e
try:
    pb.check_applies(["ghost-bot"], ["harbor-clerk"], "skill ledger")
    raise SystemExit("unknown slug was accepted")
except ValueError as e:
    assert "fleet.json" in str(e), e
trash = """| Action | Hard rule |
|---|---|
| mail trash | keep the longer name |
"""
only_mail = """| Action | Hard rule |
|---|---|
| mail | a whole phrase |
"""
calendar = """| Action | Hard rule |
|---|---|
| calendar events | ring the bell |
"""
assert not pb.loose_match(trash, "mail")
assert not pb.loose_match(only_mail, "e-mail")
assert pb.loose_match(calendar, "Calendar events.")
kept = pb.relevant_prefs(
    [{"cells": ["Calendar events.", "x"], "action": "Calendar events.", "applies": []}],
    calendar,
    "harbor-clerk",
    "worker",
    [],
)
assert kept, kept
miss = pb.relevant_prefs(
    [{"cells": ["mail"], "action": "mail", "applies": []}],
    trash,
    "harbor-clerk",
    "worker",
    [],
)
assert not miss, miss
try:
    pb.parse_applies("worker,", "skill ledger")
    raise SystemExit("trailing comma was dropped")
except ValueError as e:
    assert "blank slot" in str(e) and "skill ledger" in str(e), e
try:
    pb.parse_applies(",", "preference 'paint'")
    raise SystemExit("lone comma was dropped")
except ValueError as e:
    assert "blank slot" in str(e) and "preference" in str(e), e
src = "fleet/docs/COMPILED-PROMPTS.md"
def rw(text, source=src):
    return pb.rewrite_rel_links(text, source)
# ./ and bare rewrite only when the resolved path is tracked.
assert rw("[n](./CHANGELOG.md)") == "[n](fleet/docs/CHANGELOG.md)"
assert rw("`./CHANGELOG.md`") == "`fleet/docs/CHANGELOG.md`"
assert rw("`./CHANGELOG.md#top`") == "`fleet/docs/CHANGELOG.md#top`"
assert rw("[n](CHANGELOG.md)") == "[n](fleet/docs/CHANGELOG.md)"
assert rw("`CHANGELOG.md`") == "`fleet/docs/CHANGELOG.md`"
# untracked bare and ./ stay, including a trailing slash.
assert rw("`neighbor.md`") == "`neighbor.md`"
assert rw("[n](sub/bare.md)") == "[n](sub/bare.md)"
assert rw("`./missing-nope.md`") == "`./missing-nope.md`"
assert rw("`.obsidian/`") == "`.obsidian/`"
# .. is resolved even when the target is not a reason to skip the escape check.
assert rw("[n](../../fleet/rules/startup.md)", "local/shared/SHARED-SKILLS.md") == "[n](fleet/rules/startup.md)"
assert rw("`../../fleet/rules/startup.md`", "local/shared/SHARED-SKILLS.md") == "`fleet/rules/startup.md`"
# never rewrite these, even from an ACTIONS file where a naive join would prefix the bot kb.
actions = "bots/harbor-clerk/kb/ACTIONS.md"
for tok in (
    "~/secrets/STOP",
    "~/.config/creds",
    "<control>/STOP",
    "America/New_York",
    "app.db",
    ".obsidian/",
    "v1.2.3",
    "example.com",
    "and/or",
    "SKILL.md",
    "calendar",
    "https://example.com/a/../b",
    "#section",
):
    got = rw("`%s`" % tok, actions)
    assert got == "`%s`" % tok, (tok, got)
assert rw("[u](https://example.com/a/../b)", actions) == "[u](https://example.com/a/../b)"
assert rw("[a](#section)", actions) == "[a](#section)"
# kb/ from ACTIONS becomes this bot's kb. From the shared index it fails.
assert rw("`kb/prefs/calendar.md`", actions) == "`bots/harbor-clerk/kb/prefs/calendar.md`"
assert rw("[h](kb/rules.md#family)", actions) == "[h](bots/harbor-clerk/kb/rules.md#family)"
try:
    rw("`kb/prefs/ledger.md`", "local/shared/SHARED-SKILLS.md")
    raise SystemExit("shared kb/ path was kept")
except ValueError as e:
    assert "bots/<slug>/kb/" in str(e), e
try:
    rw("[n](../../../../outside.md)", actions)
    raise SystemExit("ACTIONS escape was rewritten")
except ValueError as e:
    assert "leaves the repo" in str(e), e
assert "cut 1000 characters, or ask the owner about the cap" in pb.over_cap_report(
    "y", 9000, 8000, [("thin", "t" * 1000), ("shared-skills", "s" * 2000), ("action-index", "a" * 6000)], []
)
default_report = pb.over_cap_report(
    "y", 9000, 8000, [("thin", "t" * 1000), ("shared-skills", "s" * 2000), ("action-index", "a" * 6000)], []
)
assert "(cap 8000, default)" in default_report, default_report
override_report = pb.over_cap_report(
    "y", 9000, 9500, [("thin", "t" * 1000), ("shared-skills", "s" * 2000), ("action-index", "a" * 6000)], [], "bot.json override"
)
assert "(cap 9500, bot.json override)" in override_report, override_report
assert pb.resolve_bot_cap({}, 8000) == (8000, "default")
assert pb.resolve_bot_cap({"worktree": "/tmp/example"}, 8000) == (8000, "default")
assert pb.resolve_bot_cap({"prompt_cap": 9500}, 8000) == (9500, "bot.json override")
assert pb.resolve_bot_cap({"prompt_cap": 8000}, 9000) == (8000, "bot.json override")
assert pb.resolve_bot_cap({"prompt_cap": 12000}, 8000) == (12000, "bot.json override")
for bad in (7999, 12001, 0, -1, True, False, 9500.0, "9500", None, []):
    try:
        pb.resolve_bot_cap({"prompt_cap": bad}, 8000)
        raise SystemExit("accepted prompt_cap %r" % (bad,))
    except ValueError as e:
        text = str(e)
        assert "Traceback" not in text
        if isinstance(bad, bool) or not isinstance(bad, int):
            assert "must be an integer" in text, (bad, text)
        elif bad > 12000:
            assert "above the ceiling" in text, text
        else:
            assert "below the floor" in text, (bad, text)
os.environ.pop("BOT_FLEET_PROMPT_MAX", None)
assert pb.fleet_prompt_cap({}) == (8000, "default")
assert pb.fleet_prompt_cap({"prompt_max_chars": 10000}) == (10000, "fleet.json")
assert pb.fleet_prompt_cap({"prompt_max_chars": 8000}) == (8000, "fleet.json")
assert pb.resolve_bot_cap({}, 10000, "fleet.json") == (10000, "fleet.json")
assert pb.resolve_bot_cap({}, 11000, "env") == (11000, "env")
assert pb.resolve_bot_cap({"prompt_cap": 9000}, 10000, "fleet.json") == (9000, "bot.json override")
os.environ["BOT_FLEET_PROMPT_MAX"] = "11000"
assert pb.fleet_prompt_cap({"prompt_max_chars": 10000}) == (11000, "env")
os.environ["BOT_FLEET_PROMPT_MAX"] = "8000"
assert pb.fleet_prompt_cap({}) == (8000, "env")
for bad in ("12001", "7999", "nope", "9000.0", "+9000"):
    os.environ["BOT_FLEET_PROMPT_MAX"] = bad
    try:
        pb.fleet_prompt_cap({})
        raise SystemExit("accepted env %r" % bad)
    except ValueError as e:
        text = str(e)
        assert "Traceback" not in text
        if bad == "12001":
            assert "above the ceiling" in text, text
        elif bad == "7999":
            assert "below the floor" in text, text
        else:
            assert "must be an integer" in text, (bad, text)
os.environ.pop("BOT_FLEET_PROMPT_MAX", None)
for bad in (12001, 7999, "10000", True, False, 10000.0, None):
    try:
        pb.fleet_prompt_cap({"prompt_max_chars": bad})
        raise SystemExit("accepted fleet cap %r" % (bad,))
    except ValueError as e:
        text = str(e)
        assert "Traceback" not in text
        if isinstance(bad, bool) or not isinstance(bad, int):
            assert "must be an integer" in text, (bad, text)
        elif bad > 12000:
            assert "above the ceiling" in text, text
        else:
            assert "below the floor" in text, (bad, text)
assert pb.parse_applies("none", "skill quay-note") == ["none"]
assert pb.parse_applies("NONE", "skill quay-note") == ["none"]
assert pb.parse_applies("None", "skill quay-note") == ["none"]
assert pb.parse_applies("`none`", "skill quay-note") == ["none"]
assert pb.parse_applies("", "skill quay-note") == []
try:
    pb.parse_applies("none, harbor-clerk", "skill quay-note")
    raise SystemExit("mixed none was accepted")
except ValueError as e:
    assert "stand alone" in str(e), e
try:
    pb.parse_applies("worker, none", "preference 'quay watch'")
    raise SystemExit("mixed none was accepted")
except ValueError as e:
    assert "stand alone" in str(e), e
try:
    pb.parse_applies("worker,", "skill quay-note")
    raise SystemExit("blank slot was accepted")
except ValueError as e:
    assert "blank slot" in str(e), e
pb.check_applies(["none"], ["harbor-clerk"], "skill quay-note")
try:
    pb.check_applies(["none", "harbor-clerk"], ["harbor-clerk"], "skill quay-note")
    raise SystemExit("check_applies accepted mixed none")
except ValueError as e:
    assert "stand alone" in str(e), e
try:
    pb.check_applies(["nope"], ["harbor-clerk"], "skill quay-note")
    raise SystemExit("unknown applies was accepted")
except ValueError as e:
    assert "fleet.json" in str(e), e
skipped, _warns = pb.relevant_skills(
    "see quay-note in the index",
    [{"name": "quay-note", "location": "`local/shared/skills/quay-note`", "applies": ["none"], "actions": "", "read": "", "hard": None}],
    "worker",
)
assert skipped == [], skipped
phrase = """| Action | Hard rule |
|---|---|
| calendar events | ring the bell |
"""
assert pb.relevant_prefs(
    [{"cells": ["calendar events", "lookup-only-marker"], "action": "calendar events", "applies": ["none"]}],
    phrase, "harbor-clerk", "worker", [],
) == []
assert pb.relevant_prefs(
    [{"cells": ["calendar events", "owner calendar wins"], "action": "calendar events", "applies": []}],
    phrase, "harbor-clerk", "worker", [],
)
labels = pb.lookup_only_labels("""| Skill | Location | Applies to |
|---|---|---|
| quay-note | library | NONE |
| tide-table | `fleet/skills/tide-table` | worker |
| quay-note | library | none |

| Action | Read first | Applies to |
|---|---|---|
| Calendar events. | notes | none |
| dock painting | `fleet/docs/CONTRIBUTING.md` | builder |
""")
assert labels == ["quay-note", "Calendar events."], labels
print("unit ok")
PY

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

| Skill | When to use | Action types covered | Owner | Location | Applies to | Read first |
|---|---|---|---|---|---|---|
| fleet-change | Use when a change touches the fleet repo and must be classified before anyone applies it. This sentence must not be copied into the prompt. | repo and fleet changes | builder | `fleet/skills/fleet-change` | all | |
| rename-bot | Use when renaming a bot display name, slug, worktree or branch. | repo and fleet changes | builder | `fleet/skills/rename-bot` | builder | |
| ledger | Use when filing pier notes into the ledger skill, including the long explanation that must not be copied into the prompt. | pier notes | builder | `local/shared/skills/ledger` | manager | `bots/harbor-clerk/kb/prefs/ledger.md` and [notes](bots/harbor-clerk/kb/prefs/notes.md) |
| tide-table | Use when reading tide times for the pier. | tide times | worker | `local/shared/skills/tide-table` | worker | [sheet](../../fleet/skills/tide-table/SKILL.md) |
| ledger | Second row of the same skill. | pier notes | builder | `local/shared/skills/ledger` | manager | |
| shelf-index | Use only when the skill name or its path is named. | shelf | builder | library |  | |
| pier-bell | Use only when the name is named. | bell | worker | library |  | |
| dock-line | Use only when a path is named. | dock | worker | `fleet/skills/dock-line` or `local/shared/skills/dock-line` |  | |
| call-log | Use only when the phrase is named. | calls | worker | the `call log` file |  | |
| wharf-bell | Use only when the skills path is named. | wharf | worker | library |  | |
| quay-note | Kept for lookup. This sentence must not be copied into the prompt. | quay | worker | `local/shared/skills/quay-note` | none | |

| Action | Generic default it overrides | Read first | Pointer | Applies to |
|---|---|---|---|---|
| Calendar events. | a connector calendar | bots/harbor-clerk/kb/prefs/calendar.md and [bell](../../local/shared/skills/tide-table/SKILL.md) | owner calendar wins | |
| dock painting | a generic edit | `fleet/docs/CONTRIBUTING.md` | builder wins | builder |
| crate paint | a generic color | notes | nowhere | |
| Calendar events. | lookup-only-marker | notes | not this one | none |
"""
open("local/shared/SHARED-SKILLS.md", "w").write(shared)
os.makedirs("fleet/skills/tide-table", exist_ok=True)
open("fleet/skills/tide-table/SKILL.md", "w").write("# Tide table\n")
os.makedirs("local/shared/skills/tide-table", exist_ok=True)
open("local/shared/skills/tide-table/SKILL.md", "w").write("# Tide table notes\n")
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

Read the [shared skills index](../../../local/shared/SHARED-SKILLS.md) first. The library is mentioned here and is not a skill reference. pier-bell. See local/shared/skills/dock-line. call log. skills/wharf-bell/SKILL.md quay-note

| Action | Read first (kb files, then skills, in order) | Hard rule |
|---|---|---|
| calendar events | `kb/prefs/calendar.md`, skill `calendar` | Never write events to a second calendar service. |
| link calendar | [hours](kb/prefs/calendar.md) and [family](kb/rules.md) | Never write events to a second calendar service. |
| pipe note | `kb/prefs/notes.md` | Never split on a \\| pipe. |
| spaced note | `kb/prefs/notes.md` | Keep  two spaces and an\u00a0nbsp. |
| pier notes | `kb/prefs/notes.md`, skill `ledger` | Do not paraphrase the owner's "pier" notes. |
| tide bell | %s | Ring the tide bell only for the pier. |
| trail note | `kb/prefs/notes.md` | Keep the end   |
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
echo "$ERR" | grep 'FAIL cargo-crier: compiled prompt is '
echo "$ERR" | grep 'action-index '
echo "$ERR" | grep 'crate log'
echo "$ERR" | grep 'Fixed cost '
echo "$ERR" | grep 'Action index '
echo "$ERR" | grep 'Shared skills '
echo "$ERR" | grep -q 'Largest sections:' || fail "over-cap report missing sections"
echo "$ERR" | grep -q 'Largest rows:' || fail "over-cap report missing rows"
echo "$ERR" | grep -q 'duplicate skill row ledger' || fail "duplicate skill was silent: $ERR"
echo "$ERR" | awk '/Largest sections:/{getline; print; exit}' | grep -q '^  action-index ' || fail "largest section is not the action index: $ERR"
echo "$ERR" | grep -q 'Cut this bot'"'"'s own action index: cut ' || fail "over-cap did not blame the action index: $ERR"
echo "$ERR" | grep -q 'or ask the owner about the cap' || fail "over-cap omitted the cap advice: $ERR"
echo "$ERR" | grep -q 'Shorten those ACTIONS.md rows. Hard rules are copied verbatim and are never truncated.' || fail "missing shorten guidance"
echo "$ERR" | grep -q 'Fixed cost ' || fail "over-cap missing fixed cost: $ERR"
echo "$ERR" | grep -q 'Shared skills ' || fail "over-cap missing shared skills: $ERR"
ERR="$ERR" python3 -c 'import os,re; err=os.environ["ERR"]; m=re.search(r"compiled prompt is (\d+) characters \(cap (\d+), ([^)]+)\)", err); n=re.search(r"Cut this bot.s own action index: cut (\d+) characters", err); assert m and n and m.group(3)=="default" and int(n.group(1))==int(m.group(1))-int(m.group(2)), (m, n)' || fail "cut count is not the overflow: $ERR"
echo "$ERR" | grep -q 'cap 8000, default' || fail "over-cap did not name the default cap: $ERR"
[ -f "$REPO/local/prompts/harbor-clerk.md" ] || fail "clerk prompt missing"
[ -f "$REPO/local/prompts/pier-archivist.md" ] || fail "archivist prompt missing"
[ ! -e "$REPO/local/prompts/cargo-crier.md" ] || fail "over-cap prompt was written"
# The huge hard rule is not pasted into the changelog-sized error, and was not truncated into a file.
echo "$ERR" | grep -q 'nowhere else. Always file this crate' && fail "over-cap report pasted the hard rule" || true
pass "over cap fails and names the action index"

python3 - "$REPO" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
def parts(text):
    def span(start, end):
        a = text.find(start)
        b = text.find(end)
        if a < 0 or b < a:
            return ""
        return text[a:b]
    action = span("\n## Action index\n", "\n## Shared skills\n")
    shared = span("\n## Shared skills\n", "\n## Left in git\n")
    return len(text) - len(action) - len(shared), len(action), len(shared)
for slug in ("harbor-clerk", "pier-archivist"):
    text = (root / "local/prompts" / f"{slug}.md").read_text()
    fixed, action, shared = parts(text)
    print(f"SIZE {slug} {len(text)}")
    print(f"FIXED {slug} {fixed}")
    print(f"ACTION {slug} {action}")
    print(f"SHARED {slug} {shared}")
PY

clerk() { cat "$REPO/local/prompts/harbor-clerk.md"; }
arch() { cat "$REPO/local/prompts/pier-archivist.md"; }
clerk | grep -q '## Before you act' || fail "missing pre-action heading"
clerk | grep -q 'even on a one-word reply' || fail "missing one-word reply"
clerk | grep -q 'even right after a summary' || fail "missing summary clause"
clerk | grep -F -q 'Look up the action in the embedded index and in Shared skills.' || fail "missing shared-skills lookup"
clerk | grep -F -q 'At the start of a run, and again after a summary, re-read kb/INDEX.md' || fail "re-read is not limited to the start of a run and a summary"
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
clerk | grep -q -- '- calendar events | `bots/harbor-clerk/kb/prefs/calendar.md`, skill `calendar` | Never write events to a second calendar service.' || fail "calendar row"
clerk | grep -q 'Do not paraphrase the owner'"'"'s "pier" notes.' || fail "hard rule not verbatim"
clerk | grep -q 'Ring the tide bell only for the pier.' || fail "tide bell rule"
clerk | grep -q 'pasted in full into the prompt' || fail "read-first text was shortened"
clerk | grep -q '\[hours\](bots/harbor-clerk/kb/prefs/calendar.md)' || fail "markdown link was dropped"
clerk | grep -q '\[family\](bots/harbor-clerk/kb/rules.md)' || fail "second link was dropped"
clerk | grep -q 'Never split on a \| pipe.' || fail "escaped pipe was split"
clerk | grep -q 'owner calendar wins' || fail "owner-preference row was dropped"
clerk | grep -q 'Keep  two spaces' || fail "internal spaces were collapsed"
python3 -c 'import pathlib,sys; t=pathlib.Path("'"$REPO"'/local/prompts/harbor-clerk.md").read_text(); sys.exit(0 if "Keep  two spaces and an\u00a0nbsp." in t else 1)' || fail "NBSP was stripped"
clerk | grep -F -q '4. If no row exists, act thoughtfully: do the reversible part, and before anything irreversible (send, buy, book, post, delete) stop and ask the owner; when the same ask repeats, add a row to your ACTIONS.md.' || fail "missing step 4"
clerk | grep -q 'kb/INDEX.md' || fail "missing re-read list"
clerk | grep -q "today's journal" || fail "missing journal re-read"
clerk | grep -q 'A summary carries no duties' || fail "missing summary step 0"
clerk | grep -q 'build-prompt.sh --check <slug>' || fail "missing slug check"
clerk | grep -q 'carrying out something you proposed earlier' || fail "missing earlier-proposal clause"
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
clerk | grep -q 'shelf-index' && fail "bare location word library pulled in a skill" || true
arch | grep -q 'shelf-index' && fail "bare location word library pulled in a skill for the builder" || true
clerk | grep -q -- '- pier-bell |' || fail "trailing punctuation hid the skill name"
clerk | grep -q -- '- dock-line |' || fail "second backticked path was not a candidate"
clerk | grep -q -- '- call-log |' || fail "backticked phrase with trailing punctuation missed"
clerk | grep -q -- '- wharf-bell |' || fail "skills/<name> path segment missed"
arch | grep -q -- '- pier-bell |' && fail "name match leaked to the builder" || true
arch | grep -q -- '- dock-line |' && fail "path match leaked to the builder" || true
arch | grep -q -- '- call-log |' && fail "phrase match leaked to the builder" || true
arch | grep -q -- '- wharf-bell |' && fail "skills segment leaked to the builder" || true
clerk | grep -q 'kb/prefs/ledger.md' || fail "skill read-first target missing"
clerk | grep -q 'kb/prefs/notes.md' || fail "skill read-first link missing"
clerk | grep -F -q 'local/shared/skills/tide-table/SKILL.md' || fail "preference link was not a repo-root path"
clerk | grep -F -q 'fleet/skills/tide-table/SKILL.md' || fail "skill link was not a repo-root path"
[ -f "$REPO/fleet/skills/tide-table/SKILL.md" ] || fail "fixture skill file missing"
[ -f "$REPO/local/shared/skills/tide-table/SKILL.md" ] || fail "fixture preference target missing"
python3 -c 'import pathlib,re,sys; t=pathlib.Path(sys.argv[1]).read_text(); bad=re.findall(r"(?:\(|`)(\.\./[^)`\s]*)", t); sys.exit("emitted ../ path: %s" % bad if bad else 0)' "$REPO/local/prompts/harbor-clerk.md" || fail "compiled prompt emitted a ../ path"
clerk | grep -q 'builder wins' && fail "builder preference reached the clerk" || true
clerk | grep -q 'nowhere' && fail "unrelated preference reached the clerk" || true
arch | grep -q 'owner calendar wins' && fail "calendar preference reached the builder" || true
arch | grep -q 'builder wins' || fail "applies-to role missed the builder"
arch | grep -q 'nowhere' && fail "unrelated preference reached the builder" || true
clerk | grep -q 'quay-note' && fail "lookup-only skill was embedded" || true
arch | grep -q 'quay-note' && fail "lookup-only skill was embedded for the builder" || true
clerk | grep -q 'lookup-only-marker' && fail "matching phrase plus none was embedded" || true
arch | grep -q 'lookup-only-marker' && fail "matching phrase plus none was embedded for the builder" || true
python3 -c 'import pathlib,sys; t=pathlib.Path("'"$REPO"'/local/prompts/harbor-clerk.md").read_text(); sys.exit(0 if "Keep the end  " in t else 1)' || fail "trailing spaces were stripped"
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

# An escaping link is a FAIL line for that bot, not an uncaught traceback.
cp "$REPO/local/shared/SHARED-SKILLS.md" "$T/skills.bak"
cat >> "$REPO/local/shared/SHARED-SKILLS.md" << 'EOF'

| Skill | When to use | Action types covered | Owner | Location | Applies to | Read first |
|---|---|---|---|---|---|---|
| escape-hatch | out | out | worker | `../../../outside.md` | all | |
EOF
run "$BUILD" harbor-clerk
[ "$RC" != 0 ] || fail "escaping link was accepted"
echo "$ERR" | grep -q 'FAIL harbor-clerk:' || fail "escaping link was not a FAIL line: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "escaping link printed a traceback: $ERR" || true
echo "$ERR" | grep -q 'leaves the repo' || fail "escaping link did not name the cause: $ERR"
cp "$T/skills.bak" "$REPO/local/shared/SHARED-SKILLS.md"

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
python3 -c 'import json,sys; a=json.load(open("'"$T"'/clerk.json")); b=json.load(open("'"$REPO"'/local/prompts/harbor-clerk.manifest.json")); sys.exit(0 if a["built"]["input_hash"]==b["built"]["input_hash"] else 1)' || fail "non-input edit changed the input hash"
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
echo "$OUT" | grep -q 'cargo-crier: stale (over-cap, not-built); cap 8000, default' || fail "check missed the default cap: $OUT"
echo "$OUT" | grep -q 'cap harbor-clerk: 8000, default' || fail "check missed the clerk cap: $OUT"
n="$(echo "$OUT" | grep -c '^lookup-only: quay-note$' || true)"
[ "$n" = 1 ] || fail "lookup-only skill listed $n times: $OUT"
n="$(echo "$OUT" | grep -c '^lookup-only: Calendar events\.$' || true)"
[ "$n" = 1 ] || fail "lookup-only preference listed $n times: $OUT"
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
# Commit the edited inputs so the build is not a dirty-tree snapshot, then mark.
git -C "$REPO" add -- bots/harbor-clerk/kb/ACTIONS.md local/fleet.json
git -C "$REPO" commit -qm "clerk: calendar row" --no-verify
run "$BUILD" harbor-clerk
[ "$RC" = 0 ] || fail "rebuild after committing the row: $ERR"
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
import re
from pathlib import Path
p = Path("$REPO/fleet/rules/startup.md")
t = p.read_text()
m = re.search(r"prompt_version: (\d+)\n", t)
if not m: raise SystemExit("version line missing")
ver = int(m.group(1))
Path("$T/ver").write_text(str(ver))
p.write_text(t.replace("the file wins.", "the file wins today.", 1))
PY
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 1 ] || fail "digest change without bump should fail"
echo "$OUT$ERR" | grep -q 'FAIL fleet/rules/startup.md: prompt digest changed but prompt_version did not' || fail "bump fail text: $OUT $ERR"
git -C "$REPO" checkout -q -- fleet/rules/startup.md
python3 - <<PY
import re
from pathlib import Path
p = Path("$REPO/fleet/rules/startup.md")
t = p.read_text()
ver = int(Path("$T/ver").read_text())
p.write_text(t.replace("prompt_version: %d\n" % ver, "prompt_version: %d\n" % (ver + 1), 1))
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
# A version decrease fails even when the digest also changes.
git -C "$REPO" checkout -q -- fleet/rules/startup.md
python3 - <<PY
from pathlib import Path
p = Path("$REPO/fleet/rules/startup.md")
t = p.read_text()
ver = int(Path("$T/ver").read_text())
t = t.replace("prompt_version: %d\n" % ver, "prompt_version: %d\n" % (ver - 1), 1)
t = t.replace("the file wins.", "the file wins today.", 1)
p.write_text(t)
PY
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 1 ] || fail "version decrease should fail"
echo "$OUT$ERR" | grep -q 'prompt_version decreased' || fail "decrease text: $OUT $ERR"
# Deleting a kit prompt source fails the check.
git -C "$REPO" checkout -q -- fleet/rules/startup.md
rm -f "$REPO/fleet/roles/retired.md"
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 1 ] || fail "deleted kit source should fail"
echo "$OUT$ERR" | grep -q 'fleet/roles/retired.md: kit prompt source removed' || fail "deletion text: $OUT $ERR"
printf 'fleet/roles/retired.md\n' > "$REPO/fleet/PROMPT-REMOVALS"
run env BOT_FLEET_PROMPT_BASE=HEAD "$BUILD" --check-versions
[ "$RC" = 0 ] || fail "listed removal should pass: $OUT $ERR"
echo "$OUT" | grep -q 'fleet/PROMPT-REMOVALS' || fail "listed removal was silent: $OUT"
git -C "$REPO" checkout -q -- fleet/roles/retired.md
rm -f "$REPO/fleet/PROMPT-REMOVALS"
run env BOT_FLEET_PROMPT_BASE=0123456789abcdef0123456789abcdef01234567 "$BUILD" --check-versions
[ "$RC" = 0 ] || fail "unreachable base aborted: $OUT $ERR"
echo "$ERR" | grep -q 'unreachable' || fail "missing unreachable warning: $ERR"
echo "$OUT" | grep -q 'skipped (no git base)' || fail "unreachable base did not fall through: $OUT"
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

# Per-bot prompt_cap. lane-marker is a fixture name. Absent stays the 8000 default.
python3 - "$REPO" "$T" <<'PY'
import json, os, sys
root, scratch = sys.argv[1], sys.argv[2]
os.chdir(root)
fleet = json.load(open("local/fleet.json"))
fleet["bots"].append({
  "slug": "lane-marker", "name": "Lane Marker", "id": "example-lane-marker",
  "role": "worker", "status": "active", "summary": "Marks a lane.",
})
json.dump(fleet, open("local/fleet.json", "w"), indent=2)
open("local/fleet.json", "a").write("\n")
d = "bots/lane-marker"
os.makedirs(d + "/kb", exist_ok=True)
bj = {
  "schemaVersion": 1, "display_name": "Lane Marker", "slug": "lane-marker", "role": "worker",
  "title": "Example title", "agent_id": "example-lane-marker",
  "worktree": "/tmp/example-worktrees/lane-marker", "owner_name": "Example Owner",
  "fleet_repo": "example/fleet", "kit_version": "0.12.0", "timezone": "UTC",
  "prompt_cap": 9500,
}
json.dump(bj, open(d + "/bot.json", "w"), indent=2)
open(d + "/bot.json", "a").write("\n")
open(d + "/rules.md", "w").write("# Rules\n\nMark the lane.\n")
open(d + "/kb/ACTIONS.md", "w").write("""---
type: actions-index
updated: 2026-01-01
status: seeded
---
# Actions index

| Action | Read first | Hard rule |
|---|---|---|
| lane mark | `kb/prefs/lane.md` | m |
""")
open(scratch + "/lane-base", "w").write("1")
print("lane-marker seeded")
PY
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "short lane-marker build: $ERR"
python3 - "$REPO" "$T" <<'PY'
import pathlib, re, sys
root, scratch = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
prompt = (root / "local/prompts/lane-marker.md").read_text()
actions_path = root / "bots/lane-marker/kb/ACTIONS.md"
actions = actions_path.read_text()
found = re.search(r"\| (m+) \|$", actions, re.M)
if not found:
    raise SystemExit("pad cell missing")
pad = len(found.group(1)) + (9000 - len(prompt))
if pad < 1:
    raise SystemExit("base prompt %d leaves no room under 9000" % len(prompt))
actions_path.write_text(actions[:found.start(1)] + ("m" * pad) + actions[found.end(1):])
(scratch / "actions-9000.md").write_text(actions_path.read_text())
print("pad", pad, "base", len(prompt))
PY
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "9000-char override should pass at cap 9500: $ERR"
python3 -c 'import pathlib,sys; n=len(pathlib.Path(sys.argv[1]).read_text()); assert n==9000, n' "$REPO/local/prompts/lane-marker.md" || fail "override prompt is not 9000 characters"
run "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'cap lane-marker: 9500, bot.json override' || fail "check missed the override: $OUT"
run "$BUILD" --check --json lane-marker
echo "$OUT" | python3 -c 'import json,sys; r=json.load(sys.stdin); b=next(x for x in r["bots"] if x["slug"]=="lane-marker"); assert b["cap"]==9500 and b["cap_source"]=="bot.json override" and b["characters"]==9000, b' || fail "json override cap: $OUT"
pass "override allows 9000 characters at cap 9500"

set_lane_cap() {
  python3 - "$REPO" "$1" <<'PY'
import json, pathlib, sys
root, raw = pathlib.Path(sys.argv[1]), sys.argv[2]
path = root / "bots/lane-marker/bot.json"
bj = json.loads(path.read_text())
if raw == "absent":
    bj.pop("prompt_cap", None)
elif raw == "true":
    bj["prompt_cap"] = True
elif raw == "float":
    bj["prompt_cap"] = 9500.0
elif raw == "str":
    bj["prompt_cap"] = "9500"
else:
    bj["prompt_cap"] = int(raw)
path.write_text(json.dumps(bj, indent=2) + "\n")
PY
}

# Shrink the known 9000-character prompt to 8001 (9000 - 8001 = 999).
python3 - "$REPO" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
actions_path = root / "bots/lane-marker/kb/ACTIONS.md"
actions = actions_path.read_text()
found = re.search(r"\| (m+) \|$", actions, re.M)
if not found:
    raise SystemExit("pad cell missing")
pad = len(found.group(1)) - 999
if pad < 1:
    raise SystemExit("pad too short")
actions_path.write_text(actions[:found.start(1)] + ("m" * pad) + actions[found.end(1):])
PY
set_lane_cap absent
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "8001 without an override should fail"
echo "$ERR" | grep -q 'compiled prompt is 8001 characters (cap 8000, default)' || fail "8001 did not fail at the default cap: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "8001 printed a traceback: $ERR" || true
pass "8001 without an override still fails"

set_lane_cap 8000
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "explicit 8000 should not raise the cap"
echo "$ERR" | grep -q 'compiled prompt is 8001 characters (cap 8000, bot.json override)' || fail "explicit 8000 report: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "explicit 8000 printed a traceback: $ERR" || true

set_lane_cap 12001
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "cap above the ceiling was accepted"
echo "$ERR" | grep -q 'FAIL lane-marker:' || fail "ceiling was not a FAIL line: $ERR"
echo "$ERR" | grep -q 'above the ceiling 12000' || fail "ceiling message: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "ceiling printed a traceback: $ERR" || true

set_lane_cap 7999
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "cap below the default was accepted"
echo "$ERR" | grep -q 'FAIL lane-marker:' || fail "below-default was not a FAIL line: $ERR"
echo "$ERR" | grep -q 'below the floor 8000' || fail "below-floor message: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "below-default printed a traceback: $ERR" || true

set_lane_cap str
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "string prompt_cap was accepted"
echo "$ERR" | grep -q 'FAIL lane-marker:' || fail "string cap was not a FAIL line: $ERR"
echo "$ERR" | grep -q 'must be an integer' || fail "string cap message: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "string cap printed a traceback: $ERR" || true

set_lane_cap true
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "boolean prompt_cap was accepted"
echo "$ERR" | grep -q 'must be an integer' || fail "boolean cap message: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "boolean cap printed a traceback: $ERR" || true

set_lane_cap float
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "float prompt_cap was accepted"
echo "$ERR" | grep -q 'must be an integer' || fail "float cap message: $ERR"

# Ceiling is inclusive: 12000 accepts the 9000-character prompt.
cp "$T/actions-9000.md" "$REPO/bots/lane-marker/kb/ACTIONS.md"
set_lane_cap 12000
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "cap 12000 should accept 9000 characters: $ERR"
python3 -c 'import pathlib,sys; n=len(pathlib.Path(sys.argv[1]).read_text()); assert n==9000, n' "$REPO/local/prompts/lane-marker.md" || fail "ceiling prompt is not 9000 characters"
pass "prompt_cap fail-closed"

python3 - "$REPO" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
try:
    import jsonschema
except ImportError:
    raise SystemExit("jsonschema missing")
schema = json.load(open(root / "fleet/schema/bot.schema.json"))
base = json.loads((root / "bots/harbor-clerk/bot.json").read_text())
assert "prompt_cap" not in base
jsonschema.validate(base, schema)
for good in (8000, 9500, 12000):
    trial = dict(base)
    trial["prompt_cap"] = good
    jsonschema.validate(trial, schema)
# 9500.0 is a whole JSON number. The builder still rejects it; this schema check
# covers the values draft 2020-12 integer plus minimum and maximum refuse.
for bad in (7999, 12001, "9500", True, None):
    trial = dict(base)
    trial["prompt_cap"] = bad
    try:
        jsonschema.validate(trial, schema)
    except jsonschema.ValidationError:
        continue
    raise SystemExit("schema accepted %r" % (bad,))
print("schema ok")
PY
pass "bot.json schema bounds prompt_cap"

# none mixed with a slug fails the build. A lone none stays unembedded (asserted above).
cp "$REPO/local/shared/SHARED-SKILLS.md" "$T/skills-none.bak"
cat >> "$REPO/local/shared/SHARED-SKILLS.md" << 'EOF'

| Skill | When to use | Action types covered | Owner | Location | Applies to | Read first |
|---|---|---|---|---|---|---|
| mixed-note | out | out | worker | library | none, lane-marker | |
EOF
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "none mixed with a slug was accepted"
echo "$ERR" | grep -q 'FAIL lane-marker:' || fail "mixed none was not a FAIL line: $ERR"
echo "$ERR" | grep -q 'none must stand alone' || fail "mixed none did not name the cause: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "mixed none printed a traceback: $ERR" || true
cp "$T/skills-none.bak" "$REPO/local/shared/SHARED-SKILLS.md"
pass "none stands alone and is lookup-only"

# Cap source and floor. Precedence is bot.json, then env, then fleet.json, then default.
# The floor is 8000 whatever the configured fleet or env cap is.
unset BOT_FLEET_PROMPT_MAX
cp "$REPO/local/fleet.json" "$T/fleet-before-sources.json"
set_fleet_cap() {
  python3 - "$REPO" "$1" <<'PY'
import json, pathlib, sys
root, raw = pathlib.Path(sys.argv[1]), sys.argv[2]
path = root / "local/fleet.json"
fleet = json.loads(path.read_text())
if raw == "absent":
    fleet.pop("prompt_max_chars", None)
elif raw == "true":
    fleet["prompt_max_chars"] = True
elif raw == "float":
    fleet["prompt_max_chars"] = 10000.0
elif raw == "str":
    fleet["prompt_max_chars"] = "10000"
else:
    fleet["prompt_max_chars"] = int(raw)
path.write_text(json.dumps(fleet, indent=2) + "\n")
PY
}
set_lane_cap absent
set_fleet_cap 10000
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "fleet.json cap 10000 should accept 9000 characters: $ERR"
run "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'cap lane-marker: 10000, fleet.json' || fail "check missed fleet.json: $OUT"
echo "$OUT" | grep 'cap lane-marker:' | grep -q 'default' && fail "fleet.json cap was called default: $OUT" || true
set_fleet_cap 8000
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "fleet.json 8000 should still be over cap for 9000 characters"
echo "$ERR" | grep -q 'compiled prompt is 9000 characters (cap 8000, fleet.json)' || fail "fleet.json 8000 report: $ERR"
echo "$ERR" | grep -q '(cap 8000, default)' && fail "number 8000 from fleet.json was called default: $ERR" || true
set_fleet_cap 12001
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "fleet.json above the ceiling was accepted"
echo "$ERR" | grep -q 'FAIL fleet: prompt_max_chars 12001 is above the ceiling 12000' || fail "fleet ceiling line: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "fleet ceiling printed a traceback: $ERR" || true
run "$BUILD" --check lane-marker
[ "$RC" != 0 ] || fail "check accepted a fleet cap above the ceiling"
echo "$OUT" | grep -q 'FAIL fleet: prompt_max_chars 12001 is above the ceiling 12000' || fail "check fleet ceiling: $OUT"
set_fleet_cap 7999
run "$BUILD" lane-marker
[ "$RC" != 0 ] || fail "fleet.json below the floor was accepted"
echo "$ERR" | grep -q 'FAIL fleet: prompt_max_chars 7999 is below the floor 8000' || fail "fleet floor line: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "fleet floor printed a traceback: $ERR" || true
set_fleet_cap str
run "$BUILD" lane-marker
echo "$ERR" | grep -q 'FAIL fleet: prompt_max_chars must be an integer' || fail "fleet string cap: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "fleet string cap printed a traceback: $ERR" || true
set_fleet_cap true
run "$BUILD" --check
echo "$OUT" | grep -q 'FAIL fleet: prompt_max_chars must be an integer' || fail "fleet boolean cap: $OUT"
set_fleet_cap float
run "$BUILD" lane-marker
echo "$ERR" | grep -q 'FAIL fleet: prompt_max_chars must be an integer' || fail "fleet float cap: $ERR"
set_fleet_cap 10000
run env BOT_FLEET_PROMPT_MAX=11000 "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "env cap 11000 should win and accept 9000 characters: $ERR"
run env BOT_FLEET_PROMPT_MAX=11000 "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'cap lane-marker: 11000, env' || fail "check missed env: $OUT"
echo "$OUT" | grep 'cap lane-marker:' | grep -q 'default' && fail "env cap was called default: $OUT" || true
run env BOT_FLEET_PROMPT_MAX=8000 "$BUILD" lane-marker
echo "$ERR" | grep -q 'compiled prompt is 9000 characters (cap 8000, env)' || fail "env 8000 report: $ERR"
echo "$ERR" | grep -q '(cap 8000, default)' && fail "env 8000 was called default: $ERR" || true
run env BOT_FLEET_PROMPT_MAX=12001 "$BUILD" lane-marker
echo "$ERR" | grep -q 'FAIL fleet: BOT_FLEET_PROMPT_MAX 12001 is above the ceiling 12000' || fail "env ceiling line: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "env ceiling printed a traceback: $ERR" || true
run env BOT_FLEET_PROMPT_MAX=7999 "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'FAIL fleet: BOT_FLEET_PROMPT_MAX 7999 is below the floor 8000' || fail "env floor line: $OUT"
run env BOT_FLEET_PROMPT_MAX=nope "$BUILD" lane-marker
echo "$ERR" | grep -q 'FAIL fleet: BOT_FLEET_PROMPT_MAX must be an integer' || fail "env non-integer: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "env non-integer printed a traceback: $ERR" || true
run env BOT_FLEET_PROMPT_MAX=9000.0 "$BUILD" lane-marker
echo "$ERR" | grep -q 'FAIL fleet: BOT_FLEET_PROMPT_MAX must be an integer' || fail "env float text: $ERR"
# A bot override may sit below the configured fleet cap. The floor is still 8000.
set_lane_cap 9000
run env BOT_FLEET_PROMPT_MAX=11000 "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "bot override should beat env: $ERR"
run env BOT_FLEET_PROMPT_MAX=11000 "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'cap lane-marker: 9000, bot.json override' || fail "bot override lost to env: $OUT"
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "bot override 9000 should be allowed under fleet cap 10000: $ERR"
run "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'cap lane-marker: 9000, bot.json override' || fail "bot override lost to fleet.json: $OUT"
set_lane_cap 7999
run "$BUILD" lane-marker
echo "$ERR" | grep -q 'FAIL lane-marker:' || fail "bot cap below the floor was not a FAIL line: $ERR"
echo "$ERR" | grep -q 'below the floor 8000' || fail "bot floor ignored the configured fleet cap: $ERR"
echo "$ERR" | grep -q 'Traceback' && fail "bot floor printed a traceback: $ERR" || true
# A cap change is a new input even when the prompt text stays the same.
set_fleet_cap absent
set_lane_cap 9500
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "rebuild before cap-hash check: $ERR"
cp "$REPO/local/prompts/lane-marker.md" "$T/lane-cap.md"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["built"]["input_hash"])' "$REPO/local/prompts/lane-marker.manifest.json" > "$T/lane-hash-1"
set_lane_cap 10000
run "$BUILD" --check lane-marker
echo "$OUT" | grep -q 'inputs-changed' || fail "cap change was not an input change: $OUT"
echo "$OUT" | grep -q 'cap lane-marker: 10000, bot.json override' || fail "check missed the new cap: $OUT"
cmp "$T/lane-cap.md" "$REPO/local/prompts/lane-marker.md" || fail "check rewrote the prompt on a cap change"
run "$BUILD" --changelog
echo "$OUT" | grep -q 'Effective cap for each compiled bot:' || fail "changelog missed the cap list: $OUT"
echo "$OUT" | grep -q -- '- lane-marker: 10000, bot.json override' || fail "changelog missed lane-marker cap: $OUT"
echo "$OUT" | grep -q -- '- harbor-clerk: 8000, default' || fail "changelog missed the default cap: $OUT"
run "$BUILD" lane-marker
[ "$RC" = 0 ] || fail "rebuild after cap change: $ERR"
cmp "$T/lane-cap.md" "$REPO/local/prompts/lane-marker.md" || fail "cap change rewrote the prompt text"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["built"]["input_hash"])' "$REPO/local/prompts/lane-marker.manifest.json" > "$T/lane-hash-2"
cmp "$T/lane-hash-1" "$T/lane-hash-2" && fail "cap change left the input hash unchanged" || true
python3 - "$REPO" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
import jsonschema
schema = json.load(open(root / "fleet/schema/fleet.schema.json"))
base = json.loads((root / "local/fleet.json").read_text())
base.pop("prompt_max_chars", None)
jsonschema.validate(base, schema)
for good in (8000, 10000, 12000):
    trial = dict(base)
    trial["prompt_max_chars"] = good
    jsonschema.validate(trial, schema)
for bad in (7999, 12001, 1, "10000", True, None):
    trial = dict(base)
    trial["prompt_max_chars"] = bad
    try:
        jsonschema.validate(trial, schema)
    except jsonschema.ValidationError:
        continue
    raise SystemExit("fleet schema accepted %r" % (bad,))
print("fleet cap schema ok")
PY
cp "$T/fleet-before-sources.json" "$REPO/local/fleet.json"
pass "cap source, floor, and hash"

echo
echo "SIZE harbor-clerk $(python3 -c 'print(len(open("'"$REPO"'/local/prompts/harbor-clerk.md").read()))')"
echo "SIZE pier-archivist $(python3 -c 'print(len(open("'"$REPO"'/local/prompts/pier-archivist.md").read()))' 2>/dev/null || echo missing)"
pass "0.12.0 compiled prompts"
