#!/usr/bin/env bash
# Usage: fleet/scripts/check-actions.sh
# 0.11.0 action index and shared skills index. Read-only.
# No local/fleet.json (the template repo): print a skip line and exit 0.
# Non-retired bots in local/fleet.json:
#   (a) FAIL if bots/<slug>/kb/ACTIONS.md is missing and the bot folder exists.
#       A fleet.json row with no folder yet (active or pre-fleet) only warns, even when strict.
#   (e) FAIL if a row links to a path that does not exist (markdown links, reference-style
#       links, and backticked paths ending .md/.json/.sh/.py/.yml). Resolve relative to the
#       file's directory first, then bots/<slug>/ for a kb/ or skills/ path, then the
#       repo root, after %20 decoding. A realpath outside
#       the repo is dead. Ignore http(s), anchors, ~/absolute paths, env/secret names,
#       fenced code, and placeholders (<...> or kb/prefs/x.md). A symlinked ACTIONS.md or
#       SHARED-SKILLS.md is a FAIL and is not read. A bare skill name is not a dead link.
#   (b) WARN standing kb/me/prefs and kb/me/services files not referenced (or covered by that folder's INDEX.md)
#   (c) WARN the bot's own skills not named in ACTIONS.md
#   (d) WARN skills cited in rules.md, instructions.md, routine steps, or *.steps.md
#       that ACTIONS.md does not mention
#   stub WARN when ACTIONS.md says status: stub
# Shared index local/shared/SHARED-SKILLS.md:
#   (f) FAIL if it is missing; WARN if status: stub; dead links count as (e)
#   (g) WARN a fleet/skills or local/shared/skills skill (dir with SKILL.md) not listed.
#       If BOT_FLEET_SKILL_LIBRARY is a directory, also WARN each library skill that is
#       neither listed nor bot-private (a bots/<slug>/skills/<name>/ dir, or `(private)`
#       in exactly one bot's ACTIONS.md). Unset library: skipped.
#   (h) WARN a bot row whose Action cell is a shared skill name, or whose Action or
#       Hard rule cell repeats 40+ characters of a shared When-to-use cell.
#       Naming a shared skill in the Read-first cell is not a copy.
#   (i) WARN if ACTIONS.md has no markdown link to the shared index
# (a)(e)(f missing and dead links) fail immediately. (b)(c)(d)(g)(h)(i) and stubs warn.
# BOT_FLEET_STRICT_ACTIONS=1 turns those warnings into failures.
set -euo pipefail
if ! root="$(git rev-parse --show-toplevel)"; then
  echo "check-actions: not a git repo" >&2
  exit 1
fi
cd "$root"
python3 - <<'PY'
import glob, json, os, re, sys
from urllib.parse import unquote
strict = os.environ.get("BOT_FLEET_STRICT_ACTIONS") == "1"
library = os.environ.get("BOT_FLEET_SKILL_LIBRARY") or ""
F = "local/fleet.json"
counts = {k: 0 for k in "a e b c d f g h i stub type folder status".split()}
failed = False
FAIL_KINDS = {"a", "e", "f"}
# folder stays a warning under strict: a roster row with no directory yet is not a failure
WARN_KINDS = {"b", "c", "d", "g", "h", "i", "stub", "type", "status"}
ROOT = os.path.realpath(".")
def symlink_part(rel):
    acc = ""
    for part in rel.strip("/").split("/"):
        if not part:
            continue
        acc = part if not acc else acc + "/" + part
        if os.path.islink(acc):
            return acc
    return ""

def emit(kind, who, msg):
    global failed
    counts[kind] += 1
    bad = kind in FAIL_KINDS or (strict and kind in WARN_KINDS)
    if bad:
        failed = True
    print(f"{'FAIL' if bad else 'WARN'} {who}: {msg}")

