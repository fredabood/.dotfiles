#!/usr/bin/env bash
# Pre-commit: validates frontmatter on memory vault .md files.
# Exit 0 = allow, Exit 2 = block.
#
# This hook is triggered by settings.json PreToolUse on every Bash call. It acts only on a
# `git commit` whose repo is the memory vault: its primary checkout or any worktree of it.

set -euo pipefail

# Modern hook payload arrives as JSON on stdin (legacy TOOL_INPUT env was always
# empty, making this gate a silent no-op — LAB-215, 2026-07-13).
INPUT=$(cat)
if [[ "$INPUT" != *git* || "$INPUT" != *commit* ]]; then
  exit 0
fi

# This gate has silently died FOUR times. First LAB-215 (2026-07-13): the legacy TOOL_INPUT
# env was always empty. Then the 2026-09-10 de-monorepo: the path read was
# "${CLAUDE_PROJECT_DIR:-.}/submodules/memory", and the vault stopped being a submodule of
# anything — so the -d test missed under EVERY project root and the hook exited 0 on every
# commit, validating nothing. Then vault worktrees (LAB-1996, 2026-09-12): the hook `cd`-ed to
# $MEMORY_VAULT_PATH and read the PRIMARY checkout's index, but a worktree has its own index —
# so every commit from a worktree, now the normal path, validated nothing, and a worktree
# commit could be blocked by files another session had staged in the primary. The same fix
# found a fifth hole: the prefilter matched the literal text "git commit", so
# `git -C <path> commit` never reached the check at all.
#
# The failure mode is the same each time and is what makes it recur: a gate whose skip path
# and success path are both "exit 0, print nothing". So the repo is now taken from the
# COMMAND (git -C, a leading cd, else the payload cwd), identity is the git common dir (equal
# for a checkout and all its worktrees), and every "could not tell" path prints one line to
# stderr. Exiting 0 silently is reserved for "not a commit" and "not the vault".
#
# The command text is parsed with shlex, never evaluated: a path containing $, a backtick or a
# glob is reported as unresolvable rather than expanded.
#
# Then add-then-commit (LAB-2062, 2026-09-13): PreToolUse runs BEFORE the command, so in
# `git add x && git commit` the index was read before the add. With nothing staged beforehand the
# hook exited 0 silently, and `git add … && git commit` is the most common way agents commit. So
# the file set is now computed from the command: the index, plus every earlier `git add` in the
# same command that targets the same repo, plus `commit -a`, `commit -i <paths>` and
# `commit <paths>` (which commits only those paths). Content is read from the working tree.
#
# Remaining limits, each a visible skip rather than a silent pass: interactive or file-driven
# adds and commits (-p, -i, -e, --pathspec-from-file), and pathspecs using $, backticks or braces.
# A partially staged file is validated from the working tree, not the staged blob. `git rm` and
# `git mv` stage no new content and are not counted.
#
# If you change this file, prove it with claude/tests/memory-frontmatter-check.test.sh AND by
# staging a frontmatter-less .md in a real vault worktree and watching the commit get BLOCKED —
# never by observing that the hook ran without error.

skip() {
  echo "memory-frontmatter-check: skipped — $1" >&2
}

# Prints one line per `git commit` found: "DIR<TAB><abs path><TAB><json>" or "SKIP<TAB><reason>".
# The json says what else the commit will pick up: -a, -i, pathspecs, and every earlier `git add`
# in the same command (LAB-2062).
# A function rather than a heredoc inside $( ): bash 3.2 mis-parses the latter.
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

# The git common dir is the same for a checkout and every one of its worktrees, and differs
# for everything else. --show-toplevel would not do: it differs per worktree.
common_dir() {
  local d
  d=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (cd "$d" 2>/dev/null && pwd -P)
}

MEMORY_DIR="${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}"
VAULT_COMMON=""

# commit_files <top> <commit dir> <json>: the .md files the commit will contain, as
# "FILE<TAB><top-relative path>" or "SKIP<TAB><reason>" lines. Git runs with list argv, never a
# shell, and pathspecs go after `--`. Content is read from the working tree afterwards: for every
# source below, that is the content git will stage.
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
        if not p.endswith(".md"):
            continue
        if "\n" in p or "\t" in p:
            say("SKIP", "a staged .md name contains a newline or tab")
        else:
            say("FILE", p)

def toplevel(d):
    out = git(d, "rev-parse", "--show-toplevel")
    return os.path.realpath(out.strip()) if out else None

CHANGED = ("diff", "--name-only", "-z", "--no-relative", "--diff-filter=ACM")
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

# Every line of a BLOCK goes to stderr. On exit 2 Claude Code hands the model stderr only; when
# this report went to stdout the agent saw "No stderr output" and could not tell what to fix
# (LAB-1996 post-merge live control, 2026-09-12).
ERRORS=0
CHECKED=0
for i in "${!VAULT_TOPS[@]}"; do
TOP="${VAULT_TOPS[$i]}"
cd "$TOP"

if ! FILE_LINES=$(commit_files "$TOP" "${VAULT_DIRS[$i]}" "${VAULT_SPECS[$i]}"); then
  skip "could not compute the files this commit will contain (python3 failed)"
  continue
fi
STAGED_FILES=""
while IFS=$'\t' read -r kind value; do
  if [[ "$kind" == SKIP ]]; then
    skip "$value"
  elif [[ "$kind" == FILE ]]; then
    STAGED_FILES+="$value"$'\n'
  fi
done <<<"$FILE_LINES"
STAGED_FILES="${STAGED_FILES%$'\n'}"
if [[ -z "$STAGED_FILES" ]]; then
  continue
fi
CHECKED=1

while IFS= read -r file; do
  [[ -f "$file" ]] || continue

  # Check frontmatter exists
  if [[ "$(head -1 "$file")" != "---" ]]; then
    echo "ERROR: $file — missing frontmatter (no opening ---)" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Extract frontmatter block (lines between first and second ---)
  FM=$(awk '/^---$/{n++; if(n==2) exit} n==1{print}' "$file")

  if [[ -z "$FM" ]]; then
    echo "ERROR: $file — unclosed frontmatter block (missing closing ---)" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check required fields.
  # Herestrings throughout, NOT `echo "$FM" | grep -q` (LAB-1603): under the `pipefail`
  # at the top of this file, `grep -q` exits at its first match and closes the pipe, the
  # producer takes SIGPIPE, and `pipefail` promotes that to the pipeline's status — so
  # the test reports FAILURE precisely when the field IS present. Here that inverts a
  # `!`, meaning a valid file would be reported as missing a required field.
  for field in title tags created; do
    if ! grep -q "^${field}:" <<<"$FM"; then
      echo "ERROR: $file — missing required field: $field" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Validate created date format
  # `grep` without -q here, so it reads to EOF and cannot SIGPIPE its producer; the
  # -q test below is the herestring form for the same reason as the loop above.
  CREATED=$(grep "^created:" <<<"$FM" | sed 's/created: *//' | sed 's/^["'"'"']//;s/["'"'"']$//')
  if [[ -n "$CREATED" ]] && ! grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' <<<"$CREATED"; then
    echo "ERROR: $file — created date not in YYYY-MM-DD format: $CREATED" >&2
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$STAGED_FILES"
done

if [[ $CHECKED -eq 0 ]]; then
  exit 0
fi

if [[ $ERRORS -gt 0 ]]; then
  {
    echo ""
    echo "Vault frontmatter validation failed ($ERRORS errors)."
    echo "Run /obsidian-lint --fix to auto-repair, or fix manually."
  } >&2
  exit 2
fi

echo "Vault frontmatter: all checks passed."
exit 0
