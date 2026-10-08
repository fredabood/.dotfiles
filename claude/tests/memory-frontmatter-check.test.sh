#!/usr/bin/env bash
# memory-frontmatter-check.test.sh — the gate must validate the index of the repo being COMMITTED:
# the vault's primary checkout or any worktree of it, and nothing else (LAB-1996) — and the files the
# commit will actually contain, including ones staged by the same command (LAB-2062).
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

# put <repo> <file> <content>: write to the working tree only.
put() { printf '%s' "$3" > "$1/$2"; }
# stage <repo> <file> <content>
stage() { put "$@" && git -C "$1" add -- "$2"; }
# commit_tracked <repo> <file>: commit a valid version, then overwrite it with BAD, unstaged.
commit_tracked() { stage "$1" "$2" "$GOOD" && git -C "$1" commit -qm "$2" && put "$1" "$2" "$BAD"; }

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

# The reason goes to STDERR: on exit 2 Claude Code shows the model stderr only, so a reason on
# stdout reaches it as "No stderr output" (seen in the LAB-1996 post-merge live control).
blocked() { [ "$RC" -eq 2 ] && grep -q "ERROR: $1" <<<"$ERR" && grep -q 'obsidian-lint' <<<"$ERR"; }
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
    [ "$RC" -eq 0 ] && ! grep -q primary-bad.md <<<"$OUT$ERR"
}
check "worktree with valid .md passes although primary has a bad .md staged" t_own_index
t_primary_ignores_worktree() {
    setup; stage "$WT" wt-bad.md "$BAD"; stage "$VAULT" good.md "$GOOD"
    run_hook "$VAULT" "git commit -m x"
    [ "$RC" -eq 0 ] && ! grep -q wt-bad.md <<<"$OUT$ERR"
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

echo "stage and commit in one command (LAB-2062)"
# The hook runs BEFORE the command, so the index it can read is the one from before any `git add`
# in the same command. Every check below passed silently (exit 0, no output) before LAB-2062.
t_add_then_commit() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add bad.md && git commit -m x"; blocked bad.md; }
check "git add bad.md && git commit, nothing staged before -> blocked" t_add_then_commit
t_add_then_commit_c() { setup; put "$WT" bad.md "$BAD"; run_hook "$OTHER" "git -C '$WT' add bad.md && git -C '$WT' commit -m x"; blocked bad.md; }
check "git -C <wt> add && git -C <wt> commit (cwd elsewhere) -> blocked" t_add_then_commit_c
t_cd_add_commit() { setup; put "$WT" bad.md "$BAD"; run_hook "$OTHER" "cd '$WT' && git add bad.md && git commit -m x"; blocked bad.md; }
check "cd <wt> && git add bad.md && git commit -> blocked" t_cd_add_commit
t_add_subdir() { setup; mkdir -p "$WT/notes"; put "$WT" notes/bad.md "$BAD"; run_hook "$WT/notes" "git add bad.md && git commit -m x"; blocked notes/bad.md; }
check "git add pathspec is relative to the cwd subdirectory -> blocked" t_add_subdir
t_add_all() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add -A && git commit -m x"; blocked bad.md; }
check "git add -A && git commit, untracked bad .md -> blocked" t_add_all
t_add_dot() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add . && git commit -m x"; blocked bad.md; }
check "git add . && git commit, untracked bad .md -> blocked" t_add_dot
t_add_glob() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add '*.md' && git commit -m x"; blocked bad.md; }
check "git add '*.md' && git commit -> blocked (pathspec glob, not shell-expanded)" t_add_glob
t_add_update() { setup; commit_tracked "$WT" bad.md; run_hook "$WT" "git add -u && git commit -m x"; blocked bad.md; }
check "git add -u && git commit, tracked bad .md modified -> blocked" t_add_update
for shape in "git commit -am x" "git commit -a -m x" "git commit --all -m x"; do
    t_commit_all() { setup; commit_tracked "$WT" bad.md; run_hook "$WT" "$1"; blocked bad.md; }
    check "$shape, tracked bad .md modified -> blocked" t_commit_all "$shape"
done
for shape in "git commit -m x bad.md" "git commit -m x -- bad.md" "git commit -i -m x bad.md" "git commit --only -m x bad.md"; do
    t_commit_path() { setup; commit_tracked "$WT" bad.md; run_hook "$WT" "$1"; blocked bad.md; }
    check "$shape (pathspec), tracked bad .md modified -> blocked" t_commit_path "$shape"
done
t_add_good_untracked_bad() {
    setup; put "$WT" good.md "$GOOD"; put "$WT" bad.md "$BAD"
    run_hook "$WT" "git add good.md && git commit -m x"
    [ "$RC" -eq 0 ] && ! grep -q bad.md <<<"$OUT$ERR"
}
check "git add good.md && git commit passes with an unrelated untracked bad .md" t_add_good_untracked_bad
t_commit_path_excludes_index() {
    setup; put "$WT" good.md "$GOOD"; git -C "$WT" add good.md && git -C "$WT" commit -qm good
    put "$WT" good.md "${GOOD}more"; stage "$WT" bad.md "$BAD"
    run_hook "$WT" "git commit -m x good.md"
    [ "$RC" -eq 0 ] && ! grep -q bad.md <<<"$OUT$ERR"
}
check "git commit <good path> is not blocked by a bad .md staged outside the pathspec" t_commit_path_excludes_index
t_commit_msg_file() { setup; put "$WT" msg.md "$BAD"; run_hook "$WT" "git commit -F msg.md"; silent_pass; }
check "git commit -F msg.md: an option value is not a pathspec -> silent" t_commit_msg_file
t_add_after_commit() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git commit -m x; git add bad.md"; silent_pass; }
check "git add after the commit is not counted -> silent" t_add_after_commit
t_add_other_repo() { setup; put "$OTHER" x.md "$BAD"; run_hook "$OTHER" "git -C '$OTHER' add x.md && git -C '$WT' commit -m x"; silent_pass; }
check "git add in another repo does not count toward a vault commit -> silent" t_add_other_repo
t_add_dry_run() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add -n bad.md && git commit -m x"; silent_pass; }
check "git add -n (dry run) stages nothing -> silent" t_add_dry_run
t_add_rm() { setup; commit_tracked "$WT" bad.md; run_hook "$WT" "git rm -q --cached bad.md && git commit -m x"; silent_pass; }
check "git rm stages no content -> silent" t_add_rm
t_add_patch_skip() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add -p && git commit -m x"; one_skip_notice; }
check "git add -p && git commit -> one-line skip notice" t_add_patch_skip
t_add_subst_skip() { setup; put "$WT" bad.md "$BAD"; run_hook "$WT" "git add \$(ls) && git commit -m x"; one_skip_notice; }
check "git add \$(ls) && git commit -> one-line skip notice" t_add_subst_skip
t_add_skip_still_validates() { setup; stage "$WT" staged-bad.md "$BAD"; run_hook "$WT" "git add -p && git commit -m x"; blocked staged-bad.md && grep -q skipped <<<"$ERR"; }
check "a skipped git add does not cancel validation of the index -> blocked" t_add_skip_still_validates

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
t_no_exec_add_pathspec() { setup; run_hook "$WT" "git add \"\$(touch '$T/pwned4')\" && git commit -m x"; [ ! -e "$T/pwned4" ] && one_skip_notice; }
check "\$(...) in a git add pathspec is not run -> one-line skip notice" t_no_exec_add_pathspec

echo "renames and typechanges are validated (LAB-2858)"
# Both passed silently (exit 0) before LAB-2858: the file list used rename detection and ACM.
t_f_ren() {
    setup; stage "$WT" a.md "$GOOD"; git -C "$WT" commit -qm a
    git -C "$WT" mv a.md b.md; grep -v '^title:' "$WT/b.md" > "$T/b.$n" && cp "$T/b.$n" "$WT/b.md"; git -C "$WT" add b.md
    run_hook "$WT" "git commit -m x"; blocked "b.md — missing required field: title"
}
check "F-REN git mv a.md b.md + an edit dropping title: -> blocked, naming b.md" t_f_ren
t_f_tc() {
    setup; stage "$WT" target.txt "$BAD"; stage "$WT" link.md "$GOOD"; git -C "$WT" commit -qm two
    rm "$WT/link.md"; ln -s target.txt "$WT/link.md"; git -C "$WT" add link.md
    run_hook "$WT" "git commit -m x"; blocked link.md
}
check "F-TC .md typechanged to a symlink to a frontmatter-less file -> blocked" t_f_tc
t_f_nonmd() { setup; stage "$WT" notes.txt "$BAD"; run_hook "$WT" "git commit -m x"; [ "$RC" -eq 0 ] && ! grep -q 'ERROR' <<<"$ERR"; }
check "F-NONMD a frontmatter-less notes.txt staged -> not validated (md_only), rc 0" t_f_nonmd

echo "planted python modules are never imported (python3 -I, LAB-2858)"
PLANT='import sys; sys.exit(0)'
# run_hook_from <process cwd> <payload cwd> <command>: run_hook with the hook's own cwd set.
run_hook_from() {
    local payload
    payload=$(python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "tool_input": {"command": sys.argv[2]}, "cwd": sys.argv[1]}))' "$2" "$3")
    OUT=$(cd "$1" && bash "$HOOK" <<<"$payload" 2>"$T/stderr"); RC=$?
    ERR=$(cat "$T/stderr")
}
t_f_plant1() { setup; printf '%s\n' "$PLANT" > "$WT/subprocess.py"; stage "$WT" bad.md "$BAD"; run_hook "$WT" "git commit -m x"; blocked bad.md; }
check "F-PLANT1 subprocess.py at the worktree root, bad .md staged -> blocked" t_f_plant1
t_f_plant2() {
    setup; mkdir -p "$T/plant$n"; printf '%s\n' "$PLANT" > "$T/plant$n/shlex.py"; stage "$WT" bad.md "$BAD"
    run_hook_from "$T/plant$n" "$WT" "git commit -m x"; blocked bad.md
}
check "F-PLANT2 shlex.py in the hook's process cwd, bad .md staged -> blocked" t_f_plant2