def link_path(raw):
    raw = raw.strip()
    raw = re.sub(r'\s+["\'].*$', "", raw).strip()
    if raw.startswith("<") and raw.endswith(">"):
        raw = raw[1:-1].strip()
    return raw.split("#", 1)[0].split("?", 1)[0].strip()

def ignored(raw):
    path = link_path(raw)
    if not path:
        return True
    low = path.lower()
    if low.startswith(("http://", "https://", "mailto:")):
        return True
    if path.startswith("#") or raw.strip().startswith("#"):
        return True
    if path.startswith("~") or path.startswith("/"):
        return True
    if path.startswith("$") or "${" in path:
        return True
    if "/" not in path and re.fullmatch(r"[A-Z][A-Z0-9_]*(?:\.(?:md|json|sh|py|yml))?", path):
        return True
    return False

def strip_fences(text):
    return re.sub(r"(?s)```.*?```", "", text)

def placeholder(path):
    if "<" in path and ">" in path:
        return True
    return path.lstrip("./") in ("kb/prefs/x.md", "prefs/x.md")

def inside_repo(path):
    real = os.path.realpath(path)
    try:
        return os.path.commonpath([ROOT, real]) == ROOT
    except ValueError:
        return False

def targets(text):
    text = strip_fences(text)
    found = []
    defs = {}
    for m in re.finditer(r"(?m)^[ ]{0,3}\[([^\]]+)\]:[ \t]*(\S+)", text):
        defs[m.group(1).strip().lower()] = m.group(2).strip()
        found.append(m.group(2).strip())
    for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
        found.append(m.group(1).strip())
    for m in re.finditer(r"\[([^\]]+)\]\[([^\]]*)\]", text):
        key = (m.group(2) or m.group(1)).strip().lower()
        if key in defs:
            found.append(defs[key])
    for m in re.finditer(r"`([^`\n]+)`", text):
        inner = m.group(1).strip()
        path = unquote(link_path(inner))
        if re.search(r"\.(?:md|json|sh|py|yml)$", path) or ("<" in path and ">" in path):
            found.append(inner)
    return found

def candidate_state(abs_path):
    """ok if the path exists inside the repo, missing if it does not, dead if it escapes."""
    if not inside_repo(abs_path):
        return "dead"
    if os.path.lexists(abs_path):
        return "ok"
    return "missing"

def link_state(raw, base, bot_root=None):
    """skip, ok, or dead.

    Order: the file's directory, then bots/<slug>/ for a kb/ or skills/ path, then the repo root.
    A candidate whose real path leaves the repo is dead and is not replaced by a later hit.
    """
    path = unquote(link_path(raw))
    if not path or ignored(raw) or placeholder(path):
        return "skip"
    rel = path[2:] if path.startswith("./") else path
    bases = [base if os.path.isabs(base) else os.path.join(ROOT, base)]
    if bot_root and (rel.startswith("kb/") or rel.startswith("skills/")):
        bases.append(bot_root if os.path.isabs(bot_root) else os.path.join(ROOT, bot_root))
    bases.append(ROOT)
    for b in bases:
        state = candidate_state(os.path.normpath(os.path.join(b, rel)))
        if state == "dead":
            return "dead"
        if state == "ok":
            return "ok"
    return "dead"

def dead_links(text, base, who, bot_root=None):
    seen = []
    for raw in targets(text):
        path = unquote(link_path(raw))
        if path in seen:
            continue
        state = link_state(raw, base, bot_root)
        if state == "skip":
            continue
        seen.append(path)
        if state == "dead":
            emit("e", who, f"dead link `{path}`")

def fm_map(path):
    try:
        text = open(path, errors="ignore").read(8000)
    except Exception:
        return {}
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end < 0:
        return {}
    out = {}
    for m in re.finditer(r"(?m)^([A-Za-z0-9_-]+):\s*(.*?)\s*$", text[3:end]):
        out[m.group(1).lower()] = m.group(2).strip().strip("'\"")
    return out

