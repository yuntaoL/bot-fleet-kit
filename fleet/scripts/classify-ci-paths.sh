#!/usr/bin/env bash
# Classify a git name-status list as "docs-only" or "full" (fail-closed).
#
# docs-only: every change is an add or modify of an explicit inert path, or a
# rename whose old AND new paths are both inert:
#   bots/<slug>/journal/YYYY-MM-DD.md
#   bots/<slug>/kb/**/*.md
# slug is [a-z0-9-]+. No glob fallback: unknown paths do not match.
#
# full: anything else. Deletions, copies, type changes, renames that touch a
# non-inert path, unparseable lines, empty diffs, zero or non-hex SHAs, git
# failures, conflicting arguments, and classifier errors are full.
# Also full: a NUL byte anywhere in the input; a path that is not printable
# ASCII (Unicode slugs, controls, DEL); a git-quoted path (tab, newline, or
# non-ASCII as C escapes); a tab that adds a field; a record split only by
# LF (CR, VT, FF, NEL, U+2028, U+2029 stay inside the record); and a '#' line
# that is not a fixture header (a comment must not hide a path).
#
# CI does not execute this worktree copy for the skip decision. The workflow
# runs the base commit's blob of this file, and records full without asking
# if this file, its tests, or .github/workflows/validate.yml changed, or if
# that blob is missing or not a regular file. Tests of this file still run
# from the commit under test.
#
# Why selftest may be skipped: selftest.sh does not read bots/<slug>/journal
# or bots/<slug>/kb from the checkout under test. It builds a scratch fleet
# from fleet/, templates/, .github/, README.md, LICENSE and examples/.
# validate.sh reads bots/*/kb/**/*.md (front matter, INDEX links) and calls
# check-journal.sh. audit.sh greps tracked files outside fleet/ and .github/
# (that includes journal and kb) and calls check-journal.sh. Those always run.
#
# Prints exactly one token to stdout: docs-only | full
# Writes the reason to stderr. Exit 0 on classification results, including
# fail-closed results, so a workflow step can keep going and run selftest.
# Exit non-zero only when the interpreter itself fails to start; callers must
# treat that as full too.
#
# Usage:
#   classify-ci-paths.sh --stdin
#   classify-ci-paths.sh --name-status-file PATH
#   classify-ci-paths.sh --base SHA --head SHA
set -uo pipefail
unset CLASSIFY_STDIN_FILE
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || true
# The Python program is supplied on this script's stdin via the heredoc below,
# so --stdin input must be captured first.
for a in "$@"; do
  if [ "$a" = "--stdin" ] || [ "$a" = "-" ]; then
    CLASSIFY_STDIN_FILE="$(mktemp)"
    cat > "$CLASSIFY_STDIN_FILE"
    export CLASSIFY_STDIN_FILE
    trap 'rm -f "$CLASSIFY_STDIN_FILE"' EXIT
    break
  fi
done
python3 - "$@" << 'PY'
import os, re, subprocess, sys

DOCS_ONLY = "docs-only"
FULL = "full"

# Explicit allowlist. Anchored. New unknown paths do not match.
INERT = (
    re.compile(r"^bots/[a-z0-9-]+/journal/[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$"),
    re.compile(r"^bots/[a-z0-9-]+/kb/.+\.md$"),
)
RENAME = re.compile(r"^R[0-9]*$")
COPY = re.compile(r"^C[0-9]*$")
ZERO_SHA = re.compile(r"^0+$")
SHA = re.compile(r"^[0-9a-fA-F]{4,64}$")

def emit(mode, reason):
    print(reason, file=sys.stderr)
    print(mode)
    sys.exit(0)

# Fixture files carry only these headers. Any other '#' line can hide a path.
FIXTURE_HEADER = re.compile(r"^# (?:expect: (?:docs-only|full)|case: [A-Za-z0-9._-]+)$")

def is_inert(path):
    if not path or path.startswith("/") or path.startswith("./") or "\\" in path:
        return False
    # Printable ASCII only. Do not unquote git's C-quoted paths and do not
    # treat Unicode, controls, DEL, or NUL as the allowlist. A kb markdown
    # file whose name is non-ASCII is not proven to be the same shape.
    if any(ord(ch) < 0x20 or ord(ch) > 0x7e for ch in path):
        return False
    parts = path.split("/")
    if any(p in ("", ".", "..") for p in parts):
        return False
    return any(rx.fullmatch(path) for rx in INERT)

