#!/usr/bin/env bash
# Usage: fleet/scripts/check-actions.sh
# 0.11.0 action index and shared skills index. Read-only.
# No local/fleet.json (the template repo): print a skip line and exit 0.
# Non-retired bots in local/fleet.json:
#   (a) FAIL if bots/<slug>/kb/ACTIONS.md is missing
#   (e) FAIL if a row links to a path that does not exist (markdown links, and
#       backticked paths ending .md/.json/.sh/.py/.yml). Relative to the file's
#       directory first, then the repo root. Ignore http(s), anchors, ~/absolute
#       paths, and env/secret names. A bare skill name is not a dead link.
#   (b) WARN kb prefs/services not referenced (or covered by that folder's INDEX.md)
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
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 - <<'PY'
import glob, json, os, re, sys
strict = os.environ.get("BOT_FLEET_STRICT_ACTIONS") == "1"
library = os.environ.get("BOT_FLEET_SKILL_LIBRARY") or ""
F = "local/fleet.json"
counts = {k: 0 for k in "a e b c d f g h i stub".split()}
failed = False
FAIL_KINDS = {"a", "e", "f"}
WARN_KINDS = {"b", "c", "d", "g", "h", "i", "stub"}
PREF_TYPES = {"pref", "prefs", "preference", "service", "services"}

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

def targets(text):
    found = []
    for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
        found.append(m.group(1).strip())
    for m in re.finditer(r"`([^`\n]+)`", text):
        inner = m.group(1).strip()
        if re.search(r"\.(?:md|json|sh|py|yml)$", link_path(inner)):
            found.append(inner)
    return found

def path_exists(raw, base):
    path = link_path(raw)
    if os.path.exists(os.path.normpath(os.path.join(base, path))):
        return True
    if os.path.exists(os.path.normpath(path)):
        return True
    return False

def dead_links(text, base, who):
    seen = []
    for raw in targets(text):
        if ignored(raw):
            continue
        path = link_path(raw)
        if path in seen:
            continue
        if not path_exists(raw, base):
            seen.append(path)
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

def skill_mentioned(name, text, slug):
    if re.search(r"(?<![A-Za-z0-9_-])" + re.escape(name) + r"(?![A-Za-z0-9_-])", text):
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

def is_pref_service(path, kb):
    if os.path.basename(path) == "INDEX.md":
        return False
    rel = os.path.relpath(path, kb).replace(os.sep, "/")
    parts = rel.split("/")
    if "prefs" in parts[:-1] or "services" in parts[:-1]:
        return True
    return fm_map(path).get("type", "").lower() in PREF_TYPES

def cited_names(text):
    names = []
    for m in re.finditer(r"skills/([A-Za-z0-9_-]+)/SKILL\.md", text):
        names.append(m.group(1))
    for line in text.splitlines():
        for m in re.finditer(r"\bskills?\b", line, flags=re.I):
            rest = line[m.end():]
            names.extend(re.findall(r"`([A-Za-z0-9][A-Za-z0-9_-]*)`", rest))
    return names

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
if not os.path.isfile(shared_path):
    emit("f", "fleet", f"missing {shared_path}")
else:
    shared_text = open(shared_path, errors="ignore").read()
    if fm_map(shared_path).get("status", "").lower() == "stub":
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
    actions = f"bots/{slug}/kb/ACTIONS.md"
    if not os.path.isfile(actions):
        emit("a", slug, f"missing {actions}")
        continue
    text = open(actions, errors="ignore").read()
    dead_links(text, os.path.dirname(actions), slug)
    kb = f"bots/{slug}/kb"
    for f in sorted(glob.glob(f"{kb}/**/*.md", recursive=True)):
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
    if fm_map(actions).get("status", "").lower() == "stub":
        emit("stub", slug, "stub index, not seeded yet")
    if recs:
        copies(slug, text, recs)
    if not re.search(r"\[[^\]]*\]\([^)]*SHARED-SKILLS\.md[^)]*\)", text):
        emit("i", slug, "ACTIONS.md does not link to local/shared/SHARED-SKILLS.md")

if all(v == 0 for v in counts.values()):
    print("check-actions: OK")
else:
    print("check-actions: " + " ".join(f"{k}={counts[k]}" for k in "a e b c d f g h i stub".split()))
sys.exit(1 if failed else 0)
PY
