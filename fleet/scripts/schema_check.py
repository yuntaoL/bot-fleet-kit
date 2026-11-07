#!/usr/bin/env python3
"""Schema checks shared by validate.sh and the pre-commit staged-config check.

validate.sh calls check_file() on working-tree files. `schema_check.py staged`
(check-staged-config.sh) validates index blobs only (`git show :path`) for:

  bots/<slug>/routines/<name>.json  -> fleet/schema/routine.schema.json
  bots/<slug>/bot.json              -> fleet/schema/bot.schema.json
  local/fleet.json                  -> fleet/schema/fleet.schema.json

Both paths call jsonschema.validate. The schema files are the rules.
"""
import json, os, re, subprocess, sys

STAGED_SCHEMAS = (
    (re.compile(r"^bots/[^/]+/routines/[^/]+\.json$"), "routine"),
    (re.compile(r"^bots/[^/]+/bot\.json$"), "bot"),
    (re.compile(r"^local/fleet\.json$"), "fleet"),
)
SCHEMA_NAMES = ["fleet", "profile", "state", "routine", "owners", "bot"]

def root():
    return subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()

def load_schemas(root_dir):
    try:
        import jsonschema
    except ImportError:
        sys.exit("check-staged-config: pip install jsonschema")
    out = {}
    for n in SCHEMA_NAMES:
        with open(os.path.join(root_dir, "fleet/schema", "%s.schema.json" % n)) as f:
            out[n] = json.load(f)
    return jsonschema, out

def schema_name_for(path):
    path = path.replace("\\", "/").lstrip("./")
    for rx, name in STAGED_SCHEMAS:
        if rx.match(path):
            return name
    return None

def fail_line(path, exc):
    return "FAIL %s: %s" % (path, str(exc).splitlines()[0])

def apply_schema(jsonschema_mod, instance, schema):
    jsonschema_mod.validate(instance, schema)

def check_file(path, schema_name, schemas=None, jsonschema_mod=None, root_dir=None):
    """Working-tree check. Same call validate.sh used to make inline."""
    if jsonschema_mod is None or schemas is None:
        jsonschema_mod, schemas = load_schemas(root_dir or root())
    try:
        apply_schema(jsonschema_mod, json.load(open(path)), schemas[schema_name])
    except Exception as e:
        return fail_line(path, e)
    return None

def staged_paths():
    # Added, copied, modified, renamed. Deletions have no blob to check.
    out = subprocess.check_output(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"])
    return [p.decode("utf-8", "surrogateescape") for p in out.split(b"\0") if p]

def check_staged_blob(path, schema_name, schemas, jsonschema_mod):
    try:
        blob = subprocess.check_output(["git", "show", ":%s" % path])
    except subprocess.CalledProcessError as e:
        return fail_line(path, e)
    try:
        apply_schema(jsonschema_mod, json.loads(blob.decode("utf-8")), schemas[schema_name])
    except Exception as e:
        return fail_line(path, e)
    return None

def check_staged():
    r = root()
    os.chdir(r)
    jsonschema_mod, schemas = load_schemas(r)
    fails = []
    for path in staged_paths():
        name = schema_name_for(path)
        if not name:
            continue
        msg = check_staged_blob(path, name, schemas, jsonschema_mod)
        if msg:
            fails.append(msg)
    if fails:
        print("check-staged-config: refusing commit; staged configuration JSON failed schema check:", file=sys.stderr)
        for msg in fails:
            print(msg, file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "staged":
        sys.exit(check_staged())
    elif cmd == "file" and len(sys.argv) == 4:
        msg = check_file(sys.argv[3], sys.argv[2])
        if msg:
            print(msg, file=sys.stderr)
            sys.exit(1)
    else:
        sys.exit("usage: schema_check.py staged | file <schema> <path>")
