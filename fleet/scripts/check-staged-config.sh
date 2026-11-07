#!/usr/bin/env bash
# Schema-check staged configuration JSON before commit.
# Instances and schemas are index blobs (git cat-file), one snapshot. An unchanged
# schema's index blob is HEAD. The worktree copy is never the schema source.
# Config paths and schema blobs must be mode 100644 or 100755. Type changes (T),
# symlinks (120000), gitlinks (160000), and any other mode fail closed.
# Deletions are not checked. Other staged paths (journals, prose) are ignored.
#
# Imports: python3 -I, then an explicit directory that holds only the index blob of
# fleet/scripts/schema_check.py. That file must be tracked and clean (worktree
# bytes match the index blob, which is HEAD when the file is unchanged). An untracked or dirty
# fleet/scripts/jsonschema.py cannot shadow the installed validator.
# Success is exit 0 and stdout exactly "check-staged-config: pass".
# SystemExit(0) is not that signal.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
export PYTHONDONTWRITEBYTECODE=1

lib="$(mktemp -d "${TMPDIR:-/tmp}/staged-config.XXXXXX")"
outf="$(mktemp)"
errf="$(mktemp)"
cleanup() { rm -rf "$lib"; rm -f "$outf" "$errf"; }
trap cleanup EXIT

set +e
python3 -I - "$lib" >"$outf" 2>"$errf" <<'PY'
import os, site, subprocess, sys
sys.dont_write_bytecode = True
lib = sys.argv[1]

class Refuse(Exception):
    pass

def fail(msg):
    raise Refuse(msg)

def git(args):
    env = os.environ.copy()
    env["GIT_LITERAL_PATHSPECS"] = "1"
    return subprocess.check_output(args, env=env)

def repo_root():
    return subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()

os.chdir(repo_root())
rootp = os.path.realpath(os.getcwd())

def real(path):
    return os.path.realpath(path)

def in_repo(path):
    rp = real(path)
    return rp == rootp or rp.startswith(rootp + os.sep)

def index_entry(path):
    out = git(["git", "ls-files", "--stage", "-z", "--", path])
    recs = [r for r in out.split(b"\0") if r]
    if len(recs) != 1 or b"\t" not in recs[0]:
        return None
    meta, sp = recs[0].split(b"\t", 1)
    if sp.decode("utf-8", "surrogateescape") != path:
        return None
    parts = meta.decode().split()
    if len(parts) != 3 or parts[2] != "0":
        return None
    return parts[0], parts[1]

def tracked_and_clean(path):
    """Tracked regular file whose worktree bytes match the index blob.
    That blob is what this commit will record (HEAD, when the path is unchanged).
    skip-worktree and assume-unchanged do not hide a content mismatch, so a dirty
    copy cannot run in place of the index blob.
    """
    ent = index_entry(path)
    if ent is None or ent[0] not in ("100644", "100755"):
        return False
    sha = ent[1]
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    work = subprocess.check_output(["git", "hash-object", "--", path], text=True).strip()
    return work == sha

MOD = "fleet/scripts/schema_check.py"
SHADOWS = (
    "fleet/scripts/jsonschema.py",
    "fleet/scripts/jsonschema/__init__.py",
    "jsonschema.py",
)

try:
    if not tracked_and_clean(MOD):
        fail("fleet/scripts/schema_check.py is not tracked and clean (worktree must match the index blob, and the index blob must be a regular file)")
    for shadow in SHADOWS:
        if os.path.lexists(shadow) and not tracked_and_clean(shadow):
            fail("untrusted module %s can shadow the validator (not tracked and clean)" % shadow)
    _mode, sha = index_entry(MOD)
    blob = subprocess.check_output(["git", "cat-file", "blob", sha])
    dest = os.path.join(lib, "schema_check.py")
    with open(dest, "wb") as fh:
        fh.write(blob)
    os.chmod(dest, 0o644)
    got = subprocess.check_output(["git", "hash-object", "--", dest], text=True).strip()
    if got != sha:
        fail("extracted validator blob does not match the index")

    kept = []
    for p in sys.path:
        if not p or not os.path.isabs(p) or in_repo(p):
            continue
        kept.append(p)
    user_site = site.getusersitepackages()
    if isinstance(user_site, str) and os.path.isdir(user_site) and not in_repo(user_site):
        if real(user_site) not in [real(p) for p in kept]:
            kept.append(user_site)
    libp = real(lib)
    sys.path = [lib] + [p for p in kept if real(p) != libp]

    import schema_check
    loaded = real(getattr(schema_check, "__file__", "") or "")
    if loaded != real(dest):
        fail("validator loaded from %s" % (loaded or "nowhere"))
    rc = schema_check.main_staged()
except Refuse as e:
    print("check-staged-config: refusing commit; %s" % e, file=sys.stderr)
    sys.exit(1)
except SystemExit as e:
    print("check-staged-config: refusing commit; validator SystemExit(%r) is not a pass" % (e.code,), file=sys.stderr)
    sys.exit(1)
sys.exit(rc if isinstance(rc, int) else 1)
PY
rc=$?
set -e

printf 'check-staged-config: pass\n' > "$lib/expected-pass"
if [ "$rc" -eq 0 ] && cmp -s "$outf" "$lib/expected-pass"; then
  exit 0
fi
cat "$errf" >&2
if ! grep -q "check-staged-config: refusing commit" "$errf"; then
  echo "check-staged-config: refusing commit; checker did not report an explicit pass (exit $rc)" >&2
fi
exit 1
