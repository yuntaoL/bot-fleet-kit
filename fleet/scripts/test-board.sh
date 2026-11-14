#!/usr/bin/env bash
# 0.12.0 optional shared task board. Scratch repos only. Fictional bots. No owner data.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
cleanup() { rm -rf "$T"; }
trap cleanup EXIT
fail() { echo "FAIL $*" >&2; [ -n "${OUT:-}" ] && echo "$OUT" >&2; exit 1; }
pass() { echo "PASS $*"; }
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="$T/gitconfig" LC_ALL=C PYTHONDONTWRITEBYTECODE=1
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.invalid
git config --global commit.gpgsign false

# The rule text is in the common Prompt digest, so compiled prompts can carry it.
grep -q 'prompt_version: 3' "$SRC/fleet/rules/common.md" || fail "common prompt_version was not bumped"
grep -q 'A board card is never an approval' "$SRC/fleet/rules/common.md" || fail "card-is-not-approval missing"
grep -q 'When fleet.json sets a board' "$SRC/fleet/rules/common.md" || fail "digest missing board clause"
grep -q 'nudges a stale card' "$SRC/fleet/rules/common.md" || fail "digest missing nudge"
grep -q 'manager-owned cards' "$SRC/fleet/rules/common.md" || fail "digest missing approval cards"
grep -q 'same sync' "$SRC/fleet/rules/common.md" || fail "digest missing same-sync card"
grep -q 'pull\.sh' "$SRC/fleet/rules/common.md" && fail "common.md must not teach pull.sh" || true
python3 -c 'import json; json.load(open("'"$SRC"'/fleet/OWNERS.json")); json.load(open("'"$SRC"'/fleet/schema/fleet.schema.json"))' || fail "json"
python3 -m py_compile "$SRC/fleet/scripts/owners.py" "$SRC/fleet/scripts/schema_check.py"
pass "source shape"

REPO="$T/repo"
mkdir -p "$REPO/fleet/scripts" "$REPO/fleet/schema" "$REPO/local/shared/state" \
  "$REPO/bots/mina/kb" "$REPO/bots/mina/journal" \
  "$REPO/bots/otto/kb" "$REPO/bots/otto/journal" \
  "$REPO/bots/rex/kb" "$REPO/bots/nell/kb"
cp "$SRC/fleet/OWNERS.json" "$REPO/fleet/OWNERS.json"
cp "$SRC/fleet/scripts/owners.py" "$REPO/fleet/scripts/owners.py"
cp "$SRC/fleet/scripts/schema_check.py" "$REPO/fleet/scripts/schema_check.py"
cp "$SRC/fleet/scripts/sync.sh" "$REPO/fleet/scripts/sync.sh"
cp "$SRC/fleet/scripts/schema_check.py" "$REPO/fleet/scripts/schema_check.py"
cp "$SRC/fleet/scripts/check-staged-config.sh" "$REPO/fleet/scripts/check-staged-config.sh"
cp "$SRC/fleet/schema/"*.schema.json "$REPO/fleet/schema/"
chmod +x "$REPO/fleet/scripts/sync.sh" "$REPO/fleet/scripts/check-staged-config.sh"
printf '# note\n' > "$REPO/bots/otto/kb/note.md"
printf '# note\n' > "$REPO/bots/rex/kb/note.md"
printf -- '- start\n' > "$REPO/bots/otto/journal/2026-01-01.md"
printf '# overrides\n' > "$REPO/local/overrides.md"
printf '# readme\n' > "$REPO/README.md"

