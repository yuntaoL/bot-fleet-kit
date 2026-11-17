#!/usr/bin/env python3
"""Compile per-bot prompts (0.12.0). Stdlib only. No network.

The rebuild hash covers the prompt digests, the embedded action and skill lines,
the bot's role and capabilities, and the thin-prompt text. It does not cover
docs, scripts, journals, state, holds, approvals, or built_at. A rebuild with
the same hash writes the same bytes, including the manifest's built_at.

Stale means the built snapshot differs from the deployed snapshot, or the
files that feed the hash differ from the built snapshot. Drift means a live
profile description (read-only) differs from the deployed prompt. This script
never writes a profile.

Usage:
  prompt_build.py [slug...]
  prompt_build.py --check [--json] [slug...]
  prompt_build.py --changelog
  prompt_build.py --mark-deployed <slug>
  prompt_build.py --check-versions
"""
import copy, datetime, glob, hashlib, json, os, re, subprocess, sys, tempfile

HEADER = (
    "<!-- Compiled by fleet/scripts/build-prompt.sh. Do not hand-edit. "
    "If an embedded row disagrees with the file in git, the file wins. -->\n"
)
FOOTER_BODY = (
    "Holds, approvals, journals and state stay in their files. "
    "This prompt does not copy them.\n"
)
# The pre-action routine is the Prompt digest of fleet/rules/startup.md.
# These phrases are the fixed routine; a digest that drops one is refused.
ROUTINE_ANCHORS = (
    "one-word reply",
    "carrying out something you proposed earlier",
    "right after a summary",
    "kb/INDEX.md",
    "today's journal",
    "Look up the action in the embedded index and in Shared skills.",
    "An owner row beats a generic platform skill or a connector default.",
    "4. If no row exists, act thoughtfully: do the reversible part, and before anything irreversible (send, buy, book, post, delete) stop and ask the owner; when the same ask repeats, add a row to your ACTIONS.md.",
    "the file wins",
    "build-prompt.sh --check <slug>",
)
ROLES = ("manager", "builder", "worker", "retired", "all")
SLUG_RX = re.compile(r"^[a-z0-9-]+$")
REASON_ORDER = (
    "missing-bot-dir",
    "missing-bot-json",
    "missing-actions",
    "missing-shared-skills",
    "duplicate-id",
    "symlink",
    "bad-source",
    "over-cap",
    "not-built",
    "prompt-file-mismatch",
    "inputs-changed",
    "not-deployed",
    "built-differs-from-deployed",
)
PROFILES_DEFAULT = "/home/box/agent-data/agents"
CAP_DEFAULT = 8000


def git_out(*args):
    r = subprocess.run(["git", *args], capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "replace").strip()


def chdir_root():
    root = git_out("rev-parse", "--show-toplevel")
    if not root:
        sys.exit("build-prompt: not a git repo")
    os.chdir(root)
    return root


