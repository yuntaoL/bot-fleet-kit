#!/usr/bin/env python3
"""Schema checks shared by validate.sh and the pre-commit staged-config check.

validate.sh calls check_file() on working-tree files and passes schemas it loaded
from the working tree. That gate is unchanged.

`schema_check.py` staged (via check-staged-config.sh) validates index blobs only.
The instance and the schemas are the same snapshot: the index. `git cat-file` of
the staged blob, never the working tree. An unchanged schema's index blob is HEAD,
so a commit that does not stage the schema is checked against the committed schema.
A commit that stages a schema and an instance together is checked against that
staged schema. An unstaged edit, a skip-worktree or assume-unchanged edit, or a
schema restored in the worktree after a refused check cannot loosen the rules.

A staged config path, and every schema blob, must be mode 100644 or 100755.
Symlinks (120000), gitlinks (160000), type changes, and any other mode fail closed.
Deletions have no blob and are not checked.

check-staged-config.sh runs this module under `python3 -I` from an explicit copy of
the index blob. This file must be tracked and clean: a regular index blob whose
worktree bytes match that blob (a skip-worktree or unstaged copy does not run).
When the file is unchanged, that blob is HEAD. jsonschema is the installed package;
a worktree or untracked module must not be the validator that runs.

SystemExit from the validator, including SystemExit(0), is not a pass. Success is
only main_staged() returning 0 after writing the pass line.
"""
import json, os, re, subprocess, sys

sys.dont_write_bytecode = True

STAGED_SCHEMAS = (
    (re.compile(r"^bots/[^/]+/routines/[^/]+\.json$"), "routine"),
    (re.compile(r"^bots/[^/]+/bot\.json$"), "bot"),
    (re.compile(r"^local/fleet\.json$"), "fleet"),
)
SCHEMA_NAMES = ["fleet", "profile", "state", "routine", "owners", "bot"]
REGULAR_MODES = ("100644", "100755")
PASS_LINE = "check-staged-config: pass"


def root():
    return subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()

def _git(args):
    env = os.environ.copy()
    env["GIT_LITERAL_PATHSPECS"] = "1"
    return subprocess.check_output(args, env=env)

def index_entry(path):
    """(mode, sha) for one stage-0 index blob, or None. skip-worktree does not change this."""
    out = _git(["git", "ls-files", "--stage", "-z", "--", path])
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

def cat_blob(sha):
    return subprocess.check_output(["git", "cat-file", "blob", sha])

def iter_staged():
    """Staged diff entries as (path, new_mode, status). Includes type changes (T).
    Renames and copies yield the destination path. Does not use --diff-filter, so
    ACMR cannot hide a symlink or gitlink.
    """
    out = subprocess.check_output(["git", "diff", "--cached", "-z", "--raw"])
    parts = [p for p in out.split(b"\0") if p]
    i = 0
    while i < len(parts):
        rec = parts[i]
        i += 1
        if not rec.startswith(b":"):
            raise RuntimeError("unreadable staged diff")
        fields = rec[1:].decode("utf-8", "surrogateescape").split(" ")
        if len(fields) < 5 or i > len(parts):
            raise RuntimeError("unreadable staged diff")
        _oldmode, newmode, _oldsha, _newsha, status = fields[:5]
        if i >= len(parts):
            raise RuntimeError("staged diff truncated")
        path = parts[i].decode("utf-8", "surrogateescape")
        i += 1
        if status[:1] in ("R", "C"):
            if i >= len(parts):
                raise RuntimeError("staged diff truncated")
            path = parts[i].decode("utf-8", "surrogateescape")
            i += 1
        yield path, newmode, status

def load_schemas(root_dir):
    """Working-tree schemas for check_file / validate.sh. Not used for the staged gate."""
    try:
        import jsonschema
    except ImportError:
        sys.exit("check-staged-config: pip install jsonschema")
    out = {}
    for n in SCHEMA_NAMES:
        with open(os.path.join(root_dir, "fleet/schema", "%s.schema.json" % n)) as f:
            out[n] = json.load(f)
    return jsonschema, out

def import_trusted_jsonschema():
    try:
        import jsonschema
    except ImportError:
        raise RuntimeError("pip install jsonschema")
    path = getattr(jsonschema, "__file__", None)
    if not path:
        raise RuntimeError("jsonschema has no __file__")
    rp = os.path.realpath(path)
    rootp = os.path.realpath(root())
    inside = rp == rootp or rp.startswith(rootp + os.sep)
    if inside:
        raise RuntimeError("jsonschema loaded from untrusted %s" % os.path.relpath(rp, rootp))
    return jsonschema

