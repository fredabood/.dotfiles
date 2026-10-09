# vault-hook-resolver.sh — the commit resolver shared by the two memory-vault PreToolUse gates,
# hooks/memory-frontmatter-check.sh and hooks/memory-gitleaks-check.sh (LAB-2858). Until LAB-2858
# each hook carried its own copy (LAB-2457 owner ruling D3), and a fix to one copy left the other
# gate open.
#
# CONTRACT
#   - Sourced only, never run. It defines three functions and, as its LAST line, sets
#     VAULT_HOOK_RESOLVER_API=1. There is no other top-level command: a failing top-level line under
#     the hooks' `set -e` would exit 1 (allow) on bash 3.2, so the hooks load this file inside an
#     EXIT trap that turns any exit into 2 and then check the sentinel and the three functions.
#   - It never exits, never sets shell options, never cds and never shopts. It reads no hook
#     globals: everything comes in as arguments.
#   - Command text is parsed with shlex, never evaluated: a path containing $, a backtick or a glob
#     is reported as unresolvable rather than expanded.
#   - Heredocs stay inside function bodies: bash 3.2 mis-parses a heredoc inside $( ).
#   - Python runs isolated (`python3 -I`): no script directory or cwd on sys.path, no user site, no
#     PYTHON* variables. Without it, a shlex.py in the hook's process cwd or a subprocess.py at the
#     repo root was imported in place of the standard module and could exit 0 with no output, which
#     both gates read as "nothing to check" (LAB-2858).
#
# FUNCTIONS
#   resolve_targets <hook payload json>
#       The payload reaches Python on fd 3, never through the environment or argv: a payload of
#       1 MiB or more made the exec fail with E2BIG (LAB-2948).
#       One line per `git commit` found: "DIR<TAB><abs path><TAB><json>" or "SKIP<TAB><reason>".
#       The json says what else the commit will pick up: -a, -i, pathspecs, and every earlier
#       `git add` in the same command (LAB-2062). Its `plumbing` list names every earlier
#       index-writing call (update-index, read-tree, apply --cached/--index) as {"cmd", "dir"} or
#       {"cmd", "skip"}; a `git commit-tree` gets a DIR line whose plumbing ends with
#       {"cmd": "commit-tree"}. commit_files refuses both in the committed repo (LAB-2948).
#   common_dir <dir>
#       The physical git common dir: equal for a checkout and every one of its worktrees, different
#       for everything else (--show-toplevel would not do: it differs per worktree). rc 1 when <dir>
#       is not in a git repository.
#   commit_files <top> <commit dir> <json> <md_only 0|1> <renames yes|no> <diff filter> <label>
#       The files the commit will contain, as "FILE<TAB><top-relative path>" or "SKIP<TAB><reason>"
#       lines. When the json's no_verify is true (`-n`, `--no-verify`, or `git -c core.hooksPath=…`;
#       a later `--verify` clears it), every SKIP is printed as "BLOCK<TAB><reason> (--no-verify: …)"
#       instead, and the hooks block on it: the vault's git hook will not run to cover the gap
#       (LAB-2948). md_only=1 keeps only .md files; renames=no lists a rename as an addition
#       (--no-renames); the diff filter is git's --diff-filter; the label names a file in the skip
#       text (".md" or "file"). Git runs with list argv, never a shell, and pathspecs go after `--`.
#       Exit codes: 0 = the list is complete (SKIP lines name what it could not include); 3 = invalid
#       parameters (a caller bug), before anything is printed; 4 = a git call that lists part of the
#       commit failed (a corrupt index, an unreadable object) or a plumbing entry targets the
#       committed repo (it is not modelled), each reason on stderr, and stdout
#       must then be discarded. Both hooks block on any non-zero exit ("could not compute the files
#       this commit will contain"; LAB-2858, OD1). An unborn HEAD is not a failure: a pathspec
#       commit there is diffed against the empty tree.
#
# Tests: claude/tests/vault-hook-resolver.test.sh (the lib alone), plus both hook suites.