def parse_tables(text):
    lines = text.splitlines()
    i, tables = 0, []
    while i < len(lines):
        if not lines[i].lstrip().startswith("|"):
            i += 1
            continue
        block = []
        while i < len(lines) and lines[i].lstrip().startswith("|"):
            block.append(lines[i])
            i += 1
        rows = []
        for ln in block:
            cells = [c.strip() for c in ln.strip().strip("|").split("|")]
            if cells and all(re.fullmatch(r":?-{1,}:?", c.replace(" ", "")) for c in cells):
                continue
            rows.append(cells)
        if len(rows) >= 2:
            tables.append((rows[0], rows[1:]))
    return tables

def col_index(header, needle):
    for i, h in enumerate(header):
        if needle in h.lower():
            return i
    return None

def norm_cell(s):
    return re.sub(r"\s+", " ", s.replace("`", "").strip().lower())

def norm_ws(s):
    s = s.lower()
    s = re.sub(r"[`*_#]", "", s)
    return re.sub(r"\s+", " ", s).strip()

def listed_names(text):
    names = set()
    for header, rows in parse_tables(text):
        sc = col_index(header, "skill")
        if sc is None:
            sc = 0
        for cells in rows:
            if sc < len(cells):
                n = norm_cell(cells[sc])
                if re.fullmatch(r"[a-z0-9][a-z0-9-]*", n):
                    names.add(n)
            for c in cells:
                for m in re.finditer(r"skills/([A-Za-z0-9_-]+)", c):
                    names.add(m.group(1).lower())
    return names

def shared_records(text):
    recs = []
    for header, rows in parse_tables(text):
        sc = col_index(header, "skill")
        wc = col_index(header, "when")
        if sc is None:
            sc = 0
        if wc is None:
            wc = 1 if len(header) > 1 else None
        for cells in rows:
            if sc >= len(cells):
                continue
            name = norm_cell(cells[sc])
            when = cells[wc] if wc is not None and wc < len(cells) else ""
            if re.fullmatch(r"[a-z0-9][a-z0-9-]*", name):
                recs.append((name, when))
    return recs

def action_rows(text):
    out = []
    for header, rows in parse_tables(text):
        ac = col_index(header, "action")
        rc = col_index(header, "read")
        hc = col_index(header, "hard")
        if ac is None:
            ac = 0
        for cells in rows:
            def get(i):
                return cells[i] if i is not None and i < len(cells) else ""
            out.append((get(ac), get(rc), get(hc)))
    return out

def tied_skill_names(text):
    """Skill names cited as skills, not label words and not a later unrelated backtick."""
    names = []
    for m in re.finditer(r"skills/([A-Za-z0-9_-]+)/SKILL\.md", text):
        names.append(m.group(1))
    for m in re.finditer(r"skills/([A-Za-z0-9_-]+)/", text):
        names.append(m.group(1))
    for line in text.splitlines():
        for m in re.finditer(r"\bskills?\b", line, flags=re.I):
            rest = line[m.end():]
            pos = 0
            first = True
            while True:
                if first:
                    m2 = re.match(r"\s*`([A-Za-z0-9][A-Za-z0-9_-]*)`", rest[pos:])
                else:
                    m2 = re.match(r"\s*(?:,|\band\b|\bor\b)\s*`([A-Za-z0-9][A-Za-z0-9_-]*)`", rest[pos:], re.I)
                if not m2:
                    break
                names.append(m2.group(1))
                pos += m2.end()
                first = False
    return names

def skill_mentioned(name, text, slug):
    if any(n.lower() == name.lower() for n in tied_skill_names(text)):
        return True
    for p in (
        f"bots/{slug}/skills/{name}/SKILL.md",
        f"bots/{slug}/skills/{name}/",
        f"skills/{name}/SKILL.md",
        f"fleet/skills/{name}/SKILL.md",
        f"local/shared/skills/{name}/SKILL.md",
        f"fleet/skills/{name}/",
        f"local/shared/skills/{name}/",
    ):
        if p in text:
            return True
    return False