def load_index_schemas():
    """Schemas from the index, the same snapshot as the instance blobs."""
    mod = import_trusted_jsonschema()
    out = {}
    for n in SCHEMA_NAMES:
        path = "fleet/schema/%s.schema.json" % n
        ent = index_entry(path)
        if ent is None or ent[0] not in REGULAR_MODES:
            mode = ent[0] if ent else "missing"
            raise RuntimeError("%s index mode %s is not a regular file" % (path, mode))
        try:
            out[n] = json.loads(cat_blob(ent[1]).decode("utf-8"))
        except Exception as e:
            raise RuntimeError("%s: %s" % (path, e))
    return mod, out

def schema_name_for(path):
    path = path.replace("\\", "/").lstrip("./")
    for rx, name in STAGED_SCHEMAS:
        if rx.match(path):
            return name
    return None

def fail_line(path, exc):
    return "FAIL %s: %s" % (path, str(exc).splitlines()[0])

def apply_schema(jsonschema_mod, instance, schema):
    # SystemExit inherits from BaseException, not Exception. sys.exit(0) in a
    # validator must not become a successful return.
    try:
        jsonschema_mod.validate(instance, schema)
    except SystemExit as e:
        raise RuntimeError("validator SystemExit(%r) is not a pass" % (e.code,))

def check_file(path, schema_name, schemas=None, jsonschema_mod=None, root_dir=None):
    """Working-tree check. Same call validate.sh used to make inline."""
    if jsonschema_mod is None or schemas is None:
        jsonschema_mod, schemas = load_schemas(root_dir or root())
    try:
        apply_schema(jsonschema_mod, json.load(open(path)), schemas[schema_name])
    except Exception as e:
        return fail_line(path, e)
    return None

def mode_failure(path, mode):
    return ("FAIL %s: staged mode %s is not a regular file (100644 or 100755); "
            "symlink, gitlink, and other modes are refused" % (path, mode))

def check_staged_blob(path, schema_name, sha, schemas, jsonschema_mod):
    try:
        instance = json.loads(cat_blob(sha).decode("utf-8"))
    except Exception as e:
        return fail_line(path, e)
    try:
        apply_schema(jsonschema_mod, instance, schemas[schema_name])
    except Exception as e:
        return fail_line(path, e)
    return None

def check_staged():
    try:
        os.chdir(root())
        jsonschema_mod, schemas = load_index_schemas()
        entries = list(iter_staged())
    except Exception as e:
        print("check-staged-config: refusing commit; %s" % e, file=sys.stderr)
        return 1
    fails = []
    for path, diff_mode, status in entries:
        name = schema_name_for(path)
        if not name or status[:1] == "D":
            continue
        ent = index_entry(path)
        if ent is None:
            fails.append("FAIL %s: staged config is not a single regular index blob" % path)
            continue
        mode, sha = ent
        if mode not in REGULAR_MODES or diff_mode not in REGULAR_MODES or mode != diff_mode:
            fails.append(mode_failure(path, mode if mode not in REGULAR_MODES else diff_mode))
            continue
        msg = check_staged_blob(path, name, sha, schemas, jsonschema_mod)
        if msg:
            fails.append(msg)
    if fails:
        print("check-staged-config: refusing commit; staged configuration JSON failed schema check:", file=sys.stderr)
        for msg in fails:
            print(msg, file=sys.stderr)
        return 1
    return 0

def main_staged():
    """Return 0 only after a real pass. Writes PASS_LINE to stdout in that case only."""
    try:
        rc = check_staged()
    except SystemExit as e:
        print("check-staged-config: refusing commit; validator SystemExit(%r) is not a pass" % (e.code,), file=sys.stderr)
        return 1
    if rc != 0:
        return 1 if not isinstance(rc, int) else rc
    sys.stdout.write(PASS_LINE + "\n")
    sys.stdout.flush()
    return 0

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "staged":
        sys.exit(main_staged())
    elif cmd == "file" and len(sys.argv) == 4:
        msg = check_file(sys.argv[3], sys.argv[2])
        if msg:
            print(msg, file=sys.stderr)
            sys.exit(1)
    else:
        sys.exit("usage: schema_check.py staged | file <schema> <path>")
