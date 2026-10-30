#!/usr/bin/env python3
"""0.10.0 path rewriter: old layout (template/, manager/) -> new layout (fleet/, templates/, local/).
usage: rewrite-paths.py [--dry-run] FILE...      prints one line per changed file (and the count of rewrites).
Only rewrites path-shaped tokens (not prose such as "the manager" or URLs like bot-fleet-template/...).
Callers decide WHICH files: history (journals, CHANGELOGs, *.old-prompt.md) and rendered prompts are never passed in."""
import re, sys
B = r"(?<![\w.\-/])"   # not part of a longer path, word or URL
MAP = [  # first match wins; longest/most specific first
    ("template/defaults/THIN-PROMPT.tmpl", "templates/THIN-PROMPT.tmpl"),
    ("template/defaults/ROUTINE-PROMPT.tmpl", "templates/ROUTINE-PROMPT.tmpl"),
    ("template/defaults/fleet/skills", "fleet/skills"),
    ("template/defaults/fleet", "templates/local"),
    ("template/defaults/roles", "fleet/roles"),
    ("template/defaults/bot", "templates/bot"),
    ("template/defaults", "templates"),
    ("template/", "fleet/"),
    ("manager/local/roles", "local/roles"),
    ("manager/local/*", "local/rules/*"),
    ("manager/local/", "local/rules/"),
    ("manager/local", "local/rules"),
    ("manager/roles", "fleet/roles"),
    ("manager/", "local/"),
]
# bare "template/" / "manager/" are rewritten only before a path segment or a code/space boundary,
# so "manager/builder" (prose: two roles) is left alone.
MGR_KIDS = r"(?=fleet\.json|overrides\.md|CHANGELOG\.md|registry|shared|scripts|roles|local|README|[`'\"\s)*]|$)"
TPL_KIDS = r"(?=VERSION|OWNERS\.json|rules|docs|scripts|schema|migrations|defaults|[`'\"\s)*]|$)"
pat = "|".join(B + re.escape(o) + (MGR_KIDS if o == "manager/" else TPL_KIDS if o == "template/" else "") for o, _ in MAP)
RX = re.compile(pat, re.M)
LOOK = dict(MAP)
def rewrite(t):
    return RX.subn(lambda m: LOOK[m.group(0)], t)
if __name__ == "__main__":
    a = sys.argv[1:]; dry = bool(a) and a[0] == "--dry-run"; a = a[1:] if dry else a
    for f in a:
        try: t = open(f, encoding="utf-8").read()
        except (UnicodeDecodeError, IsADirectoryError, FileNotFoundError): continue
        n, k = rewrite(t)
        if k:
            print(f"{'would rewrite' if dry else 'rewrote'} {f} ({k})")
            if not dry: open(f, "w", encoding="utf-8").write(n)
