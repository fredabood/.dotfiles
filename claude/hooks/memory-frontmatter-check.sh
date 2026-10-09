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
# The resolver (resolve_targets, common_dir, commit_files) lives in hooks/lib/vault-hook-resolver.sh,
# shared with memory-gitleaks-check.sh and tested by claude/tests/vault-hook-resolver.test.sh
# (LAB-2858). A missing, incomplete or failing lib blocks (exit 2): this gate cannot judge without it.
# Python runs with -I, so a shlex.py or subprocess.py planted in the cwd or the repo root is never
# imported in place of the standard module.
#
# Renamed-and-edited and typechanged notes are validated as additions (--no-renames, ACMT; LAB-2858):
# before, `git mv a.md b.md` plus an edit dropping `title:` passed unchecked. A pure `git mv` of a
# note without frontmatter is therefore blocked until the note gets frontmatter. `git rm` stages no
# new content and is not counted. When the file list cannot be computed for a vault commit, the
# commit is blocked rather than passed unchecked (LAB-2858, owner decision OD1): commit_files exits
# non-zero on a python3 failure, invalid parameters (3) or any git listing call that fails (4, e.g.
# a corrupt index). A pathspec commit on an unborn HEAD is diffed against the empty tree instead.
#
# Remaining limits, each a visible skip rather than a silent pass: interactive or file-driven
# adds and commits (-p, -i, -e, --pathspec-from-file), and pathspecs using $, backticks or braces.
# A partially staged file is validated from the working tree, not the staged blob.
#
# If you change this file, prove it with claude/tests/memory-frontmatter-check.test.sh AND by
# staging a frontmatter-less .md in a real vault worktree and watching the commit get BLOCKED —
# never by observing that the hook ran without error.

TAG="memory-frontmatter-check"

