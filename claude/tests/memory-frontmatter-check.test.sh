#!/usr/bin/env bash
# memory-frontmatter-check.test.sh — the gate must validate the index of the repo being COMMITTED:
# the vault's primary checkout or any worktree of it, and nothing else (LAB-1996).
# Runs against a throwaway HOME and temp repos. Run: bash claude/tests/memory-frontmatter-check.test.sh
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK:-$PKG/hooks/memory-frontmatter-check.sh}"
T="$(mktemp -d "${TMPDIR:-/tmp}/frontmatter-check-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

pass=0; failed=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; fi; }

BAD=$'# a note with no frontmatter\n'
GOOD=$'---\ntitle: Probe\ntags:\n  - probe\ncreated: 2026-09-12\n---\nbody\n'

# setup: a fresh vault (primary checkout + one worktree) and an unrelated repo for each case.
n=0
setup() {
    n=$((n + 1))
    local root="$T/case$n"
    VAULT="$root/memory"; WT="$VAULT/.claude/worktrees/wt"; OTHER="$root/other"
    for r in "$VAULT" "$OTHER"; do
        git init -q "$r"
        printf 'seed\n' > "$r/README"
        git -C "$r" add README && git -C "$r" commit -qm seed
    done
    git -C "$VAULT" worktree add -q "$WT" -b wt
    export MEMORY_VAULT_PATH="$VAULT"
}

# stage <repo> <file> <content>
stage() { printf '%s' "$3" > "$1/$2" && git -C "$1" add -- "$2"; }

# run_hook <cwd, or "" for none> <command>: sets RC, OUT (stdout) and ERR (stderr).
run_hook() {
    local payload
    payload=$(python3 -c '
import json, sys
d = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": sys.argv[2]}}
if sys.argv[1]:
    d["cwd"] = sys.argv[1]
print(json.dumps(d))' "$1" "$2")
    OUT=$(bash "$HOOK" <<<"$payload" 2>"$T/stderr"); RC=$?
    ERR=$(cat "$T/stderr")
}

blocked() { [ "$RC" -eq 2 ] && grep -q "$1" <<<"$OUT"; }
silent_pass() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; }
one_skip_notice() { [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$ERR" | wc -l | tr -d ' ')" -eq 1 ] && grep -q 'skipped' <<<"$ERR"; }

echo "which index is read"
t_worktree_blocked() { setup; stage "$WT" bad.md "$BAD"; run_hook "$WT" "git commit -m x"; blocked bad.md; }
check "vault worktree, bad .md staged, plain git commit (cwd) -> blocked" t_worktree_blocked
t_primary_blocked() { setup; stage "$VAULT" bad.md "$BAD"; run_hook "$VAULT" "git commit -m x"; blocked bad.md; }
check "primary vault checkout, bad .md staged -> blocked" t_primary_blocked
t_own_index() {
    setup; stage "$VAULT" primary-bad.md "$BAD"; stage "$WT" good.md "$GOOD"
    run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 0 ] && ! grep -q primary-bad.md <<<"$OUT"
}
check "worktree with valid .md passes although primary has a bad .md staged" t_own_index
t_primary_ignores_worktree() {
    setup; stage "$WT" wt-bad.md "$BAD"; stage "$VAULT" good.md "$GOOD"
    run_hook "$VAULT" "git commit -m x"
    [ "$RC" -eq 0 ] && ! grep -q wt-bad.md <<<"$OUT"
}
check "primary with valid .md passes although a worktree has a bad .md staged" t_primary_ignores_worktree
t_subdir() { setup; mkdir -p "$WT/notes"; stage "$WT" notes/bad.md "$BAD"; run_hook "$WT/notes" "git commit -m x"; blocked notes/bad.md; }
check "cwd in a subdirectory of a vault worktree -> blocked" t_subdir

echo "non-vault repos"
t_other_repo() { setup; stage "$OTHER" bad.md "$BAD"; run_hook "$OTHER" "git commit -m x"; silent_pass; }
check "non-vault repo with a bad .md staged -> not validated" t_other_repo
t_other_repo_primary_dirty() { setup; stage "$VAULT" bad.md "$BAD"; stage "$OTHER" x.md "$BAD"; run_hook "$OTHER" "git commit -m x"; silent_pass; }
check "non-vault commit is not blocked by files staged in the vault" t_other_repo_primary_dirty

echo "command shapes"
t_dash_c() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "git -C '$WT' commit -m x"; blocked bad.md; }
check "git -C <worktree> commit (cwd elsewhere) -> blocked" t_dash_c
t_cd() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "cd '$WT' && git commit -m x"; blocked bad.md; }
check "cd <worktree> && git commit (cwd elsewhere) -> blocked" t_cd
t_relative_c() { setup; stage "$WT" bad.md "$BAD"; run_hook "$VAULT" "git -C .claude/worktrees/wt commit -m x"; blocked bad.md; }
check "relative git -C resolves against cwd" t_relative_c
t_cumulative_c() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "git -C '$VAULT' -C .claude/worktrees/wt -c core.quotepath=off commit"; blocked bad.md; }
check "repeated -C is cumulative; -c <kv> is skipped" t_cumulative_c
t_cd_to_other() { setup; stage "$VAULT" bad.md "$BAD"; run_hook "$VAULT" "cd '$OTHER' && git commit -m x"; silent_pass; }
check "cd out of the vault && git commit -> not validated" t_cd_to_other
t_env_prefix() { setup; stage "$WT" bad.md "$BAD"; run_hook "$WT" "GIT_EDITOR=true git commit"; blocked bad.md; }
check "VAR=value git commit -> blocked" t_env_prefix
t_second_segment() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "git -C '$OTHER' status; git -C '$WT' commit -m x"; blocked bad.md; }
check "commit in a later segment is found" t_second_segment
t_subshell() { setup; stage "$VAULT" bad.md "$BAD"; run_hook "$OTHER" "(cd '$WT' && git status) && git -C '$VAULT' commit -m x"; blocked bad.md; }
check "cd inside a subshell does not leak; absolute -C still resolves" t_subshell
t_multiline_message() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "cd '$WT' && git commit -m \"line one