def classify_lines(text):
    # A NUL is not a git path byte. Parsing past it could drop a second path.
    if "\0" in text:
        return FULL, "NUL byte in name-status (fail-closed)"
    lines = []
    # LF only. splitlines() also breaks on CR, VT, FF, NEL, and U+2028/U+2029,
    # so a smuggled separator plus a '#' line would hide the rest. One trailing
    # CR (CRLF) is stripped; an embedded CR stays in the record and fails closed.
    for ln in text.split("\n"):
        if ln.endswith("\r"):
            ln = ln[:-1]
        if ln.strip() == "":
            continue
        if ln.lstrip().startswith("#"):
            if FIXTURE_HEADER.fullmatch(ln.strip()):
                continue
            return FULL, f"comment line is not a fixture header (fail-closed): {ln!r}"
        lines.append(ln)
    if not lines:
        return FULL, "empty diff (fail-closed)"
    for ln in lines:
        parts = ln.split("\t")
        if len(parts) < 2 or parts[0] == "":
            return FULL, f"unparseable name-status line (fail-closed): {ln!r}"
        status, paths = parts[0], parts[1:]
        if COPY.fullmatch(status):
            return FULL, f"copy treated as full (fail-closed): {ln}"
        if RENAME.fullmatch(status):
            if len(paths) != 2 or not paths[0] or not paths[1]:
                return FULL, f"rename missing paths (fail-closed): {ln!r}"
            old, new = paths
            if is_inert(old) and is_inert(new):
                continue
            return FULL, f"rename is not inert-to-inert (fail-closed): {old} -> {new}"
        if status == "D":
            if len(paths) != 1:
                return FULL, f"deletion missing path (fail-closed): {ln!r}"
            return FULL, f"deletion treated as full (fail-closed): {paths[0]}"
        if status in ("A", "M"):
            if len(paths) != 1:
                return FULL, f"add/modify has extra fields (fail-closed): {ln!r}"
            path = paths[0]
            if not is_inert(path):
                return FULL, f"path is not on the inert allowlist (fail-closed): {path}"
            continue
        return FULL, f"unknown name-status {status!r} (fail-closed)"
    return DOCS_ONLY, "all paths are inert allowlist adds/modifies (or inert-to-inert renames)"

def git_diff(base, head):
    if not base or not head or ZERO_SHA.fullmatch(base) or ZERO_SHA.fullmatch(head):
        return None, "missing or zero SHA (new branch / unknown range; fail-closed)"
    if not SHA.fullmatch(base) or not SHA.fullmatch(head):
        return None, "SHA is not hex (fail-closed)"
    # -C / --find-copies so a copy is status C (always full) rather than a plain add.
    # Rename detection stays on so an inert-to-inert rename is not a deletion+add.
    # External diff drivers and textconv are off so local git config cannot hide a path.
    # Revisions before "--". SHAs are checked as hex above, so they are not options.
    # "--" keeps a later pathspec from being read as a revision; there is no pathspec.
    r = subprocess.run(
        ["git", "-c", "color.ui=false", "-c", "core.quotePath=true",
         "diff", "--no-ext-diff", "--no-textconv", "--name-status",
         "--find-renames", "--find-copies", base, head, "--"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "git diff failed").strip().splitlines()
        hint = err[0] if err else "git diff failed"
        return None, f"git diff failed (fail-closed): {hint}"
    return r.stdout, None

def parse_args(argv):
    stdin = False
    path = None
    base = head = None
    base_set = head_set = False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("--stdin", "-"):
            stdin = True
        elif a == "--name-status-file" and i + 1 < len(argv):
            i += 1
            path = argv[i]
        elif a == "--base" and i + 1 < len(argv):
            i += 1
            base = argv[i]
            base_set = True
        elif a == "--head" and i + 1 < len(argv):
            i += 1
            head = argv[i]
            head_set = True
        elif a in ("-h", "--help"):
            return "help", None
        else:
            return None, f"unrecognized argument (fail-closed): {a}"
        i += 1
    modes = int(stdin) + int(path is not None) + int(base_set or head_set)
    if modes == 0:
        return None, "no input (fail-closed); use --stdin, --name-status-file, or --base/--head"
    if modes != 1:
        return None, "conflicting inputs (fail-closed); pass only one of --stdin, --name-status-file, --base/--head"
    if base_set != head_set:
        return None, "missing or zero SHA (new branch / unknown range; fail-closed)"
    if stdin:
        return "stdin", None
    if path is not None:
        return "file", path
    return "range", (base, head)

def main(argv):
    kind, extra = parse_args(argv)
    if kind == "help":
        print("usage: classify-ci-paths.sh --stdin | --name-status-file PATH | --base SHA --head SHA", file=sys.stderr)
        emit(FULL, "help requested (fail-closed default)")
    if kind is None:
        emit(FULL, extra)
    if kind == "stdin":
        path = os.environ.get("CLASSIFY_STDIN_FILE")
        if path:
            try:
                text = open(path, encoding="utf-8").read()
            except Exception as e:
                emit(FULL, f"cannot read captured stdin (fail-closed): {e}")
        else:
            text = sys.stdin.read()
        mode, reason = classify_lines(text)
        emit(mode, reason)
    if kind == "file":
        try:
            text = open(extra, encoding="utf-8").read()
        except Exception as e:
            emit(FULL, f"cannot read {extra} (fail-closed): {e}")
        mode, reason = classify_lines(text)
        emit(mode, reason)
    if kind == "range":
        base, head = extra
        text, err = git_diff(base, head)
        if err:
            emit(FULL, err)
        mode, reason = classify_lines(text)
        emit(mode, reason)
    emit(FULL, "internal fallthrough (fail-closed)")

if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except Exception as e:
        emit(FULL, f"classifier error (fail-closed): {e}")
PY
