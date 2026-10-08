#!/usr/bin/env bash
# memory-gitleaks-commit-check.sh — the vault secret scan for commits and pushes made OUTSIDE Claude
# Code (LAB-2857): a terminal, Obsidian desktop, claude-settings-sync.sh, or any vault worktree.
# The vault's git hooks call it; install-vault-hooks.sh installs them. vault-sync's planned
# auto-commit (fredabood/homelab#2548) is to call it explicitly, since a hook cannot run in its container.
#
#   memory-gitleaks-commit-check.sh [--pre-commit] <toplevel>
#   memory-gitleaks-commit-check.sh --pre-push <toplevel> <remote>     (git's pre-push lines on stdin)
#
# --pre-commit (the default) scans what the commit will contain: the paths staged in the index git
# hands the hook (GIT_INDEX_FILE, so `commit -a` and `commit -- <path>` are covered), through
# memory-gitleaks-scan.sh, with HEAD's committed .gitleaks.toml (LAB-2457 ruling D4: a commit cannot
# allowlist itself).
#
# --pre-push scans every OBJECT the push sends that the remote does not hold (per `git ls-remote`):
# each new blob, whatever commit introduced it, plus every commit message and tag message. So it
# covers what a pre-commit hook never sees: commit --no-verify, rebase, cherry-pick, am, revert,
# merges (including a merge's own resolution), binary-looking files, tags, and a branch that was
# purged from the remote and pushed again. Its config is the REMOTE's committed .gitleaks.toml (its
# HEAD, else refs/heads/main), so a pushed commit cannot allowlist itself: push an allowlist change on
# its own first. Only an empty remote falls back to local HEAD, and says so. A remote HEAD that is not
# in this clone is refused with "fetch first". `git push --no-verify` skips this hook.
#
# Exit codes (testing.md → Vacuous checks):
#   0  clean, a commit or push that carries no content (ZERO-INPUT-OK, printed), or the kill switch
#   1  a finding
#   2  invalid run: gitleaks or the config missing, a bad argument, or gitleaks failed
# The hooks refuse on any non-zero exit. Every line goes to stderr, tagged memory-gitleaks-check, and
# a finding prints only file, line and rule id (gitleaks --redact), never the value.
#
# PATH: GUI apps (Obsidian) and launchd jobs run without Homebrew on PATH, so
# ${MEMORY_GITLEAKS_PATH_PREPEND-/opt/homebrew/bin:/usr/local/bin} is prepended. A host that really has
# no gitleaks is still refused, never waved through.
#
# KILL SWITCH (human only): MEMORY_GITLEAKS_CHECK=off in the environment of the git command disables
# both modes and prints a DISABLED line. In Claude Code the PreToolUse gate reads the hook's own
# environment instead, so the two switches are separate.
#
# Prove changes with claude/tests/memory-gitleaks-git-hook.test.sh, never by observing a clean run.
set -uo pipefail

TAG="memory-gitleaks-check"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCAN="${MEMORY_GITLEAKS_SCAN_UNDER_TEST:-$HERE/memory-gitleaks-scan.sh}"
DISCLAIMER="keyword-and-entropy check, not a proof — gitleaks' default stopwords can suppress a real credential"

MODE=pre-commit
case "${1:-}" in
    --pre-commit) shift ;;
    --pre-push) MODE=pre-push; shift ;;
    -*) printf '%s: unknown option %s\n' "$TAG" "$1" >&2; exit 2 ;;