line two\""; blocked bad.md; }
check "multi-line quoted commit message does not break parsing" t_multiline_message

echo "wrappers and reserved words are not a silent pass"
# One check per shape; each passed silently (exit 0, no output) before the PR #10 review fix.
for shape in "if git -C '@' commit -m x; then echo ok; fi" \
             "true && { cd '@' && git commit -m x; }" \
             "! git -C '@' commit -m x" \
             "env -u FOO git -C '@' commit -m x" \
             "sudo -u someone git -C '@' commit -m x" \
             "xargs git -C '@' commit -m x"; do
    t_wrapped() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "${1//@/$WT}"; blocked bad.md; }
    check "$shape -> blocked" t_wrapped "$shape"
done
t_second_git_word() { setup; stage "$WT" bad.md "$BAD"; run_hook "$WT" "git log --grep git commit"; silent_pass; }
check "only the first git word counts: git log --grep git commit -> silent" t_second_git_word

echo "skip paths are visible"
t_skip_expansion() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "cd \"\$HOME/x\" && git commit -m x"; one_skip_notice; }
check "cd \$VAR && git commit -> one-line skip notice" t_skip_expansion
t_skip_unbalanced() { setup; run_hook "$WT" "git commit -m \"oops"; one_skip_notice; }
check "unparseable command -> one-line skip notice" t_skip_unbalanced
t_skip_git_dir() { setup; stage "$VAULT" bad.md "$BAD"; run_hook "$OTHER" "git --git-dir='$VAULT/.git' commit -m x"; one_skip_notice; }
check "--git-dir -> one-line skip notice" t_skip_git_dir
t_skip_git_dir_env() { setup; stage "$VAULT" bad.md "$BAD"; run_hook "$OTHER" "GIT_DIR='$VAULT/.git' git commit -m x"; one_skip_notice; }
check "GIT_DIR= prefix -> one-line skip notice" t_skip_git_dir_env
t_skip_no_cwd() { setup; run_hook "" "git commit -m x"; one_skip_notice; }
check "plain git commit with no payload cwd -> one-line skip notice" t_skip_no_cwd
t_skip_not_repo() { setup; mkdir -p "$T/plain$n"; run_hook "$T/plain$n" "git commit -m x"; one_skip_notice; }
check "target is not a git repo -> one-line skip notice" t_skip_not_repo
t_skip_no_vault() { setup; stage "$WT" bad.md "$BAD"; MEMORY_VAULT_PATH="$T/nope" run_hook "$WT" "git commit -m x"; one_skip_notice; }
check "vault path missing -> one-line skip notice" t_skip_no_vault
t_skip_bash_c() { setup; stage "$WT" bad.md "$BAD"; run_hook "$OTHER" "bash -c \"cd '$WT' && git commit -m x\""; one_skip_notice; }
check "git commit hidden in a quoted string -> one-line skip notice" t_skip_bash_c

echo "non-commit commands"
t_status() { setup; stage "$WT" bad.md "$BAD"; run_hook "$WT" "git status"; silent_pass; }
check "git status -> silent" t_status
t_log_grep() { setup; stage "$WT" bad.md "$BAD"; run_hook "$WT" "git log --grep commit"; silent_pass; }
check "git log --grep commit -> silent" t_log_grep
t_commit_tree() { setup; stage "$WT" bad.md "$BAD"; run_hook "$WT" "git commit-tree HEAD^{tree}"; silent_pass; }
check "git commit-tree -> silent" t_commit_tree
t_not_bash() { setup; OUT=$(bash "$HOOK" <<<'{"tool_name":"Read","tool_input":{"file_path":"/x"}}' 2>&1); RC=$?; [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }
check "payload with no command -> silent" t_not_bash

echo "command text is never executed"
t_no_exec_dollar() { setup; run_hook "$OTHER" "git -C \"\$(touch '$T/pwned1')\" commit -m x"; [ ! -e "$T/pwned1" ]; }
check "\$(...) in a -C argument is not run" t_no_exec_dollar
t_no_exec_backtick() { setup; run_hook "$OTHER" "cd \`touch '$T/pwned2'\` && git commit -m x"; [ ! -e "$T/pwned2" ]; }
check "backticks in a cd argument are not run" t_no_exec_backtick
t_no_exec_semicolon() { setup; run_hook "$OTHER" "git -C '$WT; touch $T/pwned3' commit -m x"; [ ! -e "$T/pwned3" ] && [ "$RC" -eq 0 ]; }
check "a quoted ';' in a -C path is a path, not a command" t_no_exec_semicolon

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