python3 - "$REPO" <<'PY'
import json, sys
root = sys.argv[1]
bots = [
    {"slug": "nell", "name": "Nell", "id": "example-nell", "role": "manager", "status": "active"},
    {"slug": "mina", "name": "Mina", "id": "example-mina", "role": "worker", "status": "active"},
    {"slug": "otto", "name": "Otto", "id": "example-otto", "role": "worker", "status": "active"},
    {"slug": "rex", "name": "Rex", "id": "example-rex", "role": "retired", "status": "retired"},
]
base = {"schemaVersion": 2, "owner": "example", "owner_name": "Example Owner", "templateVersion": "0.12.0", "bots": bots}
json.dump(base, open(root + "/local/fleet.json", "w"), indent=2)
open(root + "/local/fleet.json", "a").write("\n")
open(root + "/local/fleet.off.json", "w").write(open(root + "/local/fleet.json").read())
on = dict(base)
on["board"] = {"path": "local/shared/state/board.md", "coordinator": "mina"}
json.dump(on, open(root + "/local/fleet.on.json", "w"), indent=2)
open(root + "/local/fleet.on.json", "a").write("\n")
PY

git init -q -b main "$REPO"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name test
git -C "$REPO" add -A
git -C "$REPO" commit -qm "base, board off" --no-verify

# Schema: off is valid; on is valid; bad coordinator, retired coordinator, bad path, role-shaped slug.
python3 - "$REPO" "$SRC" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1] + "/fleet/scripts")
import schema_check
try:
    import jsonschema
except ImportError:
    jsonschema = None
root, src = sys.argv[1], sys.argv[2]
schema = json.load(open(src + "/fleet/schema/fleet.schema.json"))
off = json.load(open(root + "/local/fleet.off.json"))
on = json.load(open(root + "/local/fleet.on.json"))
assert schema_check.board_errors(off) == []
assert schema_check.board_errors(on) == []
if jsonschema:
    jsonschema.validate(off, schema)
    jsonschema.validate(on, schema)
bad = json.loads(json.dumps(on))
bad["board"]["coordinator"] = "worker"  # a role word, and not a bot slug in this fleet
errs = schema_check.board_errors(bad)
assert any("not a bot" in e for e in errs), errs
bad["board"]["coordinator"] = "rex"
errs = schema_check.board_errors(bad)
assert any("retired" in e for e in errs), errs
bad["board"]["coordinator"] = "mina"
bad["board"]["path"] = "local/shared/SHARED-SKILLS.md"
errs = schema_check.board_errors(bad)
assert any("local/shared/state" in e for e in errs), errs
bad["board"]["path"] = "local/../../secret.md"
if jsonschema:
    try:
        jsonschema.validate(bad, schema)
        raise SystemExit("path with .. was accepted")
    except jsonschema.ValidationError:
        pass
bad["board"] = {"path": "/tmp/board.md", "coordinator": "mina"}
if jsonschema:
    try:
        jsonschema.validate(bad, schema)
        raise SystemExit("absolute path was accepted")
    except jsonschema.ValidationError:
        pass
print("schema checks ok")
PY
pass "schema: off, on, missing slug, retired coordinator, reserved and unsafe paths"

try_check() { # slug role ; uses the index
  set +e
  OUT="$(cd "$REPO" && git diff --cached --name-status --no-renames | BOT_NAME="$1" BOT_ROLE="$2" python3 fleet/scripts/owners.py check 2>&1)"
  RC=$?
  set -e
}
# Unconfigured: the path is manager-owned. A worker cannot add it.
# An unstaged fleet.json that turns the board on does not count.
cp "$REPO/local/fleet.on.json" "$REPO/local/fleet.json"
mkdir -p "$REPO/local/shared/state"
printf '# board\n' > "$REPO/local/shared/state/board.md"
git -C "$REPO" add -- local/shared/state/board.md
try_check otto worker
[ "$RC" != 0 ] || fail "unconfigured board allowed a worker (HEAD has no board): $OUT"
echo "$OUT" | grep -q 'manager-owned' || fail "expected manager-owned while board is off: $OUT"
git -C "$REPO" reset -q -- local/shared/state/board.md
git -C "$REPO" checkout -q -- local/fleet.json
pass "board unconfigured: worker cannot write it; a dirty fleet.json does not turn it on"