def mentioned_rel(rel, text, slug):
    rel = rel.replace(os.sep, "/")
    for c in (rel, "kb/" + rel, f"bots/{slug}/kb/" + rel):
        if re.search(r"(?<![A-Za-z0-9_./-])" + re.escape(c) + r"(?![A-Za-z0-9_-])", text):
            return True
    return False

def iter_md(root):
    """Markdown under root. os.walk does not follow a symlinked directory."""
    if not os.path.isdir(root) or os.path.islink(root):
        return
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        dirnames[:] = [d for d in dirnames if not os.path.islink(os.path.join(dirpath, d))]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if name.endswith(".md") and not os.path.islink(path):
                yield path

def is_pref_service(path, kb):
    # Standing prefs and services only. Mission-scoped kb/<mission>/prefs is not checked.
    if os.path.basename(path) == "INDEX.md":
        return False
    rel = os.path.relpath(path, kb).replace(os.sep, "/")
    return rel.startswith("me/prefs/") or rel.startswith("me/services/")

def cited_names(text):
    return tied_skill_names(text)

def load_steps(path):
    try:
        data = json.load(open(path))
    except Exception:
        return ""
    steps = data.get("steps")
    if isinstance(steps, str):
        return steps
    if isinstance(steps, list):
        return "\n".join(str(x) for x in steps)
    return ""

def skill_dirs(root):
    if not os.path.isdir(root):
        return []
    out = []
    for name in sorted(os.listdir(root)):
        d = os.path.join(root, name)
        if os.path.isdir(d) and os.path.isfile(os.path.join(d, "SKILL.md")):
            out.append((name, os.path.join(d, "SKILL.md")))
    return out

def bot_private(name):
    if glob.glob(f"bots/*/skills/{name}"):
        return True
    hits = []
    for p in sorted(glob.glob("bots/*/kb/ACTIONS.md")):
        try:
            lines = open(p, errors="ignore").read().splitlines()
        except Exception:
            continue
        for line in lines:
            if "(private)" in line and re.search(r"(?<![A-Za-z0-9_-])" + re.escape(name) + r"(?![A-Za-z0-9_-])", line, re.I):
                hits.append(p)
                break
    return len(hits) == 1

def copies(slug, text, recs):
    names = {n for n, _ in recs}
    for action, read, hard in action_rows(text):
        an = norm_cell(action)
        if an in names:
            emit("h", slug, f"ACTIONS.md row copies shared skill {an}")
        blob = norm_ws(action) + "\n" + norm_ws(hard)
        for n, when in recs:
            w = norm_ws(when)
            if len(w) < 40:
                continue
            if any(w[i:i + 40] in blob for i in range(0, len(w) - 39)):
                emit("h", slug, f"ACTIONS.md row repeats shared when-to-use text for {n}")
                break

if not os.path.exists(F):
    print("check-actions: skipped (no local/fleet.json)")
    sys.exit(0)
try:
    bots = json.load(open(F)).get("bots", [])
except Exception as exc:
    print(f"FAIL fleet: cannot read {F} ({exc})")
    sys.exit(1)

shared_path = "local/shared/SHARED-SKILLS.md"
shared_text, recs, listed = "", [], set()
shared_link = symlink_part(shared_path)
if shared_link:
    emit("e", "fleet", f"{shared_link} is a symlink")
elif not os.path.isfile(shared_path):
    emit("f", "fleet", f"missing {shared_path}")