skip() {
  echo "$TAG: skipped — $1" >&2
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIB="$HERE/lib/vault-hook-resolver.sh"
# The shared resolver (resolve_targets, common_dir, commit_files; LAB-2858). Every way it can fail to
# load blocks, because this hook cannot judge a commit without it.
# [ -r ] first: under bash 3.2 `source missing || guard` never runs the guard (exit 1 = allow).
[ -r "$LIB" ] || { echo "$TAG: BLOCKED — resolver lib missing at $LIB; restore claude/hooks/lib in dotfiles" >&2; exit 2; }
# Any exit while loading (a syntax error, or a failing top-level line under set -e, which exits 1
# on bash 3.2) becomes 2.
trap 'echo "$TAG: BLOCKED — resolver lib at $LIB failed to load" >&2; exit 2' EXIT
# shellcheck source=lib/vault-hook-resolver.sh
. "$LIB"
trap - EXIT
if [ "${VAULT_HOOK_RESOLVER_API:-}" != 1 ] || ! declare -F resolve_targets common_dir commit_files >/dev/null; then
  echo "$TAG: BLOCKED — resolver lib at $LIB is incomplete" >&2; exit 2
fi

# A resolver failure (python3 missing or crashing) blocks: without it no commit can be judged (LAB-2948).
TARGETS=$(resolve_targets "$INPUT") || { echo "$TAG: BLOCKED — could not resolve the commit's repository (the resolver failed); blocking rather than passing unchecked" >&2; exit 2; }
if [[ -z "$TARGETS" ]]; then
  exit 0
fi

MEMORY_DIR="${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}"
VAULT_COMMON=""

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

# From here on this is a vault commit: an abort (set -e, a failed cd or mktemp) blocks, never exits 1 (LAB-2948).
WORK=""
trap 'rc=$?; [ -z "$WORK" ] || rm -rf "$WORK"; if [ "$rc" -ne 0 ] && [ "$rc" -ne 2 ]; then echo "$TAG: BLOCKED — the gate aborted (exit $rc) while judging a vault commit; blocking rather than passing unchecked" >&2; exit 2; fi' EXIT
WORK="$(mktemp -d "${TMPDIR:-/tmp}/memory-frontmatter-check.XXXXXX")"

# validate_note <name> <content path>: the frontmatter checks on one version of a note. Every error
# names <name>, the top-relative path, whichever version was read (LAB-2948).
validate_note() {
  local name="$1" path="$2" FM CREATED field

  # Check frontmatter exists
  if [[ "$(head -1 "$path")" != "---" ]]; then
    echo "ERROR: $name — missing frontmatter (no opening ---)" >&2
    ERRORS=$((ERRORS + 1))
    return 0
  fi

  # Extract frontmatter block (lines between first and second ---)
  FM=$(awk '/^---$/{n++; if(n==2) exit} n==1{print}' "$path")

  if [[ -z "$FM" ]]; then
    echo "ERROR: $name — unclosed frontmatter block (missing closing ---)" >&2
    ERRORS=$((ERRORS + 1))
    return 0
  fi

  # Check required fields.
  # Herestrings throughout, NOT `echo "$FM" | grep -q` (LAB-1603): under the `pipefail`
  # at the top of this file, `grep -q` exits at its first match and closes the pipe, the
  # producer takes SIGPIPE, and `pipefail` promotes that to the pipeline's status — so
  # the test reports FAILURE precisely when the field IS present. Here that inverts a
  # `!`, meaning a valid file would be reported as missing a required field.
  for field in title tags created; do
    if ! grep -q "^${field}:" <<<"$FM"; then
      echo "ERROR: $name — missing required field: $field" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Validate created date format
  # `grep` without -q here, so it reads to EOF and cannot SIGPIPE its producer; the
  # -q test below is the herestring form for the same reason as the loop above.
  CREATED=$(grep "^created:" <<<"$FM" | sed 's/created: *//' | sed 's/^["'"'"']//;s/["'"'"']$//')
  if [[ -n "$CREATED" ]] && ! grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' <<<"$CREATED"; then
    echo "ERROR: $name — created date not in YYYY-MM-DD format: $CREATED" >&2
    ERRORS=$((ERRORS + 1))
  fi
  return 0
}

# Every line of a BLOCK goes to stderr. On exit 2 Claude Code hands the model stderr only; when
# this report went to stdout the agent saw "No stderr output" and could not tell what to fix
# (LAB-1996 post-merge live control, 2026-09-12).
ERRORS=0
# Every vault target prints how many .md files it examined, or a ZERO-INPUT-OK reason; a silent
# "nothing checked" exit is gone (testing.md rule 1; LAB-2948).
TOTAL=0
for i in "${!VAULT_TOPS[@]}"; do
TOP="${VAULT_TOPS[$i]}"
cd "$TOP"

# --no-renames + ACMT: a renamed-and-edited or typechanged note is validated as an addition (LAB-2858).
if ! FILE_LINES=$(commit_files "$TOP" "${VAULT_DIRS[$i]}" "${VAULT_SPECS[$i]}" 1 no ACMT ".md"); then
  # A vault commit whose file list is unknown is blocked, not passed unchecked (LAB-2858, OD1). This
  # gate has no backstop: the vault's own git hooks run only the secret scan.
  echo "ERROR: $TOP — could not compute the files this commit will contain (the resolver's commit_files failed; its reason, if any, is above); blocking rather than passing unchecked" >&2
  ERRORS=$((ERRORS + 1))
  continue
fi
STAGED_FILES=""
N=0
SKIPPED=0
while IFS=$'\t' read -r kind value; do
  if [[ "$kind" == SKIP ]]; then
    skip "$value"
    SKIPPED=1
  elif [[ "$kind" == FILE ]]; then
    STAGED_FILES+="$value"$'\n'
    N=$((N + 1))
  fi
done <<<"$FILE_LINES"
STAGED_FILES="${STAGED_FILES%$'\n'}"
if [[ $N -eq 0 ]]; then
  if [[ $SKIPPED -eq 1 ]]; then
    echo "$TAG: $TOP: 0 .md file(s) examined — the skipped part above was not validated" >&2
    continue
  fi
  # ZERO-INPUT-OK: this commit adds or changes no .md file (message-only amend, --allow-empty, deletion-only, or non-.md content only)
  echo "$TAG: $TOP: 0 .md file(s) examined — ZERO-INPUT-OK: this commit adds or changes no .md file (message-only amend, --allow-empty, deletion-only, or non-.md content only)" >&2
  continue
fi

while IFS= read -r file; do
  # Both versions are validated (LAB-2948, owner decision OD-F): the working-tree file when it is a
  # regular file, and the staged blob (`:0:`) whenever it differs or the working tree has none. A
  # staged-then-deleted note, or a bad blob under a fixed but unstaged file, no longer passes.
  WT=0
  READ=0
  if [[ -f "$file" && ! -L "$file" ]]; then
    validate_note "$file" "$file"
    WT=1
    READ=1
  fi
  if git -C "$TOP" cat-file -e ":0:$file" 2>/dev/null; then
    git -C "$TOP" show ":0:$file" >"$WORK/blob"
    READ=1
    if [[ $WT -eq 0 ]] || ! cmp -s "$WORK/blob" "$file"; then
      validate_note "$file" "$WORK/blob"
    fi
  fi
  if [[ $READ -eq 0 ]]; then
    echo "ERROR: $file — listed for this commit but readable neither in the working tree nor the index" >&2
    ERRORS=$((ERRORS + 1))
  fi
done <<< "$STAGED_FILES"
echo "$TAG: $TOP: $N .md file(s) examined" >&2
TOTAL=$((TOTAL + N))
done

if [[ $ERRORS -gt 0 ]]; then
  {
    echo ""
    echo "Vault frontmatter validation failed ($ERRORS errors)."
    echo "Run /obsidian-lint --fix to auto-repair, or fix manually."
  } >&2
  exit 2
fi

if [[ $TOTAL -gt 0 ]]; then
  echo "Vault frontmatter: all checks passed."
fi
exit 0