echo "the resolver lib fails closed (LAB-2858)"
# mklayout <dir> <hook-name> [lib-source|none]: a copy of the hook layout (hooks/, hooks/lib/, scripts/).
mklayout() {
    mkdir -p "$1/hooks/lib" "$1/scripts"
    cp "$PKG/hooks/$2" "$1/hooks/"
    cp "$PKG/scripts/memory-gitleaks-scan.sh" "$1/scripts/"
    [ "${3:-}" = none ] || cp "${3:-$PKG/hooks/lib/vault-hook-resolver.sh}" "$1/hooks/lib/"
}
FM_HOOK="memory-frontmatter-check.sh"
REAL_LIB="$PKG/hooks/lib/vault-hook-resolver.sh"
t_f_l0() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$FM_HOOK"; mklayout "$L" "$FM_HOOK"
    stage "$WT" bad.md "$BAD"; run_hook "$WT" "git commit -m x"; blocked bad.md || return 1
    git -C "$WT" rm -q --cached bad.md; stage "$WT" good.md "$GOOD"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 0 ] && grep -q 'all checks passed' <<<"$OUT"
}
check "F-L0 control: a layout copy with the real lib blocks bad and passes good" t_f_l0
t_f_l1() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$FM_HOOK"; mklayout "$L" "$FM_HOOK" none
    stage "$WT" good.md "$GOOD"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'resolver lib missing' <<<"$ERR"
}
check "F-L1 no lib, clean commit -> rc 2, 'resolver lib missing'" t_f_l1
t_f_l2() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$FM_HOOK"
    printf 'resolve_targets() { :; }\ncommon_dir() { :; }\ncommit_files() { :; }\n' > "$T/nosentinel$n.sh"
    mklayout "$L" "$FM_HOOK" none; cp "$T/nosentinel$n.sh" "$L/hooks/lib/vault-hook-resolver.sh"
    stage "$WT" good.md "$GOOD"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'is incomplete' <<<"$ERR"
}
check "F-L2 a lib without the sentinel -> rc 2, 'incomplete'" t_f_l2
t_f_l3() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$FM_HOOK"; mklayout "$L" "$FM_HOOK"
    # A failing top-level line mid-file, before the sentinel: set -e exits 1 (allow) on bash 3.2
    # unless the load is trapped.
    awk '/^VAULT_HOOK_RESOLVER_API=1$/ { print "false" } { print }' "$REAL_LIB" > "$L/hooks/lib/vault-hook-resolver.sh"
    grep -qx false "$L/hooks/lib/vault-hook-resolver.sh" || return 1
    stage "$WT" good.md "$GOOD"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'failed to load' <<<"$ERR"
}
check "F-L3 a lib with a failing top-level line -> rc 2, 'failed to load'" t_f_l3
t_f_h() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$FM_HOOK"; mklayout "$L" "$FM_HOOK"
    printf 'commit_files() { return 1; }\n' >> "$L/hooks/lib/vault-hook-resolver.sh"
    stage "$WT" good.md "$GOOD"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'could not compute the files this commit will contain' <<<"$ERR"
}
check "F-H the vault commit's file list cannot be computed -> rc 2, blocked (OD1)" t_f_h

printf '\n%d passed, %d failed\n' "$pass" "$failed"
printf 'SUITE_RESULT pass=%d fail=%d skip=0\n' "$pass" "$failed"
[ "$failed" -eq 0 ] && [ "$pass" -gt 0 ]
