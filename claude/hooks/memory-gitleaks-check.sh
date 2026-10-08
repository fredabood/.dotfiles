#!/usr/bin/env bash
# memory-gitleaks-check.sh — PreToolUse: scan what a memory-vault commit will contain with gitleaks,
# and block the commit on a finding (LAB-2457).
#
# WHY: LAB-2288 redacted 12 credentials, four of them live, that had sat in vault notes for about
# six months. The vault is not an ordinary private repo: sync-memory-vault.py chunks every note into
# public.memories every 15 minutes and memory_search serves it, so a credential committed to a note
# is readable by every agent that queries memory within a quarter of an hour. The periodic history
# scan finds these after the fact; this gate stops the next one at commit time.
#
# HOW: the repo and the file set are resolved exactly as memory-frontmatter-check.sh resolves them
# (the resolver below is a COPY of that hook's, per the LAB-2457 owner ruling; extracting a shared
# lib is a follow-up). The repo comes from the command (git -C, a leading cd, else the payload cwd);
# vault identity is the git common dir, equal for the primary checkout and every worktree; the file
# set is the index plus every earlier `git add` in the same command, `commit -a`, `-i` and
# pathspecs. Two deliberate differences from the copy: every file counts, not only .md, and renames
# are listed as additions (--no-renames), so a renamed-and-edited file is not dropped.
# The scan itself is claude/scripts/memory-gitleaks-scan.sh (0 = clean, 1 = finding, 2 = invalid
# run). Claude Code blocks a PreToolUse call only on exit 2, so this hook maps 1 AND 2 to 2.
#
# CONFIG: HEAD's committed .gitleaks.toml, written to a temp file and passed with -c. A commit
# therefore cannot allowlist itself: an allowlist entry has to land in an earlier commit.
#
# EXIT CODES: 0 = allow (not a commit, not the vault, clean, a zero-content commit, or a visible
# skip); 2 = block (a finding, gitleaks or the committed config missing, or gitleaks failed).
#
# KILL SWITCH (human only): MEMORY_GITLEAKS_CHECK=off disables the gate and prints a DISABLED line
# on stderr for every commit it waves through.
#
# LIMITS:
#   - gitleaks is a keyword-and-entropy check, not a proof. Its default stopword allowlist can
#     suppress a real credential; every run says so.
#   - Only commits made through Claude Code's Bash tool are seen here (owner ruling D5). Commits
#     and pushes made elsewhere (a terminal, Obsidian, claude-settings-sync.sh) are gated by the
#     vault's own git hooks, claude/scripts/memory-gitleaks-commit-check.sh (LAB-2857); vault-sync's
#     planned auto-commit is to call that script explicitly (fredabood/homelab#2548).
#   - Interactive or file-driven adds and commits, and pathspecs using $, backticks or braces, are
#     a visible "skipped" line, as in the frontmatter hook.
#
# If you change this file, prove it with claude/tests/memory-gitleaks-check.test.sh AND the live
# probe in fredabood/homelab#2457 (a runtime-generated token staged in a throwaway vault worktree
# must be BLOCKED) — never by observing that the hook ran without error.

set -euo pipefail

TAG="memory-gitleaks-check"
INPUT=$(cat)
if [[ "${MEMORY_GITLEAKS_CHECK:-}" == off ]]; then
  if [[ "$INPUT" == *commit* ]]; then
    echo "$TAG: DISABLED by MEMORY_GITLEAKS_CHECK=off — no secret scan ran for this commit." >&2
  fi
  exit 0
fi
if [[ "$INPUT" != *git* || "$INPUT" != *commit* ]]; then
  exit 0
fi