resolve_targets() {
  python3 -I - 3<<<"$1" <<'PY'
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
# Every index-writing plumbing call seen so far (update-index, read-tree, apply --cached/--index).
# The gates do not model what it stages, so a commit in the same repo after one blocks (LAB-2948).
plumbing = []
try:
    payload = json.loads(os.fdopen(3, "r", encoding="utf-8", errors="surrogateescape").read() or "")
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
    hooks_off = False  # `-c core.hooksPath=…` points git away from the vault's hooks, like --no-verify
    while j < len(args):
        a = args[j]
        if a == "-C":
            target = resolve(target, args[j + 1]) if j + 1 < len(args) else Unknown("git -C with no path")
            j += 2
        elif a == "-c":
            if j + 1 < len(args) and args[j + 1].lower().startswith("core.hookspath="):
                hooks_off = True
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
    elif sub in ("update-index", "read-tree") or (sub == "apply" and ("--cached" in rest or "--index" in rest)):
        if git_dir_env:
            plumbing.append({"cmd": sub, "skip": "git %s with an explicit --git-dir/--work-tree/GIT_DIR" % sub})
        elif isinstance(target, Unknown):
            plumbing.append({"cmd": sub, "skip": "git %s in an unresolvable directory (%s)" % (sub, target.reason)})
        else:
            plumbing.append({"cmd": sub, "dir": target})
    elif sub == "commit":
        if git_dir_env:
            emit("SKIP", "git commit with an explicit --git-dir/--work-tree/GIT_DIR")
        elif isinstance(target, Unknown):
            emit("SKIP", target.reason)
        else:
            spec = parse_commit(rest)
            spec["no_verify"] = spec["no_verify"] or hooks_off
            spec["adds"] = list(adds)
            spec["plumbing"] = list(plumbing)
            emit("DIR", target, json.dumps(spec))
    elif sub == "commit-tree":
        # commit-tree writes a commit object without running any hook; commit_files refuses it.
        if git_dir_env:
            emit("SKIP", "git commit-tree with an explicit --git-dir/--work-tree/GIT_DIR")
        elif isinstance(target, Unknown):
            emit("SKIP", target.reason)
        else:
            emit("DIR", target, json.dumps({"all": False, "include": False, "specs": [], "skips": [],
                                            "no_verify": False, "adds": list(adds),
                                            "plumbing": list(plumbing) + [{"cmd": "commit-tree", "dir": target}]}))
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
    spec = {"all": False, "include": False, "specs": [], "skips": [], "no_verify": False}
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
            elif name == "no-verify":
                spec["no_verify"] = True
            elif name == "verify":
                spec["no_verify"] = False
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
                elif ch == "n":
                    spec["no_verify"] = True
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

common_dir() {
  local d
  d=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  (cd "$d" 2>/dev/null && pwd -P)
}

commit_files() {
  CF_TOP="$1" CF_DIR="$2" CF_SPEC="$3" CF_MD_ONLY="$4" CF_RENAMES="$5" CF_FILTER="$6" CF_LABEL="$7" python3 -I - <<'PY'
import json, os, re, subprocess, sys

# A caller bug must not turn into a quiet "nothing to check": exit 3 before printing anything.
if (os.environ.get("CF_MD_ONLY") not in ("0", "1")
        or os.environ.get("CF_RENAMES") not in ("yes", "no")
        or not re.fullmatch(r"[ACDMRTUXB]+", os.environ.get("CF_FILTER") or "")
        or not os.environ.get("CF_LABEL")
        or not os.environ.get("CF_TOP") or not os.environ.get("CF_DIR")):
    sys.stderr.write("vault-hook-resolver: commit_files: invalid parameters\n")
    sys.exit(3)

top, cdir = os.environ["CF_TOP"], os.environ["CF_DIR"]
seen = []
failures = []  # a git listing that failed: the list is incomplete, so the caller must block (exit 4)
# A --no-verify commit (or -c core.hooksPath=…) skips the vault's git hook, the only other check of
# what a skip leaves out, so every SKIP for it becomes a BLOCK line (LAB-2948).
NO_VERIFY = False

def say(kind, value):
    if kind == "SKIP" and NO_VERIFY:
        kind = "BLOCK"
        value += " (--no-verify: the vault's git hook will not run, so this part would go unexamined)"
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
        if reason not in failures:
            failures.append(reason)
        return
    for p in paths:
        if os.environ["CF_MD_ONLY"] == "1" and not p.endswith(".md"):
            continue
        if "\n" in p or "\t" in p:
            say("SKIP", "a staged " + os.environ["CF_LABEL"] + " name contains a newline or tab")
        else:
            say("FILE", p)

def toplevel(d):
    out = git(d, "rev-parse", "--show-toplevel")
    return os.path.realpath(out.strip()) if out else None

CHANGED = (("diff", "--name-only", "-z", "--no-relative")
           + (() if os.environ["CF_RENAMES"] == "yes" else ("--no-renames",))
           + ("--diff-filter=" + os.environ["CF_FILTER"],))
try:
    spec = json.loads(os.environ["CF_SPEC"] or "{}")
except ValueError:
    spec = {"skips": ["could not read the parsed commit"]}
NO_VERIFY = bool(spec.get("no_verify"))
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
    # On an unborn HEAD (a vault's first commit, an orphan branch) the base is the empty tree.
    base = "HEAD" if git(cdir, "rev-parse", "--verify", "-q", "HEAD^{commit}") is not None else (
        (git(cdir, "hash-object", "-t", "tree", "/dev/null") or "").strip() or None)
    files(None if base is None else names(cdir, "diff", base, *CHANGED[1:] + ("--",) + tuple(specs)),
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

# Index-writing plumbing earlier in the same command, and commit-tree itself, are not modelled: in the
# committed repo they make the list incomplete, so the caller blocks (exit 4; LAB-2948, OD-C).
for p in spec.get("plumbing", []):
    if "skip" in p:
        say("SKIP", p["skip"])
        continue
    if toplevel(p["dir"]) != real_top:
        continue
    if p["cmd"] == "commit-tree":
        reason = "git commit-tree writes a commit without running any hook and is not modelled; use git commit"
    else:
        reason = ("git %s in the same command writes the index, which the vault gates do not model; "
                  "run it in its own call, then git commit" % p["cmd"])
    if reason not in failures:
        failures.append(reason)

if failures:
    for reason in failures:
        sys.stderr.write("vault-hook-resolver: commit_files: " + reason + "\n")
    sys.exit(4)
PY
}

VAULT_HOOK_RESOLVER_API=1