esac
if { [ "$MODE" = pre-commit ] && [ $# -ne 1 ]; } || { [ "$MODE" = pre-push ] && [ $# -ne 2 ]; }; then
    printf '%s: usage: memory-gitleaks-commit-check.sh [--pre-commit] <toplevel> | --pre-push <toplevel> <remote>\n' "$TAG" >&2
    exit 2
fi
TOP="$1"
WHAT=commit; [ "$MODE" = pre-push ] && WHAT=push

if [ "${MEMORY_GITLEAKS_CHECK:-}" = off ]; then
    printf '%s: DISABLED by MEMORY_GITLEAKS_CHECK=off — no secret scan ran for this %s.\n' "$TAG" "$WHAT" >&2
    exit 0
fi

PREPEND="${MEMORY_GITLEAKS_PATH_PREPEND-/opt/homebrew/bin:/usr/local/bin}"
[ -n "$PREPEND" ] && PATH="$PREPEND:$PATH"
export PATH

if ! git -C "$TOP" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s: %s is not a git work tree — nothing was scanned\n' "$TAG" "$TOP" >&2
    exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/memory-gitleaks-commit.XXXXXX")" || {
    printf '%s: could not create a temp dir — nothing was scanned\n' "$TAG" >&2
    exit 2
}
trap 'rm -rf "$WORK"' EXIT

remedy() {
    printf 'Vault secret scan refused this %s. Remove the value (store it in 1Password and reference it), or, if it is a false positive, add a one-line allowlist with a reason to .gitleaks.toml and commit and push that on its own first.\n' "$WHAT" >&2
}

# ---------------------------------------------------------------- pre-commit
if [ "$MODE" = pre-commit ]; then
    LIST="$WORK/list"
    # GIT_INDEX_FILE is inherited: during `commit -a` or `commit -- <path>` git points it at the
    # temporary index that the commit will actually be made from.
    if ! git -c core.fsmonitor=false -C "$TOP" diff --cached --name-only -z --no-renames \
            --diff-filter=ACMT >"$LIST" 2>"$WORK/diff.err"; then
        printf '%s: %s: could not list the staged paths — nothing was scanned\n' "$TAG" "$TOP" >&2
        sed 's/^/  git: /' "$WORK/diff.err" >&2
        remedy; exit 2
    fi
    if [ ! -s "$LIST" ]; then
        # ZERO-INPUT-OK: such a commit stages no file content (message-only amend, --allow-empty, deletion-only); its message is scanned at push
        printf '%s: %s: 0 staged path(s) examined — ZERO-INPUT-OK: such a commit stages no file content (message-only amend, --allow-empty, deletion-only); its message is scanned at push\n' "$TAG" "$TOP" >&2
        printf '%s: %s\n' "$TAG" "$DISCLAIMER" >&2
        exit 0
    fi
    CONFIG="$WORK/gitleaks.toml"
    if ! git -C "$TOP" show HEAD:.gitleaks.toml >"$CONFIG" 2>/dev/null; then
        printf '%s: %s: no .gitleaks.toml committed at HEAD — refusing to scan on gitleaks defaults\n' "$TAG" "$TOP" >&2
        remedy; exit 2
    fi
    RC=0
    bash "$SCAN" "$TOP" "$CONFIG" "$LIST" || RC=$?
    if [ "$RC" -ne 0 ]; then
        [ "$RC" -ne 1 ] && printf '%s: %s: invalid scan run (exit %s) — refusing rather than passing unchecked\n' "$TAG" "$TOP" "$RC" >&2
        remedy
    fi
    exit "$RC"
fi

# ---------------------------------------------------------------- pre-push
# Object-level, not patch-level: `gitleaks git` reads `git log -p`, which prints no content for a
# binary file (a NUL byte, or -diff in .gitattributes) and no patch for a merge, and never sees a tag.
# So list every object the push sends that the remote does not already have (rev-list --objects,
# excluding what `git ls-remote` says the remote holds now, not possibly stale tracking refs),
# write out each new blob, each commit message and each tag message, and run `gitleaks dir` on them.
REMOTE="$2"
cat >"$WORK/stdin"
if ! command -v gitleaks >/dev/null 2>&1; then
    printf '%s: gitleaks not installed (brew install gitleaks) — nothing was scanned\n' "$TAG" >&2
    remedy; exit 2
fi
mkdir -p "$WORK/scan"
# prepare: prints "<objects> <commits> <blobs> <tags> <config-source>" on stdout; on an invalid run it
# prints the reason on stderr and exits 2.
if ! PREP=$(python3 -I - "$TOP" "$REMOTE" "$WORK" <<'PY'
import os, subprocess, sys

top, remote, work = sys.argv[1], sys.argv[2], sys.argv[3]
TAG = "memory-gitleaks-check"
ZERO = "0" * 40

def git(*args, inp=None):
    r = subprocess.run(["git", "-C", top] + list(args), input=inp,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return r.returncode, r.stdout

def have(sha):
    return git("cat-file", "-e", sha)[0] == 0

def die(msg):
    print("%s: %s: %s" % (TAG, top, msg), file=sys.stderr)
    sys.exit(2)

# What the remote holds NOW. Network failure means the push would fail anyway; refuse.
rc, out = git("ls-remote", remote)
if rc != 0:
    die("could not list %s's refs (git ls-remote) — nothing was scanned" % remote)
remote_refs = {}
for line in out.decode().splitlines():
    sha, _, ref = line.partition("\t")
    remote_refs[ref] = sha

# Config: the remote's own committed .gitleaks.toml (HEAD, else refs/heads/main), so a pushed commit
# cannot allowlist itself. An empty remote (first push) falls back to local HEAD and says so.
cfg_sha = remote_refs.get("HEAD") or remote_refs.get("refs/heads/main")
cfg_from = None
if cfg_sha:
    if not have(cfg_sha):
        die("%s's HEAD %s is not in this clone — fetch %s first, then push" % (remote, cfg_sha[:10], remote))
    rc, cfg = git("show", cfg_sha + ":.gitleaks.toml")
    if rc != 0:
        die("no .gitleaks.toml on %s's HEAD — refusing to scan on gitleaks defaults" % remote)
    cfg_from = "%s HEAD %s" % (remote, cfg_sha[:10])
else:
    rc, cfg = git("show", "HEAD:.gitleaks.toml")
    if rc != 0:
        die("no .gitleaks.toml on %s or at HEAD — refusing to scan on gitleaks defaults" % remote)
    cfg_from = "local HEAD (%s has no refs yet)" % remote
    print("%s: %s: %s is empty — using local HEAD's .gitleaks.toml" % (TAG, top, remote), file=sys.stderr)
with open(os.path.join(work, "gitleaks.toml"), "wb") as f:
    f.write(cfg)

positives, exclude = [], set(s for s in remote_refs.values() if have(s))
with open(os.path.join(work, "stdin")) as f:
    for line in f:
        parts = line.split()
        if len(parts) != 4:
            continue
        _lref, lsha, _rref, rsha = parts
        if lsha == ZERO:
            continue                      # a delete sends no content
        positives.append(lsha)
        if rsha != ZERO and have(rsha):
            exclude.add(rsha)

objs = {}                                 # oid -> path (or "")
if positives:
    args = ["rev-list", "--objects"] + positives + ["--not"] + sorted(exclude)
    rc, out = git(*args)
    if rc != 0:
        die("could not list the objects this push sends (git rev-list) — nothing was scanned")
    for line in out.decode("utf-8", "surrogateescape").splitlines():
        oid, _, path = line.partition(" ")
        objs.setdefault(oid, path)
    # Make sure a pushed annotated tag object itself (its message) is in the set.
    for p in positives:
        if p not in exclude and git("cat-file", "-t", p)[1].strip() == b"tag":
            objs.setdefault(p, "")

types = {}
if objs:
    rc, out = git("cat-file", "--batch-check=%(objectname) %(objecttype)",
                  inp=("\n".join(objs) + "\n").encode())
    if rc != 0:
        die("could not read the pushed objects (git cat-file) — nothing was scanned")
    for line in out.decode().splitlines():
        oid, _, kind = line.partition(" ")
        types[oid] = kind

def safe(rel):
    return rel and not os.path.isabs(rel) and ".." not in rel.split("/")

manifest, counts = [], {"commit": 0, "blob": 0, "tag": 0}
for oid, path in objs.items():
    kind = types.get(oid)
    if kind == "blob":
        rel = os.path.join("blob", oid, path if safe(path) else oid)
        label = "%s (pushed blob %s)" % (path or oid[:10], oid[:10])
        rc, data = git("cat-file", "blob", oid)
    elif kind in ("commit", "tag"):
        rel = os.path.join(kind, oid + ".txt")
        label = "%s message %s" % (kind, oid[:10])
        rc, data = git("cat-file", kind, oid)
    else:
        continue                          # trees carry names only, already in the blob paths
    if rc != 0:
        die("could not read pushed %s %s — nothing was scanned" % (kind, oid[:10]))
    dest = os.path.join(work, "scan", rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as f:
        f.write(data)
    manifest.append("%s\t%s\t%s" % (rel, oid, label))
    counts[kind] += 1
with open(os.path.join(work, "manifest"), "w") as f:
    f.write("\n".join(manifest) + "\n")
print(sum(counts.values()), counts["commit"], counts["blob"], counts["tag"], cfg_from)
PY
); then
    remedy; exit 2
fi
read -r NOBJ NCOMMIT NBLOB NTAG CFG_FROM <<EOF
$PREP
EOF

count_line() {
    printf '%s: %s: %s pushed object(s) examined (%s commit(s), %s blob(s), %s tag(s); config: %s)\n' \
        "$TAG" "$TOP" "$NOBJ" "$NCOMMIT" "$NBLOB" "$NTAG" "$CFG_FROM" >&2
    printf '%s: %s\n' "$TAG" "$DISCLAIMER" >&2
}

if [ "$NOBJ" -eq 0 ]; then
    # ZERO-INPUT-OK: the push sends no object the remote lacks (a branch delete, or refs it already has)
    printf '%s: %s: 0 pushed object(s) examined — ZERO-INPUT-OK: the push sends no object the remote lacks (a branch delete, or refs it already has)\n' "$TAG" "$TOP" >&2
    printf '%s: %s\n' "$TAG" "$DISCLAIMER" >&2
    exit 0
fi

gitleaks dir "$WORK/scan" -c "$WORK/gitleaks.toml" --redact --no-banner --log-level warn \
    --report-format json --report-path "$WORK/report.json" --exit-code 1 >/dev/null 2>"$WORK/gitleaks.err"
GRC=$?
if [ "$GRC" -eq 0 ]; then
    count_line; exit 0
fi
# gitleaks also exits 1 on a fatal error, so a finding needs a readable report with findings in it.
if [ "$GRC" -eq 1 ] && FINDINGS=$(python3 -I - "$WORK" "$TOP" 2>"$WORK/parse.err" <<'PY'
import json, os, subprocess, sys
work, top = sys.argv[1], sys.argv[2]
root = os.path.realpath(os.path.join(work, "scan"))
with open(os.path.join(work, "report.json")) as f:
    data = json.load(f)
if not isinstance(data, list) or not data:
    sys.exit(1)
labels = {}
with open(os.path.join(work, "manifest")) as f:
    for line in f:
        if line.strip():
            rel, oid, label = line.rstrip("\n").split("\t", 2)
            labels[rel] = label
for item in data:
    rel = os.path.relpath(os.path.realpath(os.path.join(root, item.get("File", ""))), root)
    print("ERROR: memory-gitleaks-check: %s: %s:%s — rule %s"
          % (top, labels.get(rel, rel), item.get("StartLine", "?"), item.get("RuleID", "?")))
PY
); then
    printf '%s\n' "$FINDINGS" >&2
    count_line; remedy; exit 1
fi
printf '%s: gitleaks failed (rc=%s) — the pushed objects were NOT scanned\n' "$TAG" "$GRC" >&2
sed 's/^/  gitleaks: /' "$WORK/gitleaks.err" >&2
remedy; exit 2