skip() {
  echo "$TAG: skipped — $1" >&2
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCAN="${MEMORY_GITLEAKS_CHECK_UNDER_TEST:-$HERE/../scripts/memory-gitleaks-scan.sh}"

# --- copied from memory-frontmatter-check.sh (resolve_targets), unchanged ---
resolve_targets() {
  HOOK_PAYLOAD="$INPUT" python3 - <<'PY'
import json, os, re, shlex, sys

class Unknown:
    def __init__(self, reason):
        self.reason = reason

def emit(kind, value, extra=None):
    line = kind + "\t" + value.replace("\n", " ").replace("\t", " ")
    if extra is not None:
        line += "\t" + extra
    if line not in seen:
        seen.append(line)
        print(line)

seen = []
adds = []  # every `git add` seen so far in the command, in order
try:
    payload = json.loads(os.environ.get("HOOK_PAYLOAD") or "")
except ValueError:
    emit("SKIP", "hook payload is not JSON")
    sys.exit(0)
if not isinstance(payload, dict):
    sys.exit(0)
cmd = (payload.get("tool_input") or {}).get("command") or ""
if not isinstance(cmd, str) or "git" not in cmd or "commit" not in cmd:
    sys.exit(0)
cwd = payload.get("cwd") or ""
start = cwd if isinstance(cwd, str) and os.path.isabs(cwd) else Unknown("no cwd in the hook payload")

lexer = shlex.shlex(cmd, posix=True, punctuation_chars="();<>|&\n")
lexer.whitespace = " \t\r"
lexer.whitespace_split = True
try:
    tokens = list(lexer)
except ValueError as e:
    emit("SKIP", "could not parse the command (%s)" % e)
    sys.exit(0)

PUNCT = set("();<>|&\n")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Words that may precede a command in the same segment: wrappers and shell reserved words.
PREFIXES = {"command", "exec", "env", "time", "nohup", "builtin", "sudo",
            "if", "then", "elif", "else", "do", "while", "until", "!", "{"}

def resolve(base, path):
    if any(c in path for c in "$`*?["):
        return Unknown("path uses shell expansion: " + path)
    path = os.path.expanduser(path)
    if os.path.isabs(path):
        return os.path.normpath(path)
    if isinstance(base, Unknown):
        return base
    return os.path.normpath(os.path.join(base, path))

def segment(words, cur):
    """Returns the working directory after this segment; emits any commit it contains."""
    i = 0
    while i < len(words) and (ASSIGN.match(words[i]) or words[i] in PREFIXES):
        i += 1
    if i < len(words) and words[i] in ("cd", "pushd"):
        args = [a for a in words[i + 1:] if a not in ("-L", "-P", "--")]
        if not args:
            return os.path.expanduser("~")
        if args[0] == "-":
            return Unknown("cd - (previous directory is not known)")
        return resolve(cur, args[0])
    # The FIRST `git` word anywhere in the segment, not only in command position: a wrapper
    # this list does not know (sudo -u x, xargs, env -u VAR) must not turn into a silent pass.
    # Over-matching `echo git commit` can at worst block a vault commit that has bad notes.
    k = next((n for n, w in enumerate(words) if os.path.basename(w) == "git"), None)
    if k is None:
        return cur
    git_dir_env = any(w.startswith(("GIT_DIR=", "GIT_WORK_TREE=")) for w in words[:k])
    args = words[k + 1:]
    target, j = cur, 0
    while j < len(args):
        a = args[j]
        if a == "-C":
            target = resolve(target, args[j + 1]) if j + 1 < len(args) else Unknown("git -C with no path")
            j += 2
        elif a == "-c":
            j += 2
        elif a.startswith(("--git-dir", "--work-tree")):
            git_dir_env = True
            j += 1
        elif a.startswith("-"):
            j += 1
        else:
            break
    sub, rest = (args[j], args[j + 1:]) if j < len(args) else (None, [])
    if sub in ("add", "stage"):
        add = parse_add(rest)
        if add is not None:
            if git_dir_env:
                add["skip"] = "git add with an explicit --git-dir/--work-tree/GIT_DIR"
            elif isinstance(target, Unknown):
                add["skip"] = "git add in an unresolvable directory (%s)" % target.reason
            else:
                add["dir"] = target
            adds.append(add)
    # `git rm` stages no content, and `git mv` moves an index entry without staging worktree
    # edits, so neither adds a file the commit could get wrong. They are deliberately not counted.
    elif sub == "commit":
        if git_dir_env:
            emit("SKIP", "git commit with an explicit --git-dir/--work-tree/GIT_DIR")
        elif isinstance(target, Unknown):
            emit("SKIP", target.reason)
        else:
            spec = parse_commit(rest)
            spec["adds"] = list(adds)
            emit("DIR", target, json.dumps(spec))
    return cur

def expands(spec):
    return any(c in spec for c in "$`{\n")

def parse_add(rest):
    """The file set a `git add` stages, or None when it stages no content."""
    add = {"all": False, "update": False, "force": False, "specs": []}
    after = False
    for a in rest:
        if after or not a.startswith("-") or a == "-":
            add["specs"].append(a)
        elif a == "--":
            after = True
        elif a.startswith("--"):
            name = a[2:].split("=", 1)[0]
            if name in ("dry-run", "intent-to-add"):
                return None
            if name in ("all", "no-ignore-removal"):
                add["all"] = True
            elif name == "update":
                add["update"] = True
            elif name == "force":
                add["force"] = True
            elif name in ("patch", "interactive", "edit", "pathspec-from-file"):
                add["skip"] = "interactive or file-driven git add (--%s)" % name
        else:
            for ch in a[1:]:
                if ch in "nN":
                    return None
                if ch == "A":
                    add["all"] = True
                elif ch == "u":
                    add["update"] = True
                elif ch == "f":
                    add["force"] = True
                elif ch in "pie":
                    add["skip"] = "interactive git add (-%s)" % ch
    if any(expands(s) for s in add["specs"]):
        add["skip"] = "git add pathspec uses shell expansion"
    return add

# Options whose value is the next word unless attached; the value is never a pathspec.
COMMIT_SHORT_VALUE = set("mFCct")
COMMIT_LONG_VALUE = {"message", "file", "reuse-message", "reedit-message", "author", "date",
                     "template", "fixup", "squash", "cleanup", "trailer"}

def parse_commit(rest):
    spec = {"all": False, "include": False, "specs": [], "skips": []}
    k, after = 0, False
    while k < len(rest):
        a = rest[k]
        k += 1
        if after or not a.startswith("-") or a == "-":
            spec["specs"].append(a)
        elif a == "--":
            after = True
        elif a.startswith("--"):
            name, eq, _ = a[2:].partition("=")
            if name == "all":
                spec["all"] = True
            elif name == "include":
                spec["include"] = True
            elif name in ("patch", "interactive", "pathspec-from-file"):
                spec["skips"].append("interactive or file-driven git commit (--%s)" % name)
            elif name in COMMIT_LONG_VALUE and not eq:
                k += 1
        else:
            for n, ch in enumerate(a[1:]):
                if ch == "a":
                    spec["all"] = True
                elif ch == "i":
                    spec["include"] = True
                elif ch == "p":
                    spec["skips"].append("interactive git commit (-p)")
                elif ch in COMMIT_SHORT_VALUE:
                    if n + 2 == len(a):
                        k += 1
                    break
                elif ch in "Su":
                    break
    if any(expands(s) for s in spec["specs"]):
        spec["skips"].append("git commit pathspec uses shell expansion")
        spec["specs"] = []
    return spec

cur, stack, words, redirect = start, [], [], False
for tok in tokens:
    if tok and all(c in PUNCT for c in tok):
        if "<" in tok or ">" in tok:
            redirect = True
            continue
        cur = segment(words, cur)
        words = []
        for c in tok:
            if c == "(":
                stack.append(cur)
            elif c == ")" and stack:
                cur = stack.pop()
        continue
    if redirect:
        redirect = False
        continue
    words.append(tok)
segment(words, cur)

# A commit inside one quoted token (bash -c "...", eval "...") is not inspected. Say so.
if not seen and any(" " in t and re.search(r"\bgit\b.*\bcommit\b", t) for t in tokens):
    emit("SKIP", "a git commit inside a quoted string (bash -c, eval) was not inspected")
PY
}

TARGETS=$(resolve_targets) || {
  skip "could not resolve the commit's repository (python3 failed)"
  exit 0
}
if [[ -z "$TARGETS" ]]; then
  exit 0
fi
# --- end of the copied resolve_targets ---

# The git common dir is the same for a checkout and every one of its worktrees, and differs
# for everything else. --show-toplevel would not do: it differs per worktree.
common_dir() {
  local d
  d=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (cd "$d" 2>/dev/null && pwd -P)
}

MEMORY_DIR="${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}"
VAULT_COMMON=""

# --- copied from memory-frontmatter-check.sh (commit_files): every file, not only .md; --no-renames ---
# commit_files <top> <commit dir> <json>: the files the commit will contain, as
# "FILE<TAB><top-relative path>" or "SKIP<TAB><reason>" lines. Git runs with list argv, never a
# shell, and pathspecs go after `--`. memory-gitleaks-scan.sh reads the working-tree content (what
# git will stage for every source below) and, where it differs, the staged blob too.
commit_files() {
  CF_TOP="$1" CF_DIR="$2" CF_SPEC="$3" python3 - <<'PY'
import json, os, subprocess

top, cdir = os.environ["CF_TOP"], os.environ["CF_DIR"]
seen = []

def say(kind, value):
    line = kind + "\t" + value
    if line not in seen:
        seen.append(line)
        print(line)

def git(d, *args):
    r = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", d] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if r.returncode != 0:
        return None
    return r.stdout.decode("utf-8", "surrogateescape")

def names(d, *args):
    out = git(d, *args)
    return None if out is None else [p for p in out.split("\0") if p]

def files(paths, reason):
    if paths is None:
        say("SKIP", reason)
        return
    for p in paths:
        if "\n" in p or "\t" in p:
            say("SKIP", "a staged file name contains a newline or tab")
        else:
            say("FILE", p)

def toplevel(d):
    out = git(d, "rev-parse", "--show-toplevel")
    return os.path.realpath(out.strip()) if out else None

CHANGED = ("diff", "--name-only", "-z", "--no-relative", "--no-renames", "--diff-filter=ACMT")
try:
    spec = json.loads(os.environ["CF_SPEC"] or "{}")
except ValueError:
    spec = {"skips": ["could not read the parsed commit"]}
for reason in spec.get("skips", []):
    say("SKIP", reason)

specs = spec.get("specs") or []
index = lambda: files(names(top, "diff", "--cached", *CHANGED[1:]), "could not read the index")
if spec.get("all"):
    index()
    files(names(top, *CHANGED), "could not list modified tracked files for commit -a")
elif specs and spec.get("include"):
    index()
    files(names(cdir, *CHANGED + ("--",) + tuple(specs)), "could not list the commit -i paths")
elif specs:
    # `git commit <paths>` commits only those paths from the working tree; the rest of the index waits.
    files(names(cdir, "diff", "HEAD", *CHANGED[1:] + ("--",) + tuple(specs)),
          "could not diff the commit pathspec against HEAD")
else:
    index()

real_top = os.path.realpath(top)
for add in spec.get("adds", []):
    if "skip" in add:
        say("SKIP", add["skip"])
        continue
    if toplevel(add["dir"]) != real_top:
        continue
    paths = add["specs"] or ([":/"] if add["all"] or add["update"] else [])
    if not paths:
        continue
    files(names(add["dir"], *CHANGED + ("--",) + tuple(paths)), "could not list the git add paths")
    if not add["update"] or add["all"]:
        others = ("ls-files", "-z", "--full-name", "--others")
        if not add["force"]:
            others += ("--exclude-standard",)
        files(names(add["dir"], *others + ("--",) + tuple(paths)), "could not list untracked git add paths")
PY
}

VAULT_TOPS=()
VAULT_DIRS=()
VAULT_SPECS=()
while IFS=$'\t' read -r kind value spec; do
  if [[ "$kind" == SKIP ]]; then
    skip "$value"
    continue
  fi
  if ! TOP=$(git -C "$value" rev-parse --show-toplevel 2>/dev/null) || [[ -z "$TOP" ]]; then
    skip "$value is not in a git work tree"
    continue
  fi
  if [[ -z "$VAULT_COMMON" ]] && ! VAULT_COMMON=$(common_dir "$MEMORY_DIR"); then
    VAULT_COMMON=""
    skip "the vault at $MEMORY_DIR is not a git repository, so nothing could be matched against it"
    exit 0
  fi
  if [[ "$(common_dir "$TOP" || true)" == "$VAULT_COMMON" ]]; then
    VAULT_TOPS+=("$TOP")
    VAULT_DIRS+=("$value")
    VAULT_SPECS+=("$spec")
  fi
done <<<"$TARGETS"

if [[ ${#VAULT_TOPS[@]} -eq 0 ]]; then
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/memory-gitleaks-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Every line goes to stderr: on exit 2 Claude Code hands the model stderr only (LAB-1996).
BLOCK=0
for i in "${!VAULT_TOPS[@]}"; do
  TOP="${VAULT_TOPS[$i]}"

  if ! FILE_LINES=$(commit_files "$TOP" "${VAULT_DIRS[$i]}" "${VAULT_SPECS[$i]}"); then
    skip "could not compute the files this commit will contain (python3 failed)"
    continue
  fi
  LIST="$WORK/list.$i"
  : >"$LIST"
  COUNT=0
  SKIPPED=0
  while IFS=$'\t' read -r kind value; do
    if [[ "$kind" == SKIP ]]; then
      skip "$value"
      SKIPPED=1
    elif [[ "$kind" == FILE ]]; then
      printf '%s\0' "$value" >>"$LIST"
      COUNT=$((COUNT + 1))
    fi
  done <<<"$FILE_LINES"

  if [[ $COUNT -eq 0 ]]; then
    if [[ $SKIPPED -eq 1 ]]; then
      echo "$TAG: $TOP: 0 staged path(s) examined — the skipped part above was not scanned" >&2
      continue
    fi
    # The owner ruling (D2) asked first for another way to judge such a commit. There is none
    # that reaches the surface this gate protects: vault-sync feeds note CONTENT to
    # public.memories, and a message-only amend, an --allow-empty commit or a deletion-only commit
    # adds no content; an amend with nothing staged keeps HEAD's tree, which was scanned when it
    # was committed. The commit message never reaches public.memories.
    # ZERO-INPUT-OK: such a commit stages no content that could hold a secret (message-only amend, --allow-empty, deletion-only)
    echo "$TAG: $TOP: 0 staged path(s) examined — ZERO-INPUT-OK: such a commit stages no content that could hold a secret (message-only amend, --allow-empty, deletion-only)" >&2
    continue
  fi

  CONFIG="$WORK/gitleaks.$i.toml"
  if ! git -C "$TOP" show HEAD:.gitleaks.toml >"$CONFIG" 2>/dev/null; then
    echo "$TAG: $TOP: no .gitleaks.toml committed at HEAD — refusing to scan on gitleaks defaults" >&2
    BLOCK=1
    continue
  fi

  RC=0
  bash "$SCAN" "$TOP" "$CONFIG" "$LIST" || RC=$?
  if [[ $RC -ne 0 ]]; then
    BLOCK=1
    if [[ $RC -ne 1 ]]; then
      echo "$TAG: $TOP: invalid scan run (exit $RC) — blocking rather than passing unchecked" >&2
    fi
  fi
done

if [[ $BLOCK -eq 1 ]]; then
  echo "Vault secret scan blocked this commit. Remove the value (store it in 1Password and reference it), or, if it is a false positive, add a one-line allowlist with a reason to .gitleaks.toml." >&2
  exit 2
fi
exit 0