# Turn the feature on in HEAD.
cp "$REPO/local/fleet.on.json" "$REPO/local/fleet.json"
git -C "$REPO" add -- local/fleet.json
try_check nell manager
[ "$RC" = 0 ] || fail "manager could not commit fleet.json: $OUT"
git -C "$REPO" commit -qm "nell: enable board" --no-verify

# Other bot may not create the file.
git -C "$REPO" add -- local/shared/state/board.md
try_check otto worker
[ "$RC" != 0 ] || fail "other bot was allowed to create the board: $OUT"
echo "$OUT" | grep -q 'shared task board' || fail "create rejection: $OUT"
git -C "$REPO" reset -q -- local/shared/state/board.md
# Coordinator (a worker slug) may create it.
git -C "$REPO" add -- local/shared/state/board.md
try_check mina worker
[ "$RC" = 0 ] || fail "coordinator create rejected: $OUT"
git -C "$REPO" commit -qm "mina: create board" --no-verify
pass "coordinator may create the board; another bot may not"

# Other non-retired bot may update. Retired may not. Manager may.
printf '\n- otto: pier notes\n' >> "$REPO/local/shared/state/board.md"
git -C "$REPO" add -- local/shared/state/board.md
try_check otto worker
[ "$RC" = 0 ] || fail "other bot update rejected: $OUT"
git -C "$REPO" commit -qm "otto: own card" --no-verify
printf '\n- rex: should not\n' >> "$REPO/local/shared/state/board.md"
git -C "$REPO" add -- local/shared/state/board.md
try_check rex worker
[ "$RC" != 0 ] || fail "retired bot was allowed to update the board: $OUT"
echo "$OUT" | grep -q 'shared task board' || fail "retired rejection: $OUT"
git -C "$REPO" reset -q -- local/shared/state/board.md
git -C "$REPO" checkout -q -- local/shared/state/board.md
printf '\n- nell: approval wait\n' >> "$REPO/local/shared/state/board.md"
git -C "$REPO" add -- local/shared/state/board.md
try_check nell manager
[ "$RC" = 0 ] || fail "manager update rejected: $OUT"
git -C "$REPO" commit -qm "nell: approval card" --no-verify
# Delete is not for the other bot.
git -C "$REPO" rm -q local/shared/state/board.md
try_check otto worker
[ "$RC" != 0 ] || fail "other bot was allowed to delete the board: $OUT"
git -C "$REPO" reset -q -- local/shared/state/board.md
git -C "$REPO" checkout -q -- local/shared/state/board.md
pass "update: other bot yes, retired no, manager yes; delete stays with manager and coordinator"

# A journal symlink to another bot's file is refused, including a type change.
printf 'mina note\n' > "$REPO/bots/mina/kb/note.md"
git -C "$REPO" add -- bots/mina/kb/note.md
try_check mina worker
[ "$RC" = 0 ] || fail "mina could not add her own note: $OUT"
git -C "$REPO" commit -qm "mina: note" --no-verify
printf 'otto day\n' > "$REPO/bots/otto/journal/day.md"
git -C "$REPO" add -- bots/otto/journal/day.md
try_check otto worker
[ "$RC" = 0 ] || fail "regular journal add rejected: $OUT"
git -C "$REPO" commit -qm "otto: journal" --no-verify
rm -f "$REPO/bots/otto/journal/day.md"
ln -s ../../mina/kb/note.md "$REPO/bots/otto/journal/day.md"
git -C "$REPO" add -- bots/otto/journal/day.md
try_check otto worker
[ "$RC" != 0 ] || fail "journal type change to a symlink was allowed: $OUT"
echo "$OUT" | grep -q 'type change' || fail "type change message: $OUT"
git -C "$REPO" reset -q -- bots/otto/journal/day.md
git -C "$REPO" checkout -q -- bots/otto/journal/day.md
ln -s ../../mina/kb/note.md "$REPO/bots/otto/journal/other.md"
git -C "$REPO" add -- bots/otto/journal/other.md
try_check otto worker
[ "$RC" != 0 ] || fail "new journal symlink was allowed: $OUT"
echo "$OUT" | grep -q '100644' || fail "mode message: $OUT"
git -C "$REPO" reset -q -- bots/otto/journal/other.md
rm -f "$REPO/bots/otto/journal/other.md"
pass "bot journal symlink and type change are refused"