else:
    shared_text = open(shared_path, errors="ignore").read()
    shared_fm = fm_map(shared_path)
    if not shared_fm.get("status", "").strip():
        emit("status", "fleet", "SHARED-SKILLS.md front matter has no status")
    elif shared_fm.get("status", "").lower() == "stub":
        emit("stub", "fleet", "stub index, not seeded yet")
    dead_links(shared_text, os.path.dirname(shared_path), "fleet")
    recs = shared_records(shared_text)
    listed = listed_names(shared_text)
    for root, label in (("fleet/skills", "fleet/skills"), ("local/shared/skills", "local/shared/skills")):
        for name, _skill in skill_dirs(root):
            if name.lower() not in listed:
                emit("g", "fleet", f"unindexed shared skill {name} ({label}/{name})")
    if library and os.path.isdir(library):
        for name, skill_md in skill_dirs(library):
            fm_name = fm_map(skill_md).get("name", "").strip()
            cands = []
            if fm_name:
                cands.append(fm_name.lower())
            cands.append(name.lower())
            if any(c in listed for c in cands):
                continue
            if any(bot_private(c) for c in cands):
                continue
            shown = fm_name or name
            emit("g", "fleet", f"unindexed library skill {shown}")

for b in bots:
    if b.get("role") == "retired" or b.get("status") == "retired":
        continue
    slug = b.get("slug") or ""
    if not slug:
        continue
    botdir = f"bots/{slug}"
    if not os.path.isdir(botdir) or os.path.islink(botdir):
        emit("folder", slug, f"no {botdir} yet (action index waits until the folder exists)")
        continue
    actions = f"{botdir}/kb/ACTIONS.md"
    link = symlink_part(actions)
    if link:
        emit("e", slug, f"{link} is a symlink")
        continue
    if not os.path.isfile(actions):
        emit("a", slug, f"missing {actions}")
        continue
    text = open(actions, errors="ignore").read()
    got = fm_map(actions).get("type", "")
    if got != "actions-index":
        emit("type", slug, f"ACTIONS.md type is '{got or 'missing'}', expected actions-index")
    dead_links(text, os.path.dirname(actions), slug, bot_root=botdir)
    kb = f"bots/{slug}/kb"
    for f in sorted(iter_md(kb)):
        if not is_pref_service(f, kb):
            continue
        rel = os.path.relpath(f, kb).replace(os.sep, "/")
        if mentioned_rel(rel, text, slug):
            continue
        folder = os.path.dirname(rel)
        index_rel = f"{folder}/INDEX.md" if folder else "INDEX.md"
        if mentioned_rel(index_rel, text, slug):
            continue
        emit("b", slug, f"unindexed pref {rel}")
    for skill in sorted(glob.glob(f"bots/{slug}/skills/*/SKILL.md")):
        name = os.path.basename(os.path.dirname(skill))
        if not skill_mentioned(name, text, slug):
            emit("c", slug, f"unindexed skill {name}")
    sources = []
    for p in (f"bots/{slug}/rules.md", f"bots/{slug}/instructions.md"):
        if os.path.isfile(p):
            sources.append(p)
    sources += sorted(glob.glob(f"bots/{slug}/routines/*.json"))
    sources += sorted(glob.glob(f"bots/{slug}/routines/*.steps.md"))
    seen = set()
    for p in sources:
        body = load_steps(p) if p.endswith(".json") else open(p, errors="ignore").read()
        for name in cited_names(body):
            key = (name, p)
            if key in seen:
                continue
            seen.add(key)
            if skill_mentioned(name, text, slug):
                continue
            emit("d", slug, f"skill `{name}` cited in {p} is not in ACTIONS.md")
    action_status = fm_map(actions).get("status", "")
    if not action_status.strip():
        emit("status", slug, "ACTIONS.md front matter has no status")
    elif action_status.lower() == "stub":
        emit("stub", slug, "stub index, not seeded yet")
    if recs:
        copies(slug, text, recs)
    if not re.search(r"\[[^\]]*\]\([^)]*SHARED-SKILLS\.md[^)]*\)", text):
        emit("i", slug, "ACTIONS.md does not link to local/shared/SHARED-SKILLS.md")

if all(v == 0 for v in counts.values()):
    print("check-actions: OK")
else:
    print("check-actions: " + " ".join(f"{k}={counts[k]}" for k in "a e b c d f g h i stub type folder status".split()))
sys.exit(1 if failed else 0)
PY
