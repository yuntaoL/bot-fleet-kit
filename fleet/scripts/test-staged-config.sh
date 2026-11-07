#!/usr/bin/env bash
# Behavioral tests: staged routine, bot.json and local/fleet.json are schema-checked
# before commit (pre-commit hook) and before sync.sh commits or pushes.
# The index blob is checked (git cat-file of the staged blob). The working tree is not.
# Schemas come from that same index snapshot. Symlinks, gitlinks, and other
# non-regular modes fail closed. An untrusted jsonschema module cannot shadow the check.
# Unstaged and untracked files are not checked and are not committed.
#
# What sync.sh stages today (unchanged by this check):
#   paths on the command line, if any
#   otherwise bots/<fleet.bot>/
#   manager also: local/ and README.md, plus bots/<fleet.bot>/ when that directory exists
# `git add --` those paths only (never -A). Untracked files inside them are staged.
# Unstaged and untracked files outside them are not staged. `git commit` commits the
# whole index. A tracked edit left outside the add paths stays unstaged, and git rebase
# then refuses to start, so that run does not push (existing sync.sh behavior).
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
pass_n=0
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; }
trap cleanup EXIT
fail() { echo "FAIL $*" >&2; exit 1; }
pass() { echo "PASS $*"; pass_n=$((pass_n+1)); }

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL="$T/gitconfig"
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.invalid
git config --global commit.gpgsign false

# Factoring: one jsonschema.validate call, used by validate.sh. Schemas stay the rules.
grep -q 'schema_check.check_file' "$SRC/fleet/scripts/validate.sh" || fail "validate.sh does not call schema_check.check_file"
if grep -n 'jsonschema.validate' "$SRC/fleet/scripts/validate.sh"; then
  fail "validate.sh calls jsonschema.validate directly"
fi
nval="$(grep -c 'jsonschema_mod.validate' "$SRC/fleet/scripts/schema_check.py" || true)"
[ "$nval" = 1 ] || fail "schema_check.py should call jsonschema validate once (got $nval)"
pass "validator logic is schema_check.apply_schema, shared with validate.sh"

REPO="$T/repo"
REMOTE="$T/remote.git"
mkdir -p "$REPO/fleet/schema" "$REPO/fleet/scripts" "$REPO/bots/atlas/routines" "$REPO/bots/atlas/journal" \
  "$REPO/bots/forge/routines" "$REPO/local"
cp -a "$SRC/fleet/schema/." "$REPO/fleet/schema/"
cp -a "$SRC/fleet/OWNERS.json" "$REPO/fleet/OWNERS.json"
for s in schema_check.py check-staged-config.sh sync.sh install-hook.sh check-boundary.sh confidential-scan.sh owners.py; do
  cp -a "$SRC/fleet/scripts/$s" "$REPO/fleet/scripts/$s"
done
chmod +x "$REPO/fleet/scripts/"*.sh

python3 - "$REPO" << 'PY'
import json, sys
root = sys.argv[1]
def w(path, obj):
    with open(root + "/" + path, "w") as f:
        json.dump(obj, f, indent=2)
        f.write("\n")
w("local/fleet.json", {
    "schemaVersion": 2, "owner": "alextest", "owner_name": "Alex Test",
    "bots": [
        {"slug": "atlas", "name": "Atlas", "id": "fake-atlas", "role": "manager", "status": "active"},
        {"slug": "forge", "name": "Forge", "id": "fake-forge", "role": "builder", "status": "active"},
    ],
})
w("bots/atlas/bot.json", {
    "schemaVersion": 1, "display_name": "Atlas", "slug": "atlas", "role": "manager",
    "agent_id": "fake-atlas", "worktree": "/tmp/atlas", "owner_name": "Alex Test",
    "kit_version": "0.10.8", "timezone": "UTC",
})
w("bots/atlas/routines/loop.json", {"name": "loop", "schedule": "daily", "steps": ["check"], "status": "active"})
w("bots/forge/routines/loop.json", {"name": "loop", "schedule": "daily", "steps": ["check"], "status": "active"})
open(root + "/bots/atlas/journal/2026-11-07.md", "w").write("- 09:00 seeded\n")
open(root + "/bots/atlas/memory.md", "w").write("base\n")
open(root + "/local/overrides.md", "w").write("base\n")
open(root + "/README.md", "w").write("# test fleet\n")
PY

git init -q -b main "$REPO"
git init -q --bare -b main "$REMOTE"
git -C "$REPO" config user.email test@example.invalid
git -C "$REPO" config user.name test
git -C "$REPO" config commit.gpgsign false
git -C "$REPO" config fleet.bot atlas
git -C "$REPO" config fleet.role worker
git -C "$REPO" add -A
git -C "$REPO" commit -qm "init"
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" push -q origin HEAD:main
(cd "$REPO" && fleet/scripts/install-hook.sh)