# A board path under bots/ does not make that file writable. The bad config is committed
# only with --no-verify, the way a hook bypass would.
python3 - <<PY
import json
p="$REPO/local/fleet.json"
f=json.load(open(p))
f["board"]={"path":"bots/mina/kb/note.md","coordinator":"mina"}
json.dump(f, open(p,"w"), indent=2)
open(p,"a").write("\n")
PY
git -C "$REPO" add -- local/fleet.json
git -C "$REPO" commit -qm "bad board path" --no-verify
printf '%s\n' 'otto edit' >> "$REPO/bots/mina/kb/note.md"
git -C "$REPO" add -- bots/mina/kb/note.md
try_check otto worker
[ "$RC" != 0 ] || fail "board path under bots/ let another bot write it: $OUT"
echo "$OUT" | grep -q "owned by bot 'mina'" || fail "expected self ownership, got: $OUT"
git -C "$REPO" reset -q --hard HEAD~1
pass "invalid board path is off and cannot widen another bot's files"

# sync: path arguments also stage the journal. A path sync does not stage the board.
git init -q --bare -b main "$T/origin.git"
git -C "$REPO" remote add origin "$T/origin.git"
git -C "$REPO" push -q origin HEAD:main
printf '\n- journal line\n' >> "$REPO/bots/otto/journal/2026-01-01.md"
printf '\nmore note\n' >> "$REPO/bots/otto/kb/note.md"
set +e
OUT="$(cd "$REPO" && BOT_NAME=otto BOT_ROLE=worker fleet/scripts/sync.sh "otto: note" bots/otto/kb/note.md 2>&1)"
RC=$?
set -e
[ "$RC" = 0 ] || fail "path sync should stage the journal and push: $OUT"
git -C "$REPO" show --name-only --format= HEAD | grep -q 'bots/otto/journal/2026-01-01.md' || fail "journal was left out of the path sync: $OUT"
git -C "$REPO" show --name-only --format= HEAD | grep -q 'bots/otto/kb/note.md' || fail "path sync missed the requested file"
pass "path sync stages the journal so rebase can run"

printf '\n- otto: second card\n' >> "$REPO/local/shared/state/board.md"
printf '\nthird note\n' >> "$REPO/bots/otto/kb/note.md"
set +e
OUT="$(cd "$REPO" && BOT_NAME=otto BOT_ROLE=worker fleet/scripts/sync.sh "otto: card" bots/otto/kb/note.md 2>&1)"
RC=$?
set -e
[ "$RC" != 0 ] || fail "path sync should not carry a half-edited board through rebase: $OUT"
git -C "$REPO" log -1 --format=%s | grep -q 'otto: card' && git -C "$REPO" show HEAD:local/shared/state/board.md | grep -q 'second card' && fail "path sync committed the board" || true
git -C "$REPO" reset -q --hard origin/main
printf '\n- otto: second card\n' >> "$REPO/local/shared/state/board.md"
printf '\nthird note\n' >> "$REPO/bots/otto/kb/note.md"
set +e
OUT="$(cd "$REPO" && BOT_NAME=otto BOT_ROLE=worker fleet/scripts/sync.sh "otto: card" 2>&1)"
RC=$?
set -e
[ "$RC" = 0 ] || fail "default sync should stage the board: $OUT"
git -C "$REPO" show HEAD:local/shared/state/board.md | grep -q 'second card' || fail "default sync left the board out: $OUT"
pass "path sync leaves a half-edited board; a default sync stages it"