def sha256_bytes(data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    return hashlib.sha256(data).hexdigest()


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def norm_newlines(s):
    return s.replace("\r\n", "\n").replace("\r", "\n")


def pad_strip(cell):
    """Drop one leading and one trailing ASCII pad space. Further spaces, and NBSP, stay."""
    if cell.startswith(" "):
        cell = cell[1:]
    if cell.endswith(" "):
        cell = cell[:-1]
    return cell


def split_cells(line, origin=None, row=None):
    """Split one markdown table row. Escaped \\| and pipes inside backticks stay in the cell.

    A row that ends in \\| has no closing pipe. That is a build failure, not a cell that ends in \\.
    origin and row name the file and the line when the row is indented or has trailing space.
    """
    def fail(msg):
        where = ""
        if origin:
            where = "%s" % origin
            if row is not None:
                where += ":%s" % row
            where += ": "
        raise ValueError(where + msg)

    s = line.strip("\n")
    if s != s.lstrip(" \t") and s.lstrip(" \t").startswith("|"):
        fail("table row is indented; move it to the start of the line: %s" % s.strip())
    if s != s.rstrip(" \t") and s.rstrip(" \t").endswith("|"):
        fail("table row has whitespace after the last pipe: %s" % s.strip())
    if s.startswith("|"):
        s = s[1:]
    if not s.endswith("|"):
        fail("table row has no closing pipe: %s" % line.strip())
    slashes = 0
    i = len(s) - 2
    while i >= 0 and s[i] == "\\":
        slashes += 1
        i -= 1
    if slashes % 2 == 1:
        raise ValueError("table row has no closing pipe: %s" % line.strip())
    s = s[:-1]
    cells, buf, code = [], [], False
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "`":
            code = not code
            buf.append(ch)
            i += 1
            continue
        if not code and ch == "\\" and i + 1 < len(s) and s[i + 1] == "|":
            buf.append("\\|")
            i += 2
            continue
        if not code and ch == "|":
            cells.append(pad_strip("".join(buf)))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    cells.append(pad_strip("".join(buf)))
    return cells


def is_separator(cells):
    return bool(cells) and all(re.fullmatch(r":?-{1,}:?", c.replace(" ", "")) for c in cells)


def norm_block(s):
    lines = [ln.rstrip() for ln in norm_newlines(s).split("\n")]
    while lines and lines[0] == "":
        lines.pop(0)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def parse_list(raw):
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        raw = raw[1:-1]
    out = []
    for part in raw.split(","):
        part = part.strip().strip("'\"").strip()
        if part:
            out.append(part)
    return out


def parse_front_matter(text):
    text = norm_newlines(text)
    if not text.startswith("---\n"):
        return None, text, False
    end = text.find("\n---\n", 4)
    if end < 0:
        return None, text, True
    raw, body = text[4:end], text[end + 5 :]
    data = {"applies_to": {"roles": [], "capabilities": []}, "has_front_matter": True}
    section = None
    for line in raw.split("\n"):
        if not line.strip():
            continue
        if line.startswith((" ", "\t")) and section == "applies_to":
            key, _, val = line.strip().partition(":")
            key = key.strip()
            if key in ("roles", "capabilities"):
                data["applies_to"][key] = parse_list(val)
            continue
        key, _, val = line.partition(":")
        key, val = key.strip(), val.strip()
        section = "applies_to" if key == "applies_to" and val == "" else None
        if key == "id":
            data["id"] = val
        elif key == "prompt_version" and val:
            data["prompt_version_raw"] = val
        elif key == "prompt_why" and val:
            data["prompt_why"] = val.strip().strip("'\"")
    return data, body, True


def extract_digest(body):
    m = re.search(r"(?ms)^## Prompt digest[ \t]*\n(.*?)(?=^## |\Z)", norm_newlines(body))
    if not m:
        return None
    text = norm_block(m.group(1))
    return text or None


def applies_error(applies):
    roles = applies.get("roles") or []
    caps = applies.get("capabilities") or []
    if not roles:
        return "applies_to.roles is empty"
    bad = [r for r in roles if r not in ROLES]
    if bad:
        return "applies_to.roles has %s" % ", ".join(bad)
    badc = [c for c in caps if not SLUG_RX.fullmatch(c)]
    if badc:
        return "applies_to.capabilities has %s" % ", ".join(badc)
    return None


def parse_source(path, text, kind):
    """kind is kit or fleet. Fleet-local inputs record no prompt_version."""
    fm, body, saw = parse_front_matter(text)
    digest = extract_digest(body)
    base = {"path": path, "kind": kind, "has_front_matter": bool(saw and fm), "digest": digest}
    if not saw or fm is None:
        if kind == "kit":
            base["error"] = "missing front matter (id, prompt_version, applies_to)"
        elif digest:
            base["error"] = "Prompt digest without front matter id"
        else:
            base["warn"] = "no Prompt digest; it is not part of the compiled prompt"
        return base
    src = base
    src["id"] = fm.get("id", "")
    src["prompt_why"] = fm.get("prompt_why") or ""
    src["applies_to"] = {
        "roles": sorted(set(fm.get("applies_to", {}).get("roles") or [])),
        "capabilities": sorted(set(fm.get("applies_to", {}).get("capabilities") or [])),
    }
    raw_ver = fm.get("prompt_version_raw")
    if kind == "kit":
        if not SLUG_RX.fullmatch(src["id"]):
            src["error"] = "missing or invalid id"
        elif not raw_ver or not re.fullmatch(r"[0-9]+", raw_ver) or int(raw_ver) < 1:
            src["error"] = "prompt_version must be an integer >= 1"
        elif not digest:
            src["error"] = "missing Prompt digest"
        else:
            err = applies_error(src["applies_to"])
            src["error"] = err
            if not err:
                src["prompt_version"] = int(raw_ver)
    else:
        src["prompt_version"] = None
        if not SLUG_RX.fullmatch(src["id"]):
            src["error"] = "missing or invalid id"
        elif not digest:
            src["warn"] = "no Prompt digest; it is not part of the compiled prompt"
        else:
            err = applies_error(src["applies_to"])
            if err:
                src["error"] = err
            elif raw_ver:
                src["warn"] = "prompt_version is ignored; fleet-local inputs carry no kit version"
    if digest and not src.get("error"):
        src["digest_sha256"] = sha256_bytes(digest)
    else:
        src["digest_sha256"] = None
    return src


def kit_paths():
    return sorted(glob.glob("fleet/rules/*.md") + glob.glob("fleet/roles/*.md"))


def kit_paths_at(rev):
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", rev], capture_output=True, text=True)
    if r.returncode != 0:
        return []
    out = []
    for p in r.stdout.splitlines():
        if (p.startswith("fleet/rules/") or p.startswith("fleet/roles/")) and p.endswith(".md"):
            out.append(p)
    return out


def local_paths():
    return sorted(glob.glob("local/rules/*.md"))


def read_repo_text(path):
    if os.path.islink(path):
        raise ValueError("%s is a symlink" % path)
    root = os.path.realpath(".")
    real = os.path.realpath(path)
    if os.path.commonpath([root, real]) != root:
        raise ValueError("%s resolves outside the repo" % path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_sources():
    items, warns, errors = [], [], []
    for path in kit_paths():
        try:
            text = read_repo_text(path)
        except ValueError as e:
            errors.append(str(e))
            continue
        src = parse_source(path, text, "kit")
        if src.get("error"):
            errors.append("%s: %s" % (path, src["error"]))
        else:
            items.append(src)
    for path in local_paths():
        try:
            text = read_repo_text(path)
        except ValueError as e:
            errors.append(str(e))
            continue
        src = parse_source(path, text, "fleet")
        if src.get("error"):
            errors.append("%s: %s" % (path, src["error"]))
        elif src.get("digest") and src.get("id"):
            if src.get("warn"):
                warns.append("%s: %s" % (path, src["warn"]))
            items.append(src)
        else:
            warns.append("%s: %s" % (path, src.get("warn") or "no Prompt digest; it is not part of the compiled prompt"))
    ids = [s["id"] for s in items]
    dup = sorted({i for i in ids if ids.count(i) > 1})
    for i in dup:
        errors.append("duplicate prompt id %s" % i)
    return items, warns, errors


def role_match(applies, role, caps):
    roles = applies.get("roles") or []
    need = applies.get("capabilities") or []
    if not roles or ("all" not in roles and role not in roles):
        return False
    if not need:
        return True
    return any(c in caps for c in need)


def startup_source(items):
    for s in items:
        if s.get("id") == "startup" and s.get("digest"):
            return s
    return None


def routine_error(digest):
    if not digest:
        return "fleet/rules/startup.md has no Prompt digest"
    missing = [a for a in ROUTINE_ANCHORS if a not in digest]
    if missing:
        return "startup Prompt digest is missing the pre-action routine (%s)" % missing[0]
    return None


def parse_tables(text, origin):
    """Return [(header, data rows)]. Fail on a row whose cell count differs from its header."""
    lines = norm_newlines(text).split("\n")
    tables, i = [], 0
    while i < len(lines):
        if not lines[i].lstrip().startswith("|"):
            i += 1
            continue
        block = []
        while i < len(lines) and lines[i].lstrip().startswith("|"):
            block.append((i + 1, lines[i]))
            i += 1
        rows = []
        for lineno, ln in block:
            cells = split_cells(ln, origin, lineno)
            if is_separator(cells):
                continue
            rows.append(cells)
        if len(rows) < 2:
            continue
        header, data = rows[0], rows[1:]
        width = len(header)
        for cells in data:
            if len(cells) != width:
                raise ValueError("%s: row has %d cells, header has %d" % (origin, len(cells), width))
        tables.append((header, data))
    return tables


def col_index(header, needle):
    for i, h in enumerate(header):
        if needle in h.lower():
            return i
    return None


def col_exact(header, name):
    """Match a header cell exactly. 'skill' must not match a cell that only contains that word."""
    want = name.strip().lower()
    for i, h in enumerate(header):
        if h.strip().lower() == want:
            return i
    return None


def is_fill_in(cell):
    t = cell.strip(" ").lower()
    return t == "fill in" or t.startswith("fill in:")


def cell_at(cells, i):
    if i is None or i >= len(cells):
        return ""
    return cells[i]


def action_lines(text, source="bots/unknown/kb/ACTIONS.md"):
    """One line per consumed row. Read-first and hard rule are the cell text, not a shortened form."""
    lines, widths = [], []
    for header, rows in parse_tables(text, "ACTIONS.md"):
        ac, rc, hc = col_index(header, "action"), col_index(header, "read"), col_index(header, "hard")
        if ac is None:
            raise ValueError("ACTIONS.md: table %s is not consumed (no Action column)" % header)
        if hc is None:
            raise ValueError("ACTIONS.md: table %s has no hard-rule column" % header)
        for cells in rows:
            read, hard, name = cell_at(cells, rc), cell_at(cells, hc), cell_at(cells, ac)
            if is_fill_in(read) and is_fill_in(hard):
                continue
            if not name.strip(" "):
                continue
            read = rewrite_rel_links(read, source)
            hard = rewrite_rel_links(hard, source)
            line = "- %s | %s | %s" % (name, read, hard)
            lines.append(line)
            widths.append((name, len(line)))
    return lines, widths


SKILL_ID = re.compile(r"[a-z0-9][a-z0-9-]*")
# Characters that continue a token. '.' , ',' ';' ':' ')' ']' end one, so 'tide-table.' matches.
_TOKEN_CONT = r"A-Za-z0-9_/-"


def skill_rows(text):
    """Skill rows, plus owner-preference rows.

    The Skill column is an exact header, not a cell that merely contains the word.
    A preference row is kept as cells and filtered per bot later. A table that is
    neither is an error.
    """
    rows_out, prefs = [], []
    for header, rows in parse_tables(text, "SHARED-SKILLS.md"):
        sc = col_exact(header, "skill")
        ac = col_index(header, "action")
        lc = col_index(header, "location")
        pc = col_index(header, "applies")
        hc = col_index(header, "hard")
        rc = col_index(header, "read")
        if sc is not None:
            for cells in rows:
                raw = cell_at(cells, sc).strip()
                if not raw or is_fill_in(raw):
                    continue
                name = raw.strip("`").lower()
                if not SKILL_ID.fullmatch(name):
                    raise ValueError("SHARED-SKILLS.md: %r is not a skill id" % raw)
                applies = parse_applies(cell_at(cells, pc), "skill %s" % name)
                rows_out.append({
                    "name": name,
                    "actions": cell_at(cells, ac),
                    "location": cell_at(cells, lc),
                    "read": cell_at(cells, rc) if rc is not None else "",
                    "hard": cell_at(cells, hc) if hc is not None else None,
                    "applies": applies,
                })
            continue
        if ac is not None and (rc is not None or hc is not None or col_index(header, "override") is not None or col_index(header, "pointer") is not None):
            apc = col_exact(header, "applies to")
            for cells in rows:
                action = cell_at(cells, ac)
                applies = parse_applies(cell_at(cells, apc), "preference %r" % action) if apc is not None else []
                prefs.append({
                    "cells": cells,
                    "action": action,
                    "applies": applies,
                })
            continue
        raise ValueError("SHARED-SKILLS.md: table %s is not consumed" % header)
    return rows_out, prefs


def _token(text, token):
    """True when token is its own word or path. Trailing . , ; : ) ] does not hide it."""
    if not token:
        return False
    return re.search(
        r"(?<![%s])%s(?![%s])" % (_TOKEN_CONT, re.escape(token), _TOKEN_CONT),
        text,
    ) is not None


def skills_segment(text, name):
    """True when skills/<name> is a path segment, including skills/<name>/SKILL.md."""
    if not name:
        return False
    return re.search(
        r"(?<![A-Za-z0-9_-])skills/%s(?![A-Za-z0-9_-])" % re.escape(name),
        text,
    ) is not None


def location_candidates(location):
    """Each backticked span is its own candidate. A bare word such as library is not.

    A backticked path also tries the SKILL.md file under that directory.
    """
    loc = location or ""
    cands = []
    for raw in re.findall(r"`([^`]+)`", loc):
        c = raw.strip()
        if not c or c in cands:
            continue
        cands.append(c)
        if "/" in c and not c.rstrip("/").endswith("SKILL.md"):
            extra = c.rstrip("/") + "/SKILL.md"
            if extra not in cands:
                cands.append(extra)
    if not cands:
        bare = loc.strip()
        if "/" in bare:
            cands.append(bare)
            if not bare.rstrip("/").endswith("SKILL.md"):
                cands.append(bare.rstrip("/") + "/SKILL.md")
    return cands


def referenced(actions_text, name, location):
    """A reference is an exact skill name, skills/<name>, or an exact path.

    A location that is only a word, such as library, is not a path and does not match.
    """
    if name and (_token(actions_text, name) or skills_segment(actions_text, name)):
        return True
    for cand in location_candidates(location):
        if _token(actions_text, cand):
            return True
    return False


def relevant_skills(actions_text, rows, role):
    """A row is relevant when ACTIONS.md names it, or Applies to lists the bot's role or all.

    An empty Applies to cell is reference-only. A repeated skill name is kept and warned.
    """
    out, seen, warns = [], set(), []
    for row in rows:
        if row["name"] in seen:
            warns.append("duplicate skill row %s; both rows are kept" % row["name"])
        seen.add(row["name"])
        ref = referenced(actions_text, row["name"], row["location"])
        role_hit = bool(row["applies"]) and ("all" in row["applies"] or role in row["applies"])
        if ref or role_hit:
            out.append(row)
    return out, warns


def read_targets(cell):
    """Backticked spans and markdown link targets from a Read-first cell, in order."""
    out = []
    for raw in re.findall(r"`([^`]+)`", cell or "") + re.findall(r"\[[^\]]*\]\(([^)]+)\)", cell or ""):
        t = raw.strip()
        if t and t not in out:
            out.append(t)
    return out


def parse_applies(cell, what):
    """Comma-separated Applies to. A blank slot such as 'worker,' or ',' fails and names the row."""
    raw = (cell or "").strip()
    if not raw:
        return []
    out = []
    for part in raw.split(","):
        piece = part.strip().strip("`").strip()
        if not piece:
            raise ValueError(
                "SHARED-SKILLS.md: Applies to in %s has a blank slot (%r); name a role, a slug, or all"
                % (what, raw)
            )
        out.append(piece.lower())
    return out


_SCHEME = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
_BOT_KB = re.compile(r"^bots/([^/]+)/")


def _leave_unchanged(raw):
    """Tokens that are never paths: anchors, URLs, home paths, placeholders, prose."""
    if not raw or raw.startswith("#"):
        return True
    if raw.startswith("~"):
        return True
    if "<" in raw and ">" in raw:
        return True
    if any(ch.isspace() for ch in raw):
        return True
    if _SCHEME.match(raw):
        return True
    return False


def _tracked(path):
    """True when path is a git-index file, or a directory prefix of one."""
    path = path.replace("\\", "/").rstrip("/")
    if not path or path.startswith(".."):
        return False
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if root.returncode != 0:
        return False
    listed = subprocess.run(
        ["git", "ls-files", "--", path], cwd=root.stdout.strip(), capture_output=True, text=True
    )
    if listed.returncode != 0:
        return False
    for line in listed.stdout.splitlines():
        if line == path or line.startswith(path + "/"):
            return True
    return False


def _kb_path(path, source):
    """There is no top-level kb/. ACTIONS means this bot's kb; a shared row must name the bot."""
    rest = path[3:] if path.startswith("kb/") else ""
    src = source.replace("\\", "/")
    bot = _BOT_KB.match(src)
    if bot and "/kb/" in src:
        slug = bot.group(1)
        rewritten = ("bots/%s/kb/%s" % (slug, rest)) if rest else ("bots/%s/kb" % slug)
        return rewritten
    raise ValueError(
        "kb/ path %r in %s needs an explicit bots/<slug>/kb/ path; there is no top-level kb/"
        % (path, source)
    )


def rewrite_rel_links(text, source="local/shared/SHARED-SKILLS.md"):
    """Rewrite a relative target to a repo-root path, from the source file's directory.

    `..` is always resolved, so a link that leaves the repo still fails the build.
    A bare name or a `./` target is rewritten only when the resolved path is a tracked
    file or a tracked directory prefix. Otherwise it is left unchanged, which keeps
    timezones, domains, version strings, and words like and/or. A trailing slash is
    kept. Scheme URLs, pure #anchors, `~` paths, `<...>` placeholders, and whitespace
    are never rewritten.
    """
    base = os.path.dirname(source) or "."

    def one(target):
        raw = target.strip()
        if _leave_unchanged(raw):
            return target
        path, frag = raw, ""
        if "#" in raw:
            path, frag = raw.split("#", 1)
            frag = "#" + frag
        if not path:
            return target
        trailing = path.endswith("/")
        body = path[:-1] if trailing else path
        if body == "kb" or body.startswith("kb/"):
            rewritten = _kb_path(body, source)
            if trailing:
                rewritten += "/"
            return rewritten + frag
        if body.startswith("/"):
            return target
        norm = os.path.normpath(os.path.join(base, body)).replace("\\", "/")
        if norm.startswith("../") or norm == ".." or os.path.isabs(norm):
            raise ValueError("link leaves the repo: %s (from %s)" % (target, source))
        if trailing:
            norm += "/"
        if ".." in body.split("/"):
            return norm + frag
        if _tracked(norm.rstrip("/")):
            return norm + frag
        return target

    def link_repl(m):
        return m.group(1) + "(" + one(m.group(2)) + ")"

    text = re.sub(r"(\[[^\]]*\])\(([^)]+)\)", link_repl, text)

    def tick_repl(m):
        return "`" + one(m.group(1)) + "`"

    text = re.sub(r"`([^`]+)`", tick_repl, text)
    src = source.replace("\\", "/")
    if not (_BOT_KB.match(src) and "/kb/" in src) and re.search(r"(?<![\w./-])kb/", text):
        raise ValueError(
            "kb/ path in %s needs an explicit bots/<slug>/kb/ path; there is no top-level kb/"
            % source
        )
    return text


def skill_lines(rows):
    lines = []
    for r in rows:
        actions = rewrite_rel_links(r["actions"])
        location = rewrite_rel_links(r["location"])
        read = rewrite_rel_links(r.get("read") or "")
        bits = [r["name"], actions, location]
        reads = read_targets(read)
        if reads:
            bits.append(" ".join(reads))
        if r.get("hard") is not None:
            bits.append(rewrite_rel_links(r["hard"]))
        lines.append("- " + " | ".join(bits))
    return lines


def phrase_key(text):
    """Whole phrase: case and edge punctuation and extra spaces fold. A hyphen stays in the token."""
    s = (text or "").strip().strip("`").lower()
    s = s.strip(" \t.,;:)]")
    return re.sub(r"\s+", " ", s)


def action_phrases(text):
    """Action-column cells. A preference matches one of these whole phrases, not a shorter word inside it."""
    try:
        tables = parse_tables(text, "ACTIONS.md")
    except ValueError:
        return []
    names = []
    for header, rows in tables:
        ac = col_index(header, "action")
        if ac is None:
            continue
        for cells in rows:
            names.append(cell_at(cells, ac))
    return names


def loose_match(text, phrase):
    """Whole-phrase match. 'mail' does not match 'mail trash'. 'e-mail' does not match 'mail'."""
    want = phrase_key(phrase)
    if not want:
        return False
    phrases = action_phrases(text)
    if not phrases:
        phrases = [text]
    return any(phrase_key(p) == want for p in phrases)


def known_slugs(fleet):
    out = []
    for bot in fleet.get("bots") or []:
        slug = bot.get("slug") if isinstance(bot, dict) else None
        if isinstance(slug, str) and slug:
            out.append(slug)
    return out


def check_applies(values, slugs, what):
    """Applies to is comma-separated: all, a known role, or a slug from fleet.json."""
    allowed = set(ROLES) | set(slugs)
    for raw in values:
        if raw in allowed:
            continue
        if any(ch.isspace() for ch in raw):
            raise ValueError(
                "SHARED-SKILLS.md: Applies to value %r in %s is not comma-separated; split each role or slug with a comma"
                % (raw, what)
            )
        raise ValueError(
            "SHARED-SKILLS.md: Applies to value %r in %s is not all, a known role, or a slug in fleet.json"
            % (raw, what)
        )


def relevant_prefs(prefs, actions_text, slug, role, skill_rows_picked):
    """An Applies to cell lists slugs, roles, or all. An empty cell is relevance-only.

    Relevance is the action, or a skill named in the row, matching this bot's ACTIONS
    or a skill row already chosen for this bot.
    """
    skill_blob = "\n".join(
        " ".join([r["name"], r.get("location") or "", r.get("read") or ""]) for r in skill_rows_picked
    )
    out = []
    for pref in prefs:
        applies = pref["applies"]
        if applies:
            if "all" in applies or role in applies or slug in applies:
                out.append(pref)
            continue
        action = (pref["action"] or "").strip().strip("`")
        if action and loose_match(actions_text, action):
            out.append(pref)
            continue
        blob = " | ".join(pref["cells"])
        names = [n.lower() for n in re.findall(r"`([A-Za-z0-9][A-Za-z0-9-]*)`", blob)]
        names += [n.lower() for n in re.findall(r"skills/([A-Za-z0-9][A-Za-z0-9-]*)", blob)]
        if any(
            loose_match(actions_text, n) or skills_segment(actions_text, n) or loose_match(skill_blob, n)
            for n in names
        ):
            out.append(pref)
    return out


def pref_line(pref):
    cells = [rewrite_rel_links(c) for c in pref["cells"]]
    return "- " + " | ".join(cells)


def render_thin(worktree):
    if not os.path.isfile("templates/THIN-PROMPT.tmpl") or os.path.islink("templates/THIN-PROMPT.tmpl"):
        raise ValueError("missing templates/THIN-PROMPT.tmpl")
    txt = read_repo_text("templates/THIN-PROMPT.tmpl")
    if "\n" in worktree or "{{" in worktree or "}}" in worktree:
        raise ValueError("worktree path is not a single plain path")
    txt = txt.replace("{{WORKTREE}}", worktree)
    left = sorted(set(re.findall(r"\{\{[^}]*\}\}", txt)))
    if left:
        raise ValueError("unfilled placeholders %s" % left)
    return txt.strip("\n") + "\n"


def assemble(thin, pre, gists, actions, skills):
    sections = []
    sections.append(("thin", HEADER + "\n" + thin.strip("\n") + "\n"))
    sections.append(("pre-action", "\n## Before you act\n\n" + pre.strip("\n") + "\n"))
    if gists:
        sections.append(("rule-gists-heading", "\n## Rule gists\n"))
        for gid, text in gists:
            sections.append(("gist:%s" % gid, "\n### %s\n\n%s\n" % (gid, text.strip("\n"))))
    body = ("\n".join(actions) + "\n") if actions else "(no rows)\n"
    sections.append(("action-index", "\n## Action index\n\n" + body))
    sbody = ("\n".join(skills) + "\n") if skills else "(none)\n"
    sections.append(("shared-skills", "\n## Shared skills\n\n" + sbody))
    sections.append(("footer", "\n## Left in git\n\n" + FOOTER_BODY))
    return "".join(text for _, text in sections), sections


def prompt_cap(fleet):
    env = os.environ.get("BOT_FLEET_PROMPT_MAX", "").strip()
    if env:
        if not re.fullmatch(r"[0-9]+", env) or int(env) < 1:
            sys.exit("build-prompt: BOT_FLEET_PROMPT_MAX must be a positive integer")
        return int(env)
    raw = fleet.get("prompt_max_chars")
    if raw is None:
        return CAP_DEFAULT
    if isinstance(raw, bool) or not isinstance(raw, int) or raw < 1:
        sys.exit("build-prompt: prompt_max_chars must be a positive integer")
    return raw


def file_sha(path):
    if not os.path.isfile(path) or os.path.islink(path):
        return None
    with open(path, "rb") as f:
        return sha256_bytes(f.read())


def input_record(src):
    return {
        "digest_sha256": src["digest_sha256"],
        "id": src["id"],
        "kind": src["kind"],
        "path": src["path"],
        "prompt_version": src.get("prompt_version"),
    }


def over_cap_report(slug, total, cap, sections, row_sizes=None):
    """Three parts: fixed (thin, routine, gists, footer), the action index, and skill plus preference rows.

    Cut the strictly largest part. A tie keeps the earlier of shared skills, then fixed cost,
    and does not tell the bot to trim ACTIONS.md unless the action index is strictly largest.
    """
    fixed_n = action_n = shared_n = 0
    for name, text in sections:
        n = len(text)
        if name == "action-index":
            action_n += n
        elif name == "shared-skills":
            shared_n += n
        else:
            fixed_n += n
    overflow = total - cap
    # Tie-break order: shared skills, then fixed cost, then the action index.
    ranked_parts = (("shared skills", shared_n), ("fixed cost", fixed_n), ("action index", action_n))
    label, size = ranked_parts[0]
    for name, n in ranked_parts[1:]:
        if n > size:
            label, size = name, n
    ranked = sorted(((n, len(t)) for n, t in sections), key=lambda x: (-x[1], x[0]))
    lines = ["FAIL %s: compiled prompt is %d characters (cap %d)." % (slug, total, cap), "Largest sections:"]
    for name, n in ranked:
        lines.append("  %s %d" % (name, n))
    lines.append("Fixed cost %d (thin prompt, routine, rule gists, footer)." % fixed_n)
    lines.append("Action index %d." % action_n)
    lines.append("Shared skills %d (skill and preference rows)." % shared_n)
    lines.append("Largest rows:")
    for name, n in sorted(row_sizes or [], key=lambda x: (-x[1], x[0]))[:12]:
        lines.append("  %s %d" % (name, n))
    if label == "action index":
        lines.append(
            "Cut this bot's own action index: cut %d characters, or ask the owner about the cap. Shorten those ACTIONS.md rows. Hard rules are copied verbatim and are never truncated."
            % overflow
        )
    elif label == "shared skills":
        lines.append(
            "Cut the shared skills: cut %d characters, or ask the owner about the cap. Do not trim this bot's ACTIONS.md for a shared cost."
            % overflow
        )
    else:
        lines.append(
            "Cut the fixed cost: cut %d characters, or ask the owner about the cap. Do not trim this bot's ACTIONS.md for a fixed cost."
            % overflow
        )
    return "\n".join(lines)


def compile_bot(fleet, bot, items, cap):
    slug = bot["slug"]
    role = bot.get("role") or ""
    raw_caps = bot.get("capabilities") or []
    if not isinstance(raw_caps, list):
        return {"ok": False, "reason": "bad-source", "error": "capabilities must be a list"}
    caps = sorted(set(raw_caps))
    for c in caps:
        if not isinstance(c, str) or not SLUG_RX.fullmatch(c):
            return {"ok": False, "reason": "bad-source", "error": "bad capability %r" % c}
    startup = startup_source(items)
    err = routine_error(startup["digest"] if startup else None)
    if err:
        return {"ok": False, "reason": "bad-source", "error": err}
    bot_dir = "bots/%s" % slug
    actions_path = bot_dir + "/kb/ACTIONS.md"
    rules_path = bot_dir + "/rules.md"
    shared_path = "local/shared/SHARED-SKILLS.md"
    bj_path = bot_dir + "/bot.json"
    if os.path.islink(bot_dir) or not os.path.isdir(bot_dir):
        return {"ok": False, "reason": "missing-bot-dir"}
    if os.path.islink(bj_path):
        return {"ok": False, "reason": "symlink"}
    if not os.path.isfile(bj_path):
        return {"ok": False, "reason": "missing-bot-json"}
    try:
        bj = json.loads(read_repo_text(bj_path))
    except (ValueError, json.JSONDecodeError) as e:
        return {"ok": False, "reason": "bad-source", "error": "bot.json: %s" % e}
    worktree = bj.get("worktree") or ""
    if not isinstance(worktree, str) or not worktree.strip():
        return {"ok": False, "reason": "bad-source", "error": "bot.json has no worktree"}
    if os.path.islink(actions_path):
        return {"ok": False, "reason": "symlink"}
    if not os.path.isfile(actions_path):
        return {"ok": False, "reason": "missing-actions"}
    if os.path.islink(shared_path):
        return {"ok": False, "reason": "symlink"}
    if not os.path.isfile(shared_path):
        return {"ok": False, "reason": "missing-shared-skills"}
    try:
        actions_text = read_repo_text(actions_path)
        shared_text = read_repo_text(shared_path)
        thin = render_thin(worktree.strip())
    except ValueError as e:
        return {"ok": False, "reason": "bad-source", "error": str(e)}
    chosen = []
    for src in items:
        if src["id"] == "startup":
            chosen.append(src)
        elif role_match(src["applies_to"], role, caps):
            chosen.append(src)
    chosen.sort(key=lambda s: s["id"])
    gists = [(s["id"], s["digest"]) for s in chosen if s["id"] != "startup"]
    try:
        actions, row_sizes = action_lines(actions_text, actions_path)
        skill_table, pref_rows = skill_rows(shared_text)
        slugs = known_slugs(fleet)
        for row in skill_table:
            check_applies(row["applies"], slugs, "skill %s" % row["name"])
        for pref in pref_rows:
            check_applies(pref["applies"], slugs, "preference %r" % (pref["action"] or ""))
        picked, skill_warns = relevant_skills(actions_text, skill_table, role)
        kept_prefs = relevant_prefs(pref_rows, actions_text, slug, role, picked)
        skills = skill_lines(picked) + [pref_line(p) for p in kept_prefs]
    except ValueError as e:
        return {"ok": False, "reason": "bad-source", "error": str(e)}
    prompt, sections = assemble(thin, startup["digest"], gists, actions, skills)
    payload = {
        "actions": actions,
        "capabilities": caps,
        "digests": [input_record(s) for s in chosen],
        "footer": FOOTER_BODY,
        "header": HEADER,
        "pre_action": startup["digest"],
        "role": role,
        "skills": skills,
        "thin": thin,
    }
    rules_sha = file_sha(rules_path)
    return {
        "ok": True,
        "prompt": prompt,
        "sections": sections,
        "input_hash": sha256_bytes(canon(payload)),
        "prompt_sha256": sha256_bytes(prompt),
        "inputs": [input_record(s) for s in chosen],
        "bot_inputs": {
            "actions_md_sha256": sha256_bytes(actions_text),
            "rules_md_sha256": rules_sha,
            "shared_skills_md_sha256": sha256_bytes(shared_text),
        },
        "role_map": {"capabilities": caps, "role": role},
        "over_cap": len(prompt) > cap,
        "cap": cap,
        "actions": actions,
        "skills": skills,
        "row_sizes": row_sizes,
        "warns": skill_warns,
        "input_paths": [actions_path, rules_path, shared_path, "templates/THIN-PROMPT.tmpl", "local/fleet.json"] + [s["path"] for s in chosen],
    }


def kit_version():
    if not os.path.isfile("fleet/VERSION"):
        return ""
    return open("fleet/VERSION", encoding="utf-8").read().strip()


def head_commit():
    return git_out("rev-parse", "HEAD") or "none"


def inputs_dirty(paths):
    """True when a prompt input differs from HEAD, including an untracked input."""
    paths = [p for p in dict.fromkeys(paths) if p]
    if not paths:
        return False
    if git_out("rev-parse", "--verify", "HEAD") is None:
        return True
    diff = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", *paths])
    if diff.returncode != 0:
        return True
    other = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", *paths], capture_output=True, text=True)
    return bool(other.stdout.strip())


def manifest_path(slug):
    return "local/prompts/%s.manifest.json" % slug


def prompt_path(slug):
    return "local/prompts/%s.md" % slug


def load_manifest(slug):
    path = manifest_path(slug)
    if not os.path.isfile(path) or os.path.islink(path):
        return None
    try:
        return json.loads(read_repo_text(path))
    except (ValueError, json.JSONDecodeError):
        return None


def inside_repo(path):
    """Refuse a path that leaves the repo. Call this before creating directories."""
    root = os.path.realpath(".")
    rel = os.path.normpath(path)
    if os.path.isabs(path) or rel.startswith(".."):
        raise ValueError("refusing to write outside the repo: %s" % path)
    cur = "."
    for part in rel.split("/"):
        if part in ("", "."):
            continue
        nxt = os.path.join(cur, part)
        if os.path.islink(nxt):
            real = os.path.realpath(nxt)
            try:
                if os.path.commonpath([root, real]) != root:
                    raise ValueError("refusing to write outside the repo: %s" % path)
            except ValueError as e:
                if "refusing to write" in str(e):
                    raise
                raise ValueError("refusing to write outside the repo: %s" % path)
        cur = nxt


def atomic_write(path, data):
    if isinstance(data, str):
        data = data.encode("utf-8")
    inside_repo(path)
    parent = os.path.dirname(path) or "."
    os.makedirs(parent, exist_ok=True)
    if os.path.islink(parent) or os.path.lexists(path) and os.path.islink(path):
        raise ValueError("refusing symlink %s" % path)
    fd, tmp = tempfile.mkstemp(prefix=".prompt-", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def dump_manifest(obj):
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=True) + "\n"


def fresh_built(slug, compiled):
    return {
        "bot_inputs": compiled["bot_inputs"],
        "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "git_commit": head_commit(),
        "git_commit_dirty": inputs_dirty(compiled.get("input_paths") or []),
        "input_hash": compiled["input_hash"],
        "inputs": compiled["inputs"],
        "kit_version": kit_version(),
        "prompt_sha256": compiled["prompt_sha256"],
        "role_map": compiled["role_map"],
        "slug": slug,
    }


def compose_manifest(slug, compiled):
    new_built = fresh_built(slug, compiled)
    old = load_manifest(slug)
    if (
        old
        and old.get("built")
        and old["built"].get("input_hash") == compiled["input_hash"]
        and old["built"].get("prompt_sha256") == compiled["prompt_sha256"]
    ):
        built = dict(old["built"])
        # The prompt bytes did not change. Refresh only the dirty flag so a
        # later commit of the same inputs is not still marked dirty.
        if built.get("git_commit_dirty") != new_built["git_commit_dirty"]:
            built["git_commit_dirty"] = new_built["git_commit_dirty"]
            built["git_commit"] = new_built["git_commit"]
        deployed = old.get("deployed", None)
    else:
        built = new_built
        deployed = old.get("deployed", None) if old else None
    return {"built": built, "deployed": deployed, "slug": slug}


def load_fleet():
    path = "local/fleet.json"
    if not os.path.lexists(path):
        return None
    if os.path.islink(path):
        sys.exit("build-prompt: refusing symlink local/fleet.json")
    try:
        return json.loads(read_repo_text(path))
    except (ValueError, json.JSONDecodeError) as e:
        sys.exit("build-prompt: local/fleet.json: %s" % e)


def mode_of(fleet, bot):
    raw = bot.get("prompt_mode") or fleet.get("prompt_mode") or "files"
    if raw not in ("files", "compiled"):
        sys.exit("build-prompt: bad prompt_mode %r for %s" % (raw, bot.get("slug")))
    return raw


def selected_bots(fleet, slugs):
    bots = fleet.get("bots") or []
    if not isinstance(bots, list):
        sys.exit("build-prompt: fleet.json bots must be a list")
    by = []
    known = {}
    for b in bots:
        s = b.get("slug")
        if not isinstance(s, str) or not SLUG_RX.fullmatch(s):
            sys.exit("build-prompt: bad slug in fleet.json")
        known[s] = b
        by.append(b)
    if not slugs:
        return sorted(by, key=lambda b: b["slug"])
    out = []
    for s in slugs:
        if s not in known:
            sys.exit("build-prompt: no bot %r in local/fleet.json" % s)
        out.append(known[s])
    return out


def retired(bot):
    return bot.get("role") == "retired" or bot.get("status") == "retired"


def cmd_build(slugs):
    fleet = load_fleet()
    if fleet is None:
        print("build-prompt: no local/fleet.json")
        return 0
    items, warns, errors = load_sources()
    for w in warns:
        print("WARN " + w, file=sys.stderr)
    if errors:
        for e in errors:
            print("FAIL " + e, file=sys.stderr)
        return 1
    cap = prompt_cap(fleet)
    rc = 0
    for bot in selected_bots(fleet, slugs):
        slug = bot["slug"]
        if retired(bot):
            print("build-prompt: %s retired, skipped" % slug)
            continue
        if mode_of(fleet, bot) != "compiled":
            print("build-prompt: %s prompt_mode files (thin prompt unchanged)" % slug)
            continue
        compiled = compile_bot(fleet, bot, items, cap)
        if not compiled.get("ok"):
            rc = 1
            msg = compiled.get("reason") or "error"
            if compiled.get("error"):
                msg = "%s (%s)" % (msg, compiled["error"])
            print("FAIL %s: %s" % (slug, msg), file=sys.stderr)
            continue
        if compiled["over_cap"]:
            rc = 1
            print(over_cap_report(slug, len(compiled["prompt"]), cap, compiled["sections"], compiled.get("row_sizes")), file=sys.stderr)
            continue
        manifest = compose_manifest(slug, compiled)
        try:
            atomic_write(prompt_path(slug), compiled["prompt"])
            atomic_write(manifest_path(slug), dump_manifest(manifest))
        except ValueError as e:
            print("FAIL %s: %s" % (slug, e), file=sys.stderr)
            return 1
        for w in compiled.get("warns") or []:
            print("WARN %s: %s" % (slug, w), file=sys.stderr)
        print("build-prompt: wrote %s (%d characters)" % (prompt_path(slug), len(compiled["prompt"])))
    return rc


def profiles_dir():
    return os.environ.get("BOT_FLEET_PROFILES_DIR", "").strip() or PROFILES_DEFAULT


def profile_description(agent_id):
    """Read-only. Never creates or writes a profile."""
    if not isinstance(agent_id, str) or not agent_id or agent_id in (".", "..") or "/" in agent_id or "\\" in agent_id:
        return None, "bad-agent-id"
    root = os.path.realpath(profiles_dir())
    if not os.path.isdir(root):
        return None, "profiles-dir-missing"
    path = os.path.join(root, agent_id, "profile.json")
    if os.path.islink(path) or not os.path.isfile(path):
        return None, "profile-missing"
    real = os.path.realpath(path)
    try:
        if os.path.commonpath([root, real]) != root:
            return None, "profile-outside"
    except ValueError:
        return None, "profile-outside"
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None, "profile-unreadable"
    desc = data.get("description")
    if not isinstance(desc, str):
        return None, "no-description"
    return desc, None


def description_matches(desc, prompt_sha):
    """Exact bytes, or the same text with one trailing newline added or removed."""
    if not isinstance(desc, str) or not prompt_sha:
        return False
    cands = [desc]
    if desc.endswith("\n"):
        cands.append(desc[:-1])
    else:
        cands.append(desc + "\n")
    return any(sha256_bytes(c) == prompt_sha for c in cands)


def ordered_reasons(reasons):
    return [r for r in REASON_ORDER if r in reasons]


def check_bot(fleet, bot, items, cap):
    slug = bot["slug"]
    mode = mode_of(fleet, bot)
    entry = {"drift": None, "drift_reason": None, "prompt_mode": mode, "reasons": [], "slug": slug, "stale": False}
    if retired(bot):
        entry["note"] = "retired"
        return entry
    if mode != "compiled":
        entry["drift_reason"] = "opt-out"
        return entry
    compiled = compile_bot(fleet, bot, items, cap)
    reasons = []
    if not compiled.get("ok"):
        entry["reasons"] = [compiled.get("reason") or "bad-source"]
        if compiled.get("error"):
            entry["error"] = compiled["error"]
        entry["stale"] = True
        return entry
    if compiled["over_cap"]:
        reasons.append("over-cap")
    man = load_manifest(slug)
    if not man or not man.get("built"):
        reasons.append("not-built")
    else:
        built = man["built"]
        got = file_sha(prompt_path(slug))
        if got != built.get("prompt_sha256"):
            reasons.append("prompt-file-mismatch")
        if not compiled["over_cap"] and compiled["input_hash"] != built.get("input_hash"):
            reasons.append("inputs-changed")
        dep = man.get("deployed")
        if not dep:
            reasons.append("not-deployed")
        elif dep.get("input_hash") != built.get("input_hash") or dep.get("prompt_sha256") != built.get("prompt_sha256"):
            reasons.append("built-differs-from-deployed")
        if dep and dep.get("prompt_sha256"):
            desc, why = profile_description(bot.get("id"))
            if why:
                entry["drift"] = None
                entry["drift_reason"] = why
            elif not description_matches(desc, dep.get("prompt_sha256")):
                entry["drift"] = True
                entry["drift_reason"] = "description-differs"
            else:
                entry["drift"] = False
                entry["drift_reason"] = "match"
    if "not-built" in reasons:
        reasons = [r for r in reasons if r not in ("not-deployed", "built-differs-from-deployed", "inputs-changed", "prompt-file-mismatch")]
    entry["reasons"] = ordered_reasons(reasons)
    entry["stale"] = bool(entry["reasons"])
    if compiled["over_cap"]:
        entry["characters"] = len(compiled["prompt"])
        entry["cap"] = cap
    return entry


def cmd_check(as_json, slugs=None):
    fleet = load_fleet()
    report = {"bots": [], "errors": [], "ok": True}
    if fleet is None:
        text = "build-prompt: no local/fleet.json\n"
        if as_json:
            print(json.dumps({"bots": [], "errors": [], "ok": True}, indent=2, sort_keys=True))
            print(text, file=sys.stderr, end="")
        else:
            print(text, end="")
        return 0
    items, warns, errors = load_sources()
    report["errors"] = errors
    for w in warns:
        print("WARN " + w, file=sys.stderr)
    cap = prompt_cap(fleet) if not errors else CAP_DEFAULT
    if not errors:
        for bot in selected_bots(fleet, slugs or []):
            report["bots"].append(check_bot(fleet, bot, items, cap))
    report["ok"] = not errors and not any(b["stale"] or b["drift"] is True for b in report["bots"])
    summary = plain_summary(report)
    if as_json:
        print(json.dumps(report, indent=2, sort_keys=True))
        print(summary, file=sys.stderr, end="")
    else:
        print(summary, end="")
    return 0 if report["ok"] else 1


def plain_summary(report):
    lines = []
    stale = [b for b in report["bots"] if b["stale"]]
    drifted = [b for b in report["bots"] if b["drift"] is True]
    if report.get("errors"):
        lines.append("build-prompt: %d error(s)" % len(report["errors"]))
        for e in report["errors"]:
            lines.append("FAIL " + e)
    elif not stale and not drifted:
        lines.append("build-prompt: no stale bots")
    else:
        lines.append("build-prompt: %d stale, %d drift" % (len(stale), len(drifted)))
    for b in stale:
        why = ", ".join(b["reasons"])
        if b.get("error"):
            why = why + "; " + b["error"]
        lines.append("- %s: stale (%s)" % (b["slug"], why))
    for b in drifted:
        lines.append("- %s: drift (%s)" % (b["slug"], b["drift_reason"]))
    files = [b["slug"] for b in report["bots"] if b["prompt_mode"] == "files"]
    if files:
        lines.append("file mode: " + ", ".join(files))
    return "\n".join(lines) + "\n"


def git_bytes(rev, path):
    r = subprocess.run(["git", "ls-tree", rev, "--", path], capture_output=True)
    if r.returncode != 0:
        return None
    line = r.stdout.decode("utf-8", "replace").strip()
    if not line:
        return None
    mode = line.split(" ", 1)[0]
    if mode not in ("100644", "100755"):
        return "BADMODE"
    r2 = subprocess.run(["git", "show", "%s:%s" % (rev, path)], capture_output=True)
    if r2.returncode != 0:
        return None
    return r2.stdout


def digest_at(rev, path):
    blob = git_bytes(rev, path)
    if not isinstance(blob, (bytes, bytearray)):
        return None
    try:
        text = blob.decode("utf-8")
    except UnicodeDecodeError:
        return None
    kind = "fleet" if path.startswith("local/") else "kit"
    src = parse_source(path, text, kind)
    return src.get("digest")


def lines_at(rev, slug, role):
    actions = git_bytes(rev, "bots/%s/kb/ACTIONS.md" % slug)
    shared = git_bytes(rev, "local/shared/SHARED-SKILLS.md")
    if not isinstance(actions, (bytes, bytearray)) or not isinstance(shared, (bytes, bytearray)):
        return None, None
    try:
        atext, stext = actions.decode("utf-8"), shared.decode("utf-8")
    except UnicodeDecodeError:
        return None, None
    try:
        actions, _sizes = action_lines(atext, "bots/%s/kb/ACTIONS.md" % slug)
        table, prefs = skill_rows(stext)
        picked, _warns = relevant_skills(atext, table, role)
        kept = relevant_prefs(prefs, atext, slug, role, picked)
    except ValueError:
        return None, None
    return actions, skill_lines(picked) + [pref_line(p) for p in kept]


def cmd_changelog():
    fleet = load_fleet()
    if fleet is None:
        print("No fleet is configured, so there is no prompt update.")
        return 0
    items, warns, errors = load_sources()
    for w in warns:
        print("WARN " + w, file=sys.stderr)
    if errors:
        for e in errors:
            print("FAIL " + e, file=sys.stderr)
        return 1
    cap = prompt_cap(fleet)
    version = kit_version()
    waiting, over, files, retired_slugs = [], [], [], []
    compiled = []
    for bot in selected_bots(fleet, []):
        slug = bot["slug"]
        if retired(bot):
            retired_slugs.append(slug)
            continue
        if mode_of(fleet, bot) != "compiled":
            files.append(slug)
            continue
        result = compile_bot(fleet, bot, items, cap)
        result["bot"] = bot
        compiled.append(result)
        if not result.get("ok") or result.get("over_cap"):
            over.append(slug)
        else:
            man = load_manifest(slug) or {}
            dep = man.get("deployed")
            changed = not dep or dep.get("input_hash") != result["input_hash"]
            if changed:
                waiting.append(result)
    lines = []
    lines.append("One prompt update for kit %s. Approve this once for the whole fleet, not once per bot." % (version or "(unknown)"))
    lines.append("")
    if not waiting and not over:
        lines.append("No prompt update is waiting. Compiled prompts match what was marked deployed.")
    else:
        if waiting:
            lines.append("Waiting bots: %s." % ", ".join(r["bot"]["slug"] for r in waiting))
        if over:
            lines.append("Over the size cap, so not included: %s." % ", ".join(over))
            lines.append("The fix is for that bot to shorten its own ACTIONS.md rows. Hard rules are copied verbatim and are never truncated.")
    if files:
        lines.append("File mode (no prompt change): %s." % ", ".join(files))
    if retired_slugs:
        lines.append("Retired (skipped): %s." % ", ".join(retired_slugs))
    # Rule diffs across waiting bots, keyed by id. Removed ids come from the deployed inputs.
    by_id = {}
    why_by = {s["id"]: s.get("prompt_why") or "" for s in items}
    for result in waiting:
        dep = (load_manifest(result["bot"]["slug"]) or {}).get("deployed") or {}
        rev = dep.get("git_commit")
        if dep.get("git_commit_dirty"):
            rev = None
        old_by = {i.get("id"): i for i in (dep.get("inputs") or [])}
        current_ids = set()
        for inp in result["inputs"]:
            current_ids.add(inp["id"])
            rec = by_id.setdefault(inp["id"], {"id": inp["id"], "path": inp["path"], "bots": [], "after": None, "before": None, "why": why_by.get(inp["id"]) or ""})
            rec["bots"].append(result["bot"]["slug"])
            rec["after"] = next((s["digest"] for s in items if s["id"] == inp["id"]), None)
            rec["why"] = why_by.get(inp["id"]) or rec.get("why") or ""
            prev = old_by.get(inp["id"])
            if not dep:
                rec["before"] = None
                rec["undeployed"] = True
            elif rev and prev:
                rec["before"] = digest_at(rev, prev.get("path") or inp["path"])
            elif rev:
                rec["before"] = digest_at(rev, inp["path"])
            elif dep:
                rec["before"] = "(built from uncommitted files; the recorded commit does not hold this text)"
        for iid, prev in old_by.items():
            if iid in current_ids:
                continue
            rec = by_id.setdefault(iid, {"id": iid, "path": prev.get("path"), "bots": [], "after": None, "before": None, "why": "Removed from this bot's prompt.", "removed": True})
            rec["bots"].append(result["bot"]["slug"])
            rec["removed"] = True
            rec["why"] = "Removed from this bot's prompt."
            if not dep:
                rec["undeployed"] = True
            elif rev and prev.get("path"):
                rec["before"] = digest_at(rev, prev["path"])
            else:
                rec["before"] = "(built from uncommitted files; the recorded commit does not hold this text)"
    shown = False
    for iid in sorted(by_id):
        rec = by_id[iid]
        after = rec.get("after")
        before = rec.get("before")
        if before == after and not rec.get("undeployed") and not rec.get("removed"):
            continue
        shown = True
        why = rec.get("why") or "This rule has no prompt_why. The before and after text are the change."
        lines.append("")
        lines.append('Rule "%s" changed for %s.' % (iid, ", ".join(sorted(set(rec["bots"])))))
        lines.append("Why: %s" % why)
        lines.append("Before:")
        lines.append(before if before else "(not deployed yet)")
        lines.append("After:")
        lines.append(after if after else "(removed)")
    for result in waiting:
        bot = result["bot"]
        slug = bot["slug"]
        dep = (load_manifest(slug) or {}).get("deployed") or {}
        rev = dep.get("git_commit")
        role = (dep.get("role_map") or {}).get("role") or bot.get("role")
        if rev:
            old_actions, old_skills = lines_at(rev, slug, role)
        else:
            old_actions, old_skills = None, None
        new_actions, new_skills = result.get("actions") or [], result.get("skills") or []
        if old_actions == new_actions and old_skills == new_skills and dep:
            continue
        shown = True
        lines.append("")
        lines.append("%s action index changed." % slug)
        lines.append("Before:")
        if not dep or old_actions is None:
            lines.append("(not deployed yet)")
        else:
            lines.extend(old_actions or ["(no rows)"])
            if old_skills:
                lines.append("Shared skills:")
                lines.extend(old_skills)
        lines.append("After:")
        lines.extend(new_actions or ["(no rows)"])
        if new_skills:
            lines.append("Shared skills:")
            lines.extend(new_skills)
    if waiting:
        lines.append("")
        lines.append("After you say yes, paste each waiting bot's local/prompts/<slug>.md into that bot's platform profile.")
        lines.append("Scripts do not edit live profiles. Then run fleet/scripts/build-prompt.sh --mark-deployed <slug> for each bot you pasted.")
    if not shown and waiting:
        lines.append("")
        lines.append("The waiting bots differ from what is marked deployed. Rebuild, then paste the prompt files.")
    print("\n".join(lines))
    return 1 if over or errors else 0


def mark_deployed(slug):
    if not SLUG_RX.fullmatch(slug):
        sys.exit("build-prompt: bad slug")
    fleet = load_fleet()
    if fleet is None:
        sys.exit("build-prompt: no local/fleet.json")
    bot = next((b for b in fleet.get("bots") or [] if b.get("slug") == slug), None)
    if not bot:
        sys.exit("build-prompt: no bot %r" % slug)
    if retired(bot) or mode_of(fleet, bot) != "compiled":
        sys.exit("build-prompt: %s is not a compiled bot" % slug)
    items, warns, errors = load_sources()
    for w in warns:
        print("WARN " + w, file=sys.stderr)
    if errors:
        for e in errors:
            print("FAIL " + e, file=sys.stderr)
        return 1
    compiled = compile_bot(fleet, bot, items, prompt_cap(fleet))
    if not compiled.get("ok"):
        print("FAIL %s: %s" % (slug, compiled.get("reason") or compiled.get("error")), file=sys.stderr)
        return 1
    if compiled["over_cap"]:
        print(over_cap_report(slug, len(compiled["prompt"]), compiled["cap"], compiled["sections"], compiled.get("row_sizes")), file=sys.stderr)
        return 1
    man = load_manifest(slug)
    if not man or not man.get("built"):
        print("FAIL %s: not built; run build-prompt.sh first" % slug, file=sys.stderr)
        return 1
    if man["built"].get("input_hash") != compiled["input_hash"] or man["built"].get("prompt_sha256") != compiled["prompt_sha256"]:
        print("FAIL %s: built prompt is behind the files; rebuild before --mark-deployed" % slug, file=sys.stderr)
        return 1
    if file_sha(prompt_path(slug)) != compiled["prompt_sha256"]:
        print("FAIL %s: prompt file does not match the built manifest; rebuild" % slug, file=sys.stderr)
        return 1
    if man["built"].get("git_commit_dirty") or inputs_dirty(compiled.get("input_paths") or []):
        print("FAIL %s: built from uncommitted edits; commit the inputs before --mark-deployed" % slug, file=sys.stderr)
        return 1
    desc, why = profile_description(bot.get("id"))
    if desc is not None and not description_matches(desc, compiled["prompt_sha256"]):
        print("FAIL %s: live profile description does not match this prompt" % slug, file=sys.stderr)
        return 1
    if why and why not in ("profiles-dir-missing", "profile-missing", "no-description"):
        print("WARN %s: %s" % (slug, why), file=sys.stderr)
    man["deployed"] = copy.deepcopy(man["built"])
    atomic_write(manifest_path(slug), dump_manifest(man))
    print("build-prompt: marked %s deployed" % slug)
    return 0


def resolve_base():
    """PR base, or the previous commit on a main push. A clean main checkout is not compared to itself.

    An unreachable base (a force-push that dropped the SHA) falls back to the merge-base.
    If that is also missing, there is no base and the check is skipped.
    """
    unreachable = False
    for key in ("BOT_FLEET_PROMPT_BASE", "CLASSIFY_BASE_SHA"):
        env = os.environ.get(key, "").strip()
        if env and not re.fullmatch(r"0+", env):
            if subprocess.run(["git", "cat-file", "-e", "%s^{commit}" % env], capture_output=True).returncode == 0:
                return env
            print("WARN prompt-versions: base %s is unreachable; falling back to merge-base" % env, file=sys.stderr)
            unreachable = True
            break
    head = git_out("rev-parse", "--verify", "HEAD")
    origin = git_out("rev-parse", "--verify", "origin/main")
    if not unreachable and head and origin and head == origin:
        parent = git_out("rev-parse", "--verify", "HEAD^")
        if parent:
            return parent
    if origin and head:
        mb = git_out("merge-base", "origin/main", "HEAD")
        if mb:
            return mb
    if unreachable:
        return None
    return head


def intentional_removals():
    """Paths listed in fleet/PROMPT-REMOVALS may be deleted on purpose."""
    path = "fleet/PROMPT-REMOVALS"
    if not os.path.isfile(path) or os.path.islink(path):
        return set()
    out = set()
    for line in read_repo_text(path).splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.add(line)
    return out


def parse_git_text(rev, path):
    blob = git_bytes(rev, path)
    if blob is None:
        return None
    if blob == "BADMODE":
        return "BADMODE"
    try:
        return blob.decode("utf-8")
    except UnicodeDecodeError:
        return "BADMODE"


def bump_status(old, new):
    if new is None:
        if old and old.get("digest"):
            return "fail-deleted"
        return "ok"
    if old is None or not old.get("has_front_matter"):
        return "ok"
    old_sha = old.get("digest_sha256")
    new_sha = new.get("digest_sha256")
    old_ver = old.get("prompt_version")
    new_ver = new.get("prompt_version")
    if old_ver is not None and new_ver is not None and new_ver < old_ver:
        return "fail-decrease"
    if old.get("applies_to") != new.get("applies_to") and old_ver == new_ver:
        return "fail-applies"
    if old_sha != new_sha and old_ver == new_ver:
        return "fail"
    if old_sha == new_sha and old_ver != new_ver and old_ver is not None and new_ver is not None:
        return "warn"
    return "ok"


def cmd_check_versions():
    fails, warns = [], []
    for path in local_paths():
        try:
            text = read_repo_text(path)
        except ValueError as e:
            fails.append(str(e))
            continue
        src = parse_source(path, text, "fleet")
        if src.get("error"):
            fails.append("%s: %s" % (path, src["error"]))
        elif not src.get("digest"):
            warns.append("%s: no Prompt digest; it is not part of the compiled prompt" % path)
        elif src.get("warn"):
            warns.append("%s: %s" % (path, src["warn"]))
    base = resolve_base()
    if base is None:
        print("prompt-versions: skipped (no git base)")
        return 0
    for path in kit_paths():
        try:
            text = read_repo_text(path)
        except ValueError as e:
            fails.append(str(e))
            continue
        new = parse_source(path, text, "kit")
        if new.get("error"):
            fails.append("%s: %s" % (path, new["error"]))
            continue
        old_text = parse_git_text(base, path)
        if old_text == "BADMODE":
            fails.append("%s: base blob is not a regular file" % path)
            continue
        old = parse_source(path, old_text, "kit") if isinstance(old_text, str) else None
        status = bump_status(old, new)
        if status == "fail":
            fails.append("%s: prompt digest changed but prompt_version did not" % path)
        elif status == "fail-decrease":
            fails.append("%s: prompt_version decreased" % path)
        elif status == "fail-applies":
            fails.append("%s: applies_to changed but prompt_version did not" % path)
        elif status == "warn":
            warns.append("%s: prompt_version changed but the prompt digest did not" % path)
    current = set(kit_paths())
    for path in sorted(kit_paths_at(base)):
        if path in current:
            continue
        old_text = parse_git_text(base, path)
        if not isinstance(old_text, str) or old_text == "BADMODE":
            fails.append("%s: kit prompt source removed and the base blob is not readable" % path)
            continue
        old = parse_source(path, old_text, "kit")
        if old.get("digest") and path not in intentional_removals():
            fails.append("%s: kit prompt source removed" % path)
        elif old.get("digest"):
            warns.append("%s: kit prompt source removed, listed in fleet/PROMPT-REMOVALS" % path)
    ids = []
    for path in kit_paths():
        try:
            src = parse_source(path, read_repo_text(path), "kit")
        except ValueError:
            continue
        if src.get("id"):
            ids.append(src["id"])
    for i in sorted({x for x in ids if ids.count(x) > 1}):
        fails.append("duplicate prompt id %s" % i)
    for w in warns:
        print("WARN " + w)
    for f in fails:
        print("FAIL " + f)
    if fails:
        print("prompt-versions: FAILED")
        return 1
    if warns:
        print("prompt-versions: OK (%d warning%s)" % (len(warns), "" if len(warns) == 1 else "s"))
    else:
        print("prompt-versions: OK")
    return 0


def main(argv):
    chdir_root()
    if not argv:
        return cmd_build([])
    if argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    if argv[0] == "--check":
        rest = [a for a in argv[1:] if a != "--json"]
        for s in rest:
            if not SLUG_RX.fullmatch(s):
                sys.exit("usage: build-prompt.sh --check [--json] [slug...]")
        return cmd_check("--json" in argv[1:], rest)
    if argv[0] == "--json":
        sys.exit("usage: build-prompt.sh --check --json")
    if argv[0] == "--changelog":
        if argv[1:]:
            sys.exit("usage: build-prompt.sh --changelog")
        return cmd_changelog()
    if argv[0] == "--mark-deployed":
        if len(argv) != 2:
            sys.exit("usage: build-prompt.sh --mark-deployed <slug>")
        return mark_deployed(argv[1])
    if argv[0] == "--check-versions":
        if argv[1:]:
            sys.exit("usage: build-prompt.sh --check-versions")
        return cmd_check_versions()
    if argv[0].startswith("-"):
        sys.exit("usage: build-prompt.sh [slug...] | --check [--json] | --changelog | --mark-deployed <slug> | --check-versions")
    return cmd_build(argv)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(0)