common="$(git -C "$REPO" rev-parse --git-common-dir)"
case "$common" in
  /*) ;;
  *) common="$REPO/$common" ;;
esac
HOOK="$common/hooks/pre-commit"
python3 - "$HOOK" "$SRC/fleet/scripts/install-hook.sh" << 'PY'
import sys
hook, src = open(sys.argv[1]).read(), open(sys.argv[2]).read()
need = [
    'for s in "$top/local/shared/scripts/confidential-scan.sh" "$top/fleet/scripts/confidential-scan.sh"; do',
    '[ -f "$s" ] && { bash "$s" --staged || exit 1; break; }',
    'exec bash "$top/fleet/scripts/check-boundary.sh"',
    'bash "$top/fleet/scripts/check-staged-config.sh" || exit 1',
]
for n in need:
    if n not in hook or n not in src:
        sys.exit("hook missing %r" % n)
order = ["confidential-scan.sh", "check-staged-config.sh", "check-boundary.sh"]
pos = [hook.index(x) for x in order]
if pos != sorted(pos):
    sys.exit("hook order %s" % order)
PY
pass "hook keeps confidential scan and check-boundary.sh, and runs the schema check between them"

clean() {
  # skip-worktree hides a dirty schema from reset --hard; clear it before restoring.
  git -C "$REPO" update-index --no-skip-worktree -- \
    fleet/schema/fleet.schema.json fleet/schema/profile.schema.json fleet/schema/state.schema.json \
    fleet/schema/routine.schema.json fleet/schema/owners.schema.json fleet/schema/bot.schema.json \
    fleet/scripts/schema_check.py >/dev/null 2>&1 || true
  git -C "$REPO" fetch -q origin main
  git -C "$REPO" reset -q --hard FETCH_HEAD
  git -C "$REPO" clean -fdq
}
head_sha() { git -C "$REPO" rev-parse HEAD; }
remote_sha() { git -C "$REMOTE" rev-parse refs/heads/main; }
names_of() { git -C "$REPO" show --name-only --format= "$1" | sed '/^$/d'; }

capture() {
  CAP_FILE="$(mktemp)"
  set +e
  "$@" >"$CAP_FILE" 2>&1
  CAP_RC=$?
  set -e
  CAP="$(cat "$CAP_FILE")"
  rm -f "$CAP_FILE"
}
hook_commit() { # role slug message
  capture env BOT_NAME="$2" BOT_ROLE="$1" git -C "$REPO" commit -qm "$3"
}
check_run() {
  CAP_FILE="$(mktemp)"
  set +e
  (cd "$REPO" && fleet/scripts/check-staged-config.sh) >"$CAP_FILE" 2>&1
  CAP_RC=$?
  set -e
  CAP="$(cat "$CAP_FILE")"
  rm -f "$CAP_FILE"
}
sync_run() { # role slug message [paths...]
  local role="$1" slug="$2" msg="$3"
  shift 3
  CAP_FILE="$(mktemp)"
  set +e
  (cd "$REPO" && BOT_NAME="$slug" BOT_ROLE="$role" fleet/scripts/sync.sh "$msg" "$@") >"$CAP_FILE" 2>&1
  CAP_RC=$?
  set -e
  CAP="$(cat "$CAP_FILE")"
  rm -f "$CAP_FILE"
}
mutate() { # path kind value   kind: routine|bot|fleet|schedule
  python3 - "$REPO/$1" "$2" "$3" << 'PY'
import json, sys
path, kind, value = sys.argv[1:]
j = json.load(open(path))
if kind == "routine":
    j["status"] = value
elif kind == "bot":
    j["status"] = value
elif kind == "fleet":
    j["bots"][0]["status"] = value
elif kind == "schedule":
    j["schedule"] = value
else:
    sys.exit("bad kind")
json.dump(j, open(path, "w"), indent=2)
open(path, "a").write("\n")
PY
}
assert_refs_same() {
  local h r
  h="$(head_sha)"; r="$(remote_sha)"
  [ "$h" = "$BEFORE" ] && [ "$r" = "$RBEFORE" ] || fail "$1: refs moved HEAD $BEFORE->$h remote $RBEFORE->$r
$CAP"
}
assert_blocked() { # label
  [ "$CAP_RC" != 0 ] || fail "$1: expected non-zero, got output:
$CAP"
  printf '%s\n' "$CAP" | grep -q "check-staged-config: refusing commit" || fail "$1: missing refusal
$CAP"
  assert_refs_same "$1"
}
snap() { BEFORE="$(head_sha)"; RBEFORE="$(remote_sha)"; }

# Same failure text as a direct jsonschema.validate of the working-tree file.
clean
mutate bots/atlas/routines/loop.json routine pause_recommended
(cd "$REPO" && python3 - << 'PY'
import json, sys
sys.path.insert(0, "fleet/scripts")
import jsonschema, schema_check
path = "bots/atlas/routines/loop.json"
schema = json.load(open("fleet/schema/routine.schema.json"))
msg = schema_check.check_file(path, "routine")
try:
    jsonschema.validate(json.load(open(path)), schema)
    inline = None
except Exception as e:
    inline = "FAIL %s: %s" % (path, str(e).splitlines()[0])
if msg != inline or not msg or "pause_recommended" not in msg:
    sys.exit("message mismatch\ncheck_file=%r\ninline=%r" % (msg, inline))
PY
) || fail "check_file message != jsonschema.validate"
# Not staged: the staged checker must not read this working-tree edit.
check_run
[ "$CAP_RC" = 0 ] || fail "unstaged invalid routine was checked
$CAP"
printf '%s\n' "$CAP" | grep -q "loop.json" && fail "unstaged path mentioned: $CAP" || true
pass "check_file matches jsonschema.validate; unstaged working tree is not checked"

# --- hook: each invalid staged config blocks commit; remote stays ---
block_hook() { # label role slug path kind
  local label="$1" role="$2" slug="$3" path="$4" kind="$5"
  clean; snap
  mutate "$path" "$kind" pause_recommended
  git -C "$REPO" add -- "$path"
  hook_commit "$role" "$slug" "$label"
  assert_blocked "$label"
  printf '%s\n' "$CAP" | grep -q "FAIL $path" || fail "$label: message missing path
$CAP"
  if [ "$kind" = bot ]; then
    printf '%s\n' "$CAP" | grep -q "status" || fail "$label: bot.json error should name status
$CAP"
  else
    printf '%s\n' "$CAP" | grep -q "pause_recommended" || fail "$label: missing pause_recommended
$CAP"
  fi
  pass "$label"
}
block_hook "hook blocks invalid staged routine" worker atlas bots/atlas/routines/loop.json routine
block_hook "hook blocks invalid staged bot.json" worker atlas bots/atlas/bot.json bot
block_hook "hook blocks invalid staged fleet.json" manager atlas local/fleet.json fleet

# Both routine and fleet reported in one refusal.
clean; snap
mutate bots/atlas/routines/loop.json routine pause_recommended
mutate local/fleet.json fleet pause_recommended
git -C "$REPO" add -- bots/atlas/routines/loop.json local/fleet.json
hook_commit manager atlas "both bad"
assert_blocked "hook reports every staged failure"
printf '%s\n' "$CAP" | grep -q "FAIL bots/atlas/routines/loop.json" || fail "missing routine line: $CAP"
printf '%s\n' "$CAP" | grep -q "FAIL local/fleet.json" || fail "missing fleet line: $CAP"
pass "hook reports invalid routine and fleet.json together"

# Index blob, not the working tree.
clean; snap
mutate bots/atlas/routines/loop.json routine pause_recommended
git -C "$REPO" add -- bots/atlas/routines/loop.json
mutate bots/atlas/routines/loop.json routine active
git -C "$REPO" show :bots/atlas/routines/loop.json | grep -q pause_recommended || fail "index blob was not pause_recommended"
grep -q '"status": "active"' "$REPO/bots/atlas/routines/loop.json" || fail "worktree was not restored to active"
hook_commit worker atlas "index bad worktree good"
assert_blocked "hook follows the index when the worktree is valid"
printf '%s\n' "$CAP" | grep -q "pause_recommended" || fail "index error missing pause_recommended: $CAP"
pass "hook blocks a staged invalid blob while the worktree file is valid"

clean; snap
mutate bots/atlas/routines/loop.json schedule hourly
git -C "$REPO" add -- bots/atlas/routines/loop.json
mutate bots/atlas/routines/loop.json routine pause_recommended
grep -q pause_recommended "$REPO/bots/atlas/routines/loop.json" || fail "worktree should be invalid"
git -C "$REPO" show :bots/atlas/routines/loop.json | grep -q hourly || fail "index should be the valid schedule"
hook_commit worker atlas "index good worktree bad"
[ "$CAP_RC" = 0 ] || fail "valid index blob was blocked
$CAP"
git -C "$REPO" show HEAD:bots/atlas/routines/loop.json | grep -q hourly || fail "commit missed the staged schedule"
git -C "$REPO" show HEAD:bots/atlas/routines/loop.json | grep -q pause_recommended && fail "commit took the worktree status" || true
grep -q pause_recommended "$REPO/bots/atlas/routines/loop.json" || fail "invalid worktree edit was lost"
git -C "$REPO" diff --name-only -- bots/atlas/routines/loop.json | grep -q loop.json || fail "worktree edit should remain unstaged"
pass "hook commits the valid staged blob and leaves the invalid worktree edit unstaged"

# Valid config still commits. Journal (non-config) still commits.
clean; snap
mutate bots/atlas/routines/loop.json schedule hourly
git -C "$REPO" add -- bots/atlas/routines/loop.json
hook_commit worker atlas "valid routine"
[ "$CAP_RC" = 0 ] || fail "valid routine commit failed
$CAP"
git -C "$REPO" show HEAD:bots/atlas/routines/loop.json | grep -q hourly || fail "hourly schedule not committed"
pass "valid staged routine still commits"

clean
printf -- '- 12:00 journal only\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
git -C "$REPO" add -- bots/atlas/journal/2026-11-07.md
hook_commit worker atlas "journal"
[ "$CAP_RC" = 0 ] || fail "journal commit failed
$CAP"
pass "staged journal commits"

# Invalid unstaged and untracked files are not checked and not committed.
clean; snap
mutate bots/atlas/routines/loop.json routine pause_recommended
mkdir -p "$REPO/bots/atlas/routines"
python3 - "$REPO/bots/atlas/routines/untracked.json" << 'PY'
import json, sys
json.dump({"name": "untracked", "schedule": "daily", "steps": ["x"], "status": "pause_recommended"}, open(sys.argv[1], "w"), indent=2)
PY
printf -- '- 12:05 beside invalid files\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
git -C "$REPO" add -- bots/atlas/journal/2026-11-07.md
check_run
[ "$CAP_RC" = 0 ] || fail "checker looked at unstaged or untracked JSON
$CAP"
printf '%s\n' "$CAP" | grep -q "pause_recommended" && fail "checker mentioned an unstaged value: $CAP" || true
printf '%s\n' "$CAP" | grep -q "untracked.json" && fail "checker mentioned untracked file: $CAP" || true
hook_commit worker atlas "journal beside invalid"
[ "$CAP_RC" = 0 ] || fail "journal commit blocked by unstaged/untracked JSON
$CAP"
names_of HEAD | grep -q "bots/atlas/journal/2026-11-07.md" || fail "journal missing from commit"
names_of HEAD | grep -q "loop.json" && fail "unstaged routine was committed" || true
names_of HEAD | grep -q "untracked.json" && fail "untracked routine was committed" || true
git -C "$REPO" status --porcelain -- bots/atlas/routines/untracked.json | grep -q '^??' || fail "untracked file was not left untracked"
git -C "$REPO" diff --name-only -- bots/atlas/routines/loop.json | grep -q loop.json || fail "invalid routine should remain unstaged"
pass "unstaged and untracked invalid JSON are not checked and not committed"

# Deleting a routine has no staged blob and is allowed.
clean
git -C "$REPO" rm -q bots/atlas/routines/loop.json
hook_commit worker atlas "delete routine"
[ "$CAP_RC" = 0 ] || fail "deleting a routine was blocked
$CAP"
git -C "$REPO" cat-file -e HEAD:bots/atlas/routines/loop.json 2>/dev/null && fail "deleted routine still in HEAD" || true
pass "staged deletion of a routine is not schema-checked"

# --- sync.sh ---
block_sync() { # label role slug path kind
  local label="$1" role="$2" slug="$3" path="$4" kind="$5"
  clean; snap
  mutate "$path" "$kind" pause_recommended
  sync_run "$role" "$slug" "$label"
  assert_blocked "$label"
  printf '%s\n' "$CAP" | grep -q "sync: refusing commit and push" || fail "$label: missing sync refusal
$CAP"
  printf '%s\n' "$CAP" | grep -q "FAIL $path" || fail "$label: missing path
$CAP"
  git -C "$REPO" log -1 --format=%s | grep -q "init" || fail "$label: a commit was created: $(git -C "$REPO" log -1 --format=%s)"
  pass "$label"
}
block_sync "sync blocks invalid staged routine before commit and push" worker atlas bots/atlas/routines/loop.json routine
block_sync "sync blocks invalid staged bot.json before commit and push" worker atlas bots/atlas/bot.json bot
block_sync "sync blocks invalid staged fleet.json before commit and push" manager atlas local/fleet.json fleet

# sync refuses the index blob even when the worktree copy was put back to valid,
# and an explicit journal path does not refresh that staged blob.
clean; snap
mutate bots/atlas/routines/loop.json routine pause_recommended
git -C "$REPO" add -- bots/atlas/routines/loop.json
mutate bots/atlas/routines/loop.json routine active
printf -- '- 12:10 index still bad\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
sync_run worker atlas "journal only" bots/atlas/journal/2026-11-07.md
assert_blocked "sync checks the staged routine blob, not the valid worktree"
printf '%s\n' "$CAP" | grep -q "pause_recommended" || fail "sync missed the index value: $CAP"
grep -q '"status": "active"' "$REPO/bots/atlas/routines/loop.json" || fail "worktree should still be valid"
pass "sync.sh blocks a staged invalid blob while the worktree file is valid"

clean; snap
mutate bots/atlas/routines/loop.json schedule hourly
sync_run worker atlas "valid routine"
[ "$CAP_RC" = 0 ] || fail "valid sync failed
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "valid sync did not push: $CAP"
[ "$(head_sha)" = "$(remote_sha)" ] || fail "valid sync remote mismatch"
git -C "$REMOTE" show HEAD:bots/atlas/routines/loop.json | grep -q hourly || fail "remote missed hourly schedule"
pass "valid staged routine still commits and pushes through sync.sh"

clean; snap
printf -- '- 12:15 journal sync\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
sync_run worker atlas "journal"
[ "$CAP_RC" = 0 ] || fail "journal sync failed
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "journal sync did not push: $CAP"
git -C "$REMOTE" show HEAD:bots/atlas/journal/2026-11-07.md | grep -q "12:15" || fail "journal not pushed"
pass "non-config journal changes still commit and push through sync.sh"

# Untracked invalid file inside the add path is staged by existing git add, then blocked.
clean; snap
python3 - "$REPO/bots/atlas/routines/evil.json" << 'PY'
import json, sys
json.dump({"name": "evil", "schedule": "daily", "steps": ["x"], "status": "pause_recommended"}, open(sys.argv[1], "w"), indent=2)
PY
printf -- '- 12:20 would stage evil\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
sync_run worker atlas "inside untracked"
assert_blocked "sync stages untracked files inside bots/<me> and then schema-checks them"
printf '%s\n' "$CAP" | grep -q "FAIL bots/atlas/routines/evil.json" || fail "inside untracked file was not checked
$CAP"
git -C "$REPO" cat-file -e HEAD:bots/atlas/routines/evil.json 2>/dev/null && fail "evil.json was committed" || true
pass "untracked invalid routine inside the sync path is staged by git add, then blocked, and not committed"

# Untracked invalid file outside the add path is not staged, not checked, and not committed.
clean; snap
mkdir -p "$REPO/bots/forge/routines"
python3 - "$REPO/bots/forge/routines/evil.json" << 'PY'
import json, sys
json.dump({"name": "evil", "schedule": "daily", "steps": ["x"], "status": "pause_recommended"}, open(sys.argv[1], "w"), indent=2)
PY
printf -- '- 12:25 outside untracked\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
sync_run worker atlas "outside untracked"
[ "$CAP_RC" = 0 ] || fail "outside untracked file blocked sync
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "outside untracked did not push: $CAP"
printf '%s\n' "$CAP" | grep -q "evil.json" && fail "outside untracked file was checked: $CAP" || true
printf '%s\n' "$CAP" | grep -q "pause_recommended" && fail "outside value was checked: $CAP" || true
names_of HEAD | grep -q "evil.json" && fail "outside untracked file was committed" || true
[ -f "$REPO/bots/forge/routines/evil.json" ] || fail "outside file disappeared"
git -C "$REPO" status --porcelain -- bots/forge/routines/evil.json | grep -q '^??' || fail "outside file should stay untracked"
pass "untracked invalid JSON outside sync's paths is not checked, not committed, and does not block push"

# Tracked unstaged edit outside the add paths is not committed and not checked.
# Existing rebase then refuses, so this run does not push.
clean; snap
mutate local/fleet.json fleet pause_recommended
printf -- '- 12:30 tracked outside\n' >> "$REPO/bots/atlas/memory.md"
sync_run worker atlas "memory only"
[ "$CAP_RC" != 0 ] || fail "dirty tracked file outside the path should keep rebase from pushing
$CAP"
printf '%s\n' "$CAP" | grep -q "check-staged-config: refusing commit" && fail "unstaged fleet.json was schema-checked
$CAP" || true
printf '%s\n' "$CAP" | grep -q "pause_recommended" && fail "unstaged value was checked: $CAP" || true
printf '%s\n' "$CAP" | grep -q "unstaged changes" || fail "expected existing rebase refusal
$CAP"
[ "$(head_sha)" != "$BEFORE" ] || fail "in-path memory change was not committed"
[ "$(remote_sha)" = "$RBEFORE" ] || fail "push happened despite a dirty worktree"
names_of HEAD | grep -qx "bots/atlas/memory.md" || fail "commit files were not only memory.md: $(names_of HEAD)"
git -C "$REPO" diff --name-only -- local/fleet.json | grep -q "local/fleet.json" || fail "fleet.json should remain unstaged"
pass "sync.sh commits only its paths; an unstaged invalid fleet.json stays out and is not checked (rebase then does not push)"

# Explicit path: sibling unstaged invalid routine is not added.
clean; snap
mutate bots/atlas/routines/loop.json routine pause_recommended
echo dirty-memory >> "$REPO/bots/atlas/memory.md"
printf -- '- 12:35 explicit journal\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
sync_run worker atlas "explicit journal" bots/atlas/journal/2026-11-07.md
[ "$CAP_RC" != 0 ] || fail "explicit-path sync should not push while other tracked files are dirty
$CAP"
printf '%s\n' "$CAP" | grep -q "check-staged-config" && fail "explicit path checked an unstaged routine
$CAP" || true
names_of HEAD | grep -qx "bots/atlas/journal/2026-11-07.md" || fail "explicit commit files: $(names_of HEAD)"
git -C "$REPO" diff --name-only | grep -q "loop.json" || fail "routine should remain unstaged"
git -C "$REPO" diff --name-only | grep -q "memory.md" || fail "memory should remain unstaged"
[ "$(remote_sha)" = "$RBEFORE" ] || fail "explicit-path sync pushed despite dirty files"
pass "sync.sh with an explicit path does not stage or check sibling unstaged files"

# Manager default paths, including a slug whose bots/<me> directory does not exist.
clean; snap
echo edited >> "$REPO/local/overrides.md"
echo '# edited readme' > "$REPO/README.md"
echo extra > "$REPO/local/extra.md"
mkdir -p "$REPO/bots/forge/routines"
python3 - "$REPO/bots/forge/routines/evil.json" << 'PY'
import json, sys
json.dump({"name": "evil", "schedule": "daily", "steps": ["x"], "status": "pause_recommended"}, open(sys.argv[1], "w"), indent=2)
PY
# ghost has no bots/ghost directory, so manager stages local/ and README.md only.
# The forge routine stays untracked (a tracked edit outside the path would also stay
# unstaged, and existing git rebase would then refuse to push).
sync_run manager ghost "manager paths"
[ "$CAP_RC" = 0 ] || fail "manager sync failed
$CAP"
printf '%s\n' "$CAP" | grep -q "sync: pushed" || fail "manager sync did not push: $CAP"
printf '%s\n' "$CAP" | grep -q "pause_recommended\|evil.json\|loop.json" && fail "manager sync checked files outside its paths
$CAP" || true
got="$(names_of HEAD | sort)"
want="$(printf '%s\n' README.md local/extra.md local/overrides.md | sort)"
[ "$got" = "$want" ] || fail "manager commit files:
$got
want:
$want"
git -C "$REPO" status --porcelain -- bots/forge/routines/evil.json | grep -q '^??' || fail "forge evil.json should stay untracked"
pass "manager sync stages local/, README.md, and untracked files under local/; no bots/<me> dir means bots/ is not added"

# Worker default path stages untracked files inside bots/<me> and not local/ or README.
clean; snap
echo worker-note >> "$REPO/bots/atlas/memory.md"
echo extra-atlas > "$REPO/bots/atlas/note.txt"
echo edited >> "$REPO/local/overrides.md"
echo '# not me' > "$REPO/README.md"
sync_run worker atlas "worker paths"
# local/overrides.md and README stay dirty, so rebase does not push. The commit is still only bots/atlas.
[ "$(head_sha)" != "$BEFORE" ] || fail "worker sync did not commit"
[ "$(remote_sha)" = "$RBEFORE" ] || fail "worker sync pushed files it should have left unstaged, or pushed despite a dirty tree"
got="$(names_of HEAD | sort)"
want="$(printf '%s\n' bots/atlas/memory.md bots/atlas/note.txt | sort)"
[ "$got" = "$want" ] || fail "worker commit files:
$got
want:
$want"
git -C "$REPO" diff --name-only | grep -q "local/overrides.md" || fail "overrides should remain unstaged"
git -C "$REPO" diff --name-only | grep -q "README.md" || fail "README should remain unstaged"
pass "worker sync stages bots/<fleet.bot>/ only, including untracked files there; local/ and README stay unstaged"

# --- fail closed: type changes, untrusted schemas, shadowed imports, SystemExit(0) ---

# ACMR omits type changes. A tracked routine replaced by a symlink must still be refused.
clean; snap
rm "$REPO/bots/atlas/routines/loop.json"
ln -s /tmp/not-a-routine "$REPO/bots/atlas/routines/loop.json"
git -C "$REPO" add -- bots/atlas/routines/loop.json
if git -C "$REPO" diff --cached --name-only --diff-filter=ACMR -- bots/atlas/routines/loop.json | grep -q .; then
  fail "diff-filter ACMR listed the symlink type change"
fi
git -C "$REPO" diff --cached --raw -- bots/atlas/routines/loop.json | grep -q 120000 || fail "staged routine was not mode 120000"
hook_commit worker atlas "symlink routine"
assert_blocked "hook blocks a routine replaced by a symlink"
printf '%s\n' "$CAP" | grep -q "120000" || fail "hook did not name mode 120000:
$CAP"
sync_run worker atlas "symlink routine"
assert_blocked "sync does not push a routine replaced by a symlink"
printf '%s\n' "$CAP" | grep -q "sync: refusing commit and push" || fail "sync missed the symlink refusal:
$CAP"
printf '%s\n' "$CAP" | grep -q "120000" || fail "sync did not name mode 120000:
$CAP"
git -C "$REMOTE" show HEAD:bots/atlas/routines/loop.json | grep -q '"status": "active"' || fail "remote routine changed"
pass "symlink type change is refused by the hook and by sync; remote unchanged"

# Gitlink (160000) is also a type change ACMR drops. Commit would record it without git add rewriting the index.
clean; snap
sha="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-index --add --cacheinfo "160000,$sha,bots/atlas/routines/loop.json"
if git -C "$REPO" diff --cached --name-only --diff-filter=ACMR -- bots/atlas/routines/loop.json | grep -q .; then
  fail "diff-filter ACMR listed the gitlink type change"
fi
git -C "$REPO" ls-files --stage -- bots/atlas/routines/loop.json | grep -q '^160000' || fail "index was not a gitlink"
hook_commit worker atlas "gitlink routine"
assert_blocked "hook blocks a routine replaced by a gitlink"
printf '%s\n' "$CAP" | grep -q "160000" || fail "hook did not name mode 160000:
$CAP"
pass "gitlink mode is refused; nothing is committed or pushed"

# Regular executable files stay allowed.
clean
git -C "$REPO" update-index --chmod=+x -- bots/atlas/routines/loop.json
hook_commit worker atlas "executable routine"
[ "$CAP_RC" = 0 ] || fail "mode 100755 was refused:
$CAP"
git -C "$REPO" ls-tree HEAD -- bots/atlas/routines/loop.json | grep -q '^100755' || fail "commit did not keep mode 100755"
pass "mode 100755 still commits"

# Unstaged schema loosened to true. The index schema stays strict.
clean; snap
printf 'true\n' > "$REPO/fleet/schema/routine.schema.json"
grep -qx 'true' "$REPO/fleet/schema/routine.schema.json" || fail "worktree schema was not loosened"
git -C "$REPO" show :fleet/schema/routine.schema.json | grep -q '"enum"' || fail "index schema was not the strict one"
mutate bots/atlas/routines/loop.json routine pause_recommended
sync_run worker atlas "dirty schema"
assert_blocked "dirty worktree schema does not admit pause_recommended"
printf '%s\n' "$CAP" | grep -q "pause_recommended" || fail "strict index schema did not reject the value:
$CAP"
if git -C "$REPO" diff --cached --name-only -- fleet/schema/routine.schema.json | grep -q .; then
  fail "dirty schema was staged"
fi
pass "unstaged schema edited to true does not admit an invalid routine"

# skip-worktree hides the same looseness from git diff and git status.
clean; snap
git -C "$REPO" update-index --skip-worktree -- fleet/schema/routine.schema.json
printf 'true\n' > "$REPO/fleet/schema/routine.schema.json"
if git -C "$REPO" diff -- fleet/schema/routine.schema.json | grep -q .; then
  fail "skip-worktree schema diff was visible"
fi
if git -C "$REPO" status --porcelain -- fleet/schema/routine.schema.json | grep -q .; then
  fail "skip-worktree schema showed in status"
fi
mutate bots/atlas/routines/loop.json routine pause_recommended
sync_run worker atlas "skip-worktree schema"
assert_blocked "skip-worktree schema does not admit pause_recommended"
printf '%s\n' "$CAP" | grep -q "pause_recommended" || fail "skip-worktree schema was the one that validated:
$CAP"
pass "skip-worktree schema edited to true does not admit an invalid routine"

# The refused commit must not become an ancestor that a later sync pushes once the schema is restored.
clean; snap
printf 'true\n' > "$REPO/fleet/schema/routine.schema.json"
mutate bots/atlas/routines/loop.json routine pause_recommended
printf -- '- 12:40 would-be ancestor\n' >> "$REPO/bots/atlas/journal/2026-11-07.md"
sync_run worker atlas "dirty schema first"
assert_blocked "dirty schema did not refuse the invalid routine"
git -C "$REPO" checkout -q -- fleet/schema/routine.schema.json
git -C "$REPO" show :fleet/schema/routine.schema.json | grep -q '"enum"' || fail "restored schema is not the strict index blob"
grep -q '"enum"' "$REPO/fleet/schema/routine.schema.json" || fail "worktree schema was not restored"
sync_run worker atlas "restore then sync"
assert_blocked "restore then sync pushed a bad ancestor"
git -C "$REMOTE" show HEAD:bots/atlas/routines/loop.json | grep -q '"status": "active"' || fail "remote routine is not the original"
git -C "$REMOTE" show HEAD:bots/atlas/routines/loop.json | grep -q pause_recommended && fail "remote routine contains pause_recommended" || true
git -C "$REMOTE" show HEAD:bots/atlas/journal/2026-11-07.md | grep -q '12:40' && fail "journal reached the remote with the bad ancestor" || true
pass "restoring a dirty schema and syncing does not push the invalid routine"

# A schema symlink whose link text is "true" is a boolean schema if the blob is parsed. Mode must win.
clean; snap
rm "$REPO/fleet/schema/routine.schema.json"
ln -s true "$REPO/fleet/schema/routine.schema.json"
git -C "$REPO" add -- fleet/schema/routine.schema.json
git -C "$REPO" ls-files --stage -- fleet/schema/routine.schema.json | grep -q '^120000' || fail "schema was not staged as a symlink"
mutate bots/atlas/routines/loop.json routine pause_recommended
sync_run worker atlas "symlink schema"
assert_blocked "symlink schema true admitted pause_recommended"
printf '%s\n' "$CAP" | grep -q "120000" || fail "symlink schema was not refused by mode:
$CAP"
pass "a schema staged as a symlink is refused; remote unchanged"

# Untracked fleet/scripts/jsonschema.py would shadow python fleet/scripts/schema_check.py and no-op validate.
clean; snap
cat > "$REPO/fleet/scripts/jsonschema.py" << 'PY'
def validate(instance, schema):
    return None
PY
mutate bots/atlas/routines/loop.json routine pause_recommended
sync_run worker atlas "shadow jsonschema"
assert_blocked "untracked jsonschema.py no-op"
printf '%s\n' "$CAP" | grep -E -q 'jsonschema.py|pause_recommended' || fail "shadow was not refused:
$CAP"
git -C "$REPO" status --porcelain -- fleet/scripts/jsonschema.py | grep -q '^??' || fail "shadow file was not left untracked"
git -C "$REPO" cat-file -e HEAD:fleet/scripts/jsonschema.py 2>/dev/null && fail "shadow module was committed" || true
git -C "$REMOTE" cat-file -e HEAD:fleet/scripts/jsonschema.py 2>/dev/null && fail "shadow module was pushed" || true
pass "untracked fleet/scripts/jsonschema.py cannot no-op the checker or get pushed"

# SystemExit(0) from the real validator function is a failure, and the staged blob still does not push.
clean; snap
mutate bots/atlas/routines/loop.json routine pause_recommended
git -C "$REPO" add -- bots/atlas/routines/loop.json
marker="$T/sysexit-marker"
rm -f "$marker"
set +e
(cd "$REPO" && python3 - "$marker" << 'PY'
import io, sys
sys.path.insert(0, "fleet/scripts")
import schema_check
real = schema_check.load_index_schemas
def wrapped():
    mod, schemas = real()
    def boom(instance, schema):
        raise SystemExit(0)
    mod.validate = boom
    return mod, schemas
schema_check.load_index_schemas = wrapped
out, err = io.StringIO(), io.StringIO()
old_out, old_err = sys.stdout, sys.stderr
sys.stdout, sys.stderr = out, err
try:
    rc = schema_check.main_staged()
finally:
    sys.stdout, sys.stderr = old_out, old_err
text_out, text_err = out.getvalue(), err.getvalue()
if rc != 0 and "check-staged-config: pass" not in text_out and "validator SystemExit(0) is not a pass" in text_err:
    open(sys.argv[1], "w").write(text_err)
    sys.exit(0)
sys.stderr.write("rc=%r\nout=%r\nerr=%r\n" % (rc, text_out, text_err))
sys.exit(1)
PY
)
py_rc=$?
set -e
[ -f "$marker" ] || fail "SystemExit(0) counted as success (python rc=$py_rc)"
sync_run worker atlas "after SystemExit"
assert_blocked "SystemExit(0) sync"
printf '%s\n' "$CAP" | grep -q "sync: refusing commit and push" || fail "sync pushed after SystemExit:
$CAP"
pass "validator SystemExit(0) is not a pass and sync does not push"

# A tracked checker that exits 0 on import must not satisfy the pass signal, and must not be pushed.
clean; snap
printf 'raise SystemExit(0)\n' > "$REPO/fleet/scripts/schema_check.py"
git -C "$REPO" add -- fleet/scripts/schema_check.py
git -C "$REPO" commit -qm "hostile checker" --no-verify
BEFORE="$(head_sha)"
mutate bots/atlas/routines/loop.json routine pause_recommended
sync_run worker atlas "hostile SystemExit"
assert_blocked "hostile checker SystemExit(0)"
printf '%s\n' "$CAP" | grep -q "validator SystemExit(0) is not a pass" || fail "shell treated SystemExit(0) as a pass:
$CAP"
git -C "$REPO" show HEAD:fleet/scripts/schema_check.py | grep -q "raise SystemExit" || fail "hostile checker was not what ran"
git -C "$REMOTE" show HEAD:fleet/scripts/schema_check.py | grep -q "raise SystemExit" && fail "hostile checker reached the remote" || true
git -C "$REMOTE" show HEAD:bots/atlas/routines/loop.json | grep -q pause_recommended && fail "remote routine contains pause_recommended" || true
pass "SystemExit(0) from the checker is not a pass and nothing reaches the remote"

# skip-worktree can hide a no-op checker from git status. The worktree bytes must match the index blob.
clean; snap
git -C "$REPO" update-index --skip-worktree -- fleet/scripts/schema_check.py
cat > "$REPO/fleet/scripts/schema_check.py" << 'PY'
import sys
def main_staged():
    sys.stdout.write("check-staged-config: pass\n")
    return 0
PY
if git -C "$REPO" status --porcelain -- fleet/scripts/schema_check.py | grep -q .; then
  fail "skip-worktree checker showed in status"
fi
mutate bots/atlas/routines/loop.json routine pause_recommended
sync_run worker atlas "skip-worktree checker"
assert_blocked "skip-worktree checker no-op"
printf '%s\n' "$CAP" | grep -q "schema_check.py is not tracked and clean" || fail "dirty checker was executed:
$CAP"
pass "a skip-worktree no-op checker cannot admit an invalid routine"

# Upgrade commits a new schema_check.py (worktree matches the index, HEAD does not) with the hook installed.
clean; snap
printf '\n# upgrade marker\n' >> "$REPO/fleet/scripts/schema_check.py"
git -C "$REPO" add -- fleet/scripts/schema_check.py
capture env BOT_NAME=atlas BOT_ROLE=manager BOT_FLEET_UPGRADE=1 git -C "$REPO" commit -qm "upgrade checker"
[ "$CAP_RC" = 0 ] || fail "upgrade could not commit a clean staged checker:
$CAP"
[ "$(head_sha)" != "$BEFORE" ] || fail "upgrade commit did not happen"
[ "$(remote_sha)" = "$RBEFORE" ] || fail "upgrade commit was pushed"
git -C "$REPO" show HEAD:fleet/scripts/schema_check.py | grep -q "upgrade marker" || fail "committed checker is not the staged blob"
pass "a checker staged clean against the index still commits under the upgrade hook"

echo
echo "staged-config tests: $pass_n passed"
[ "$pass_n" -ge 37 ]