printf '\n- rex: no\n' >> "$REPO/local/shared/state/board.md"
printf '\nrex note\n' >> "$REPO/bots/rex/kb/note.md"
set +e
OUT="$(cd "$REPO" && BOT_NAME=rex BOT_ROLE=worker fleet/scripts/sync.sh "rex: note" bots/rex/kb/note.md 2>&1)"
RC=$?
set -e
[ "$RC" != 0 ] || fail "retired bot sync should not push a dirty board it cannot stage"
git -C "$REPO" show --name-only --format= HEAD | grep -q 'local/shared/state/board.md' && git -C "$REPO" show HEAD -- local/shared/state/board.md | grep -q 'rex: no' && fail "retired bot committed the board" || true
git -C "$REPO" diff -- local/shared/state/board.md | grep -q 'rex: no' || fail "retired board edit was staged or lost"
git -C "$REPO" reset -q --hard origin/main
pass "retired bot does not get the board staged"

# Compiled prompt carries the digest line.
COMP="$T/comp"
mkdir -p "$COMP/fleet/scripts" "$COMP/templates" "$COMP/local/shared" "$COMP/bots/mina/kb"
cp -a "$SRC/fleet/rules" "$COMP/fleet/rules"
cp -a "$SRC/fleet/roles" "$COMP/fleet/roles"
cp "$SRC/fleet/VERSION" "$COMP/fleet/VERSION"
cp "$SRC/fleet/scripts/prompt_build.py" "$COMP/fleet/scripts/prompt_build.py"
cp "$SRC/fleet/scripts/build-prompt.sh" "$COMP/fleet/scripts/build-prompt.sh"
cp "$SRC/templates/THIN-PROMPT.tmpl" "$COMP/templates/THIN-PROMPT.tmpl"
chmod +x "$COMP/fleet/scripts/build-prompt.sh"
printf '%s\n' '---' 'type: shared-skills-index' 'status: seeded' '---' '# Skills' > "$COMP/local/shared/SHARED-SKILLS.md"
printf '%s\n' '---' 'type: actions-index' 'status: seeded' '---' '# Actions' '| Action | Read first | Hard rule |' '|---|---|---|' '| notes | `kb/notes.md` | Keep notes in the ledger. |' > "$COMP/bots/mina/kb/ACTIONS.md"
printf '# Rules\n\nKeep notes.\n' > "$COMP/bots/mina/rules.md"
python3 - "$COMP" <<'PY'
import json, sys
root = sys.argv[1]
json.dump({"schemaVersion": 2, "owner": "example", "owner_name": "Example Owner", "templateVersion": "0.12.0", "prompt_mode": "compiled",
           "bots": [{"slug": "mina", "name": "Mina", "id": "example-mina", "role": "worker", "status": "active"}]},
          open(root + "/local/fleet.json", "w"), indent=2)
open(root + "/local/fleet.json", "a").write("\n")
json.dump({"schemaVersion": 1, "display_name": "Mina", "slug": "mina", "role": "worker", "title": "Notes",
           "agent_id": "example-mina", "worktree": "/tmp/example-worktrees/mina", "owner_name": "Example Owner",
           "fleet_repo": "example/fleet", "kit_version": "0.12.0", "timezone": "UTC"},
          open(root + "/bots/mina/bot.json", "w"), indent=2)
open(root + "/bots/mina/bot.json", "a").write("\n")
PY
git init -q -b main "$COMP"
git -C "$COMP" config user.email test@example.invalid
git -C "$COMP" config user.name test
git -C "$COMP" add -A && git -C "$COMP" commit -qm "comp" --no-verify
(cd "$COMP" && fleet/scripts/build-prompt.sh mina)
grep -q 'nudges once, then escalates to the manager' "$COMP/local/prompts/mina.md" || fail "compiled prompt missing board digest"
grep -q 'approval waits are manager-owned cards' "$COMP/local/prompts/mina.md" || fail "compiled prompt missing approval line"
pass "compiled prompt contains the board digest"

pass "0.12.0 shared task board"
