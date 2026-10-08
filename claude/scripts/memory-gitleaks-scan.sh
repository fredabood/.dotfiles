#!/usr/bin/env bash
# memory-gitleaks-scan.sh — run gitleaks, with an explicit config, over a given set of files in a
# git work tree (LAB-2457). The PreToolUse hook claude/hooks/memory-gitleaks-check.sh calls it for
# every memory-vault commit; a git hook or vault-sync can call it the same way.
#
#   memory-gitleaks-scan.sh <toplevel> <config> <listfile>
#
#   <toplevel>  the work tree the paths are relative to
#   <config>    the gitleaks config, passed to gitleaks as `-c`. gitleaks otherwise resolves its
#               config from the SCAN TARGET (here a temp dir), so leaving `-c` out would silently
#               run on the defaults and miss every allowlist. The test suite's mutation case
#               deletes `-c` and requires the placeholder case to go red.
#   <listfile>  NUL-separated, toplevel-relative paths
#
# Content scanned per path: the working-tree file (a regular file only, never through a symlink)
# and, when it differs or the working-tree file is absent, the staged blob (`git show :<path>`).
# Scanning both is the strict reading: whichever of the two the commit takes, it was scanned.
#
# Exit codes (testing.md → Vacuous checks):
#   0  at least one path examined, no finding
#   1  at least one finding
#   2  invalid run: gitleaks missing, config unreadable, zero paths examined, or gitleaks failed
#
# Every line goes to stderr. Findings are reported with gitleaks `--redact`, and only the file,
# line and rule id are printed, so a secret value never reaches a transcript.
#
# Limit, printed on every run: gitleaks is a keyword-and-entropy check. Its default stopword
# allowlist suppressed a probe value of entropy 4.77 during LAB-2288, so a real credential that
# contains a word like `test` can pass.
set -uo pipefail

TAG="memory-gitleaks-check"

if [ $# -ne 3 ]; then
    printf '%s: usage: memory-gitleaks-scan.sh <toplevel> <config> <listfile>\n' "$TAG" >&2
    exit 2
fi
TOP="$1"; CONFIG="$2"; LIST="$3"

if ! command -v gitleaks >/dev/null 2>&1; then
    printf '%s: gitleaks not installed (brew install gitleaks) — nothing was scanned\n' "$TAG" >&2
    exit 2
fi
if [ ! -f "$CONFIG" ] || [ ! -r "$CONFIG" ]; then
    printf '%s: no .gitleaks.toml at %s — refusing to scan on gitleaks defaults\n' "$TAG" "$CONFIG" >&2
    exit 2
fi
if [ ! -r "$LIST" ]; then
    printf '%s: %s: cannot read the path list %s — nothing was scanned\n' "$TAG" "$TOP" "$LIST" >&2
    exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/memory-gitleaks-scan.XXXXXX")" || {
    printf '%s: could not create a temp dir — nothing was scanned\n' "$TAG" >&2
    exit 2
}
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scan"

# materialize: copy each path's content under $TMP/scan/{worktree,staged}/<path>; print N.
if ! N=$(python3 -I - "$TOP" "$LIST" "$TMP/scan" <<'PY'
import os, subprocess, sys

top, listfile, root = sys.argv[1], sys.argv[2], sys.argv[3]
with open(listfile, "rb") as f:
    paths = [p.decode("utf-8", "surrogateescape") for p in f.read().split(b"\0") if p]

def safe(rel):
    return not os.path.isabs(rel) and ".." not in rel.split("/")

def write(kind, rel, data):
    dest = os.path.join(root, kind, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(data)

examined = 0
for rel in dict.fromkeys(paths):
    if not safe(rel):
        print("memory-gitleaks-check: skipped — unsafe path in the list: %r" % rel, file=sys.stderr)
        continue
    wt = None
    full = os.path.join(top, rel)
    if os.path.isfile(full) and not os.path.islink(full):
        with open(full, "rb") as f:
            wt = f.read()
    r = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", top, "show", ":" + rel],
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    staged = r.stdout if r.returncode == 0 else None
    if wt is None and staged is None:
        continue
    if wt is not None:
        write("worktree", rel, wt)
    if staged is not None and staged != wt:
        write("staged", rel, staged)
    examined += 1
print(examined)
PY
); then
    printf '%s: %s: could not read the files to scan (python3 failed) — nothing was scanned\n' "$TAG" "$TOP" >&2
    exit 2
fi

if [ "$N" -eq 0 ]; then
    printf '%s: %s: 0 staged path(s) examined — nothing to scan\n' "$TAG" "$TOP" >&2
    exit 2
fi

gitleaks dir "$TMP/scan" -c "$CONFIG" --redact --no-banner --log-level warn \
    --report-format json --report-path "$TMP/report.json" --exit-code 1 >/dev/null 2>"$TMP/gitleaks.err"
GRC=$?

finish() {
    printf '%s: %s: %s staged path(s) examined\n' "$TAG" "$TOP" "$N" >&2
    printf "%s: keyword-and-entropy check, not a proof — gitleaks' default stopwords can suppress a real credential\n" "$TAG" >&2
    exit "$1"
}

if [ "$GRC" -eq 0 ]; then
    finish 0
fi

# gitleaks also exits 1 on a fatal error, so a finding needs a readable report with findings in it.
if [ "$GRC" -eq 1 ] && FINDINGS=$(python3 -I - "$TMP/report.json" "$TMP/scan" "$TOP" <<'PY'
import json, os, sys

report, root, top = sys.argv[1], os.path.realpath(sys.argv[2]), sys.argv[3]
with open(report) as f:
    data = json.load(f)
if not isinstance(data, list) or not data:
    sys.exit(1)
for item in data:
    path = os.path.realpath(os.path.join(root, item.get("File", "")))
    rel = os.path.relpath(path, root)
    kind, _, rel = rel.partition(os.sep)
    where = rel + (" (staged blob)" if kind == "staged" else "")
    print("ERROR: memory-gitleaks-check: %s: %s:%s — rule %s"
          % (top, where, item.get("StartLine", "?"), item.get("RuleID", "?")))
PY
); then
    printf '%s\n' "$FINDINGS" >&2
    finish 1
fi

printf '%s: gitleaks failed (rc=%s)\n' "$TAG" "$GRC" >&2
sed 's/^/  gitleaks: /' "$TMP/gitleaks.err" >&2
finish 2
