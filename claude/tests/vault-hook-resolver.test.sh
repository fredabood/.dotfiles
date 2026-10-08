#!/usr/bin/env bash
# vault-hook-resolver.test.sh — the commit resolver both vault gates source (LAB-2858), tested on its
# own: resolve_targets, common_dir and commit_files, the lib's load contract, and static checks for
# the patterns the hooks must never reintroduce.
#
# Runs against a throwaway HOME and temp repos. The harness (check, setup, put, stage) is copied from
# memory-frontmatter-check.test.sh, not imported (testing.md: copy the harness, don't import one).
#   Run: bash claude/tests/vault-hook-resolver.test.sh
#   VAULT_HOOK_RESOLVER_UNDER_TEST=<path> points it at a modified copy of the lib (red runs, mutations).
#
# A missing lib is a counted FAIL, not a crash. Exit 1 when any case fails or none passed; the last
# line is always SUITE_RESULT.
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$PKG/tests/$(basename "${BASH_SOURCE[0]}")"
LIB="${VAULT_HOOK_RESOLVER_UNDER_TEST:-$PKG/hooks/lib/vault-hook-resolver.sh}"
HOOKS="$PKG/hooks/memory-frontmatter-check.sh $PKG/hooks/memory-gitleaks-check.sh"
# Physical path: git reports /private/var/... on macOS, and the assertions compare paths.
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/vault-hook-resolver-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

pass=0; failed=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; [ -n "${VERBOSE:-}" ] && printf '       rc=%s\n%s\n' "${RC:-}" "${OUT:-}" | sed 's/^/       /'; fi; return 0; }

GOOD=$'---\ntitle: Probe\ntags:\n  - probe\ncreated: 2026-09-12\n---\nbody line one\nbody line two\nbody line three\n'
TAB=$'\t'

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
}

put() { printf '%s' "$3" > "$1/$2"; }
stage() { put "$@" && git -C "$1" add -- "$2"; }

# payload <cwd> <command>: the PreToolUse JSON Claude Code sends.
payload() {
    python3 -c '
import json, sys
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "tool_input": {"command": sys.argv[2]}, "cwd": sys.argv[1]}))' "$1" "$2"
}

# lib_run <process cwd> <function> <args...>: source the lib in a subshell and call one function;
# sets OUT and RC. A lib that is missing or fails to load gives RC 99 and empty OUT.
lib_run() {
    local dir="$1"; shift
    OUT=$(cd "$dir" && { . "$LIB" 2>/dev/null || exit 99; } && "$@"); RC=$?
}

# resolve <process cwd> <payload cwd> <command>
resolve() { local p; p=$(payload "$2" "$3"); lib_run "$1" resolve_targets "$p"; }

# json_field <python expr over d>: evaluate against the JSON in the third field of OUT's one line.
json_field() { printf '%s\n' "$OUT" | cut -f3 | python3 -c 'import json, sys; d = json.load(sys.stdin); print('"$1"')'; }

line_count() { [ -z "$OUT" ] && echo 0 || printf '%s\n' "$OUT" | wc -l | tr -d ' '; }

echo "the lib is there"
t_l0() { [ -r "$LIB" ]; }
check "L0 the lib exists and is readable ($LIB)" t_l0

echo "resolve_targets"
t_rt1() { setup; resolve "$OTHER" "$OTHER" "git -C '$WT' commit -m x"; [ "$RC" -eq 0 ] && [ "$(line_count)" -eq 1 ] && [[ "$OUT" == "DIR${TAB}${WT}${TAB}{"* ]]; }
check "RT1 git -C '<wt>' commit -> exactly one DIR line for the worktree" t_rt1
t_rt2() {
    setup; resolve "$OTHER" "$OTHER" "cd '$WT' && git add a.md && git commit"
    [ "$RC" -eq 0 ] && [ "$(line_count)" -eq 1 ] && [[ "$OUT" == "DIR${TAB}${WT}${TAB}"* ]] \
        && [ "$(json_field 'd["adds"][0]["specs"], d["adds"][0]["dir"]')" = "['a.md'] $WT" ]
}
check "RT2 cd <wt> && git add a.md && git commit -> the add's spec [a.md] in the worktree" t_rt2
t_rt3() { setup; resolve "$OTHER" "$OTHER" "bash -c \"cd '$WT' && git commit\""; [ "$RC" -eq 0 ] && [ "$(line_count)" -eq 1 ] && [[ "$OUT" == "SKIP${TAB}"* ]]; }
check "RT3 a commit inside bash -c \"...\" -> one SKIP line" t_rt3
t_rt4() { setup; lib_run "$OTHER" resolve_targets '[1, 2]'; [ "$RC" -eq 0 ] && [ -z "$OUT" ]; }
check "RT4 a payload that is not a JSON object -> rc 0, nothing printed" t_rt4
# A module planted in the process cwd that exits 0 silently must not replace the standard one.
PLANT='import sys; sys.exit(0)'
t_rt5() {
    setup; mkdir -p "$T/plant$n"; printf '%s\n' "$PLANT" > "$T/plant$n/shlex.py"
    resolve "$T/plant$n" "$OTHER" "git -C '$WT' commit -m x"
    [ "$RC" -eq 0 ] && [ "$(line_count)" -eq 1 ] && [[ "$OUT" == "DIR${TAB}${WT}${TAB}{"* ]]
}
check "RT5 a shlex.py in the process cwd is not imported (python3 -I) -> still the RT1 line" t_rt5
t_rt6() { setup; resolve "$OTHER" "$OTHER" "git -C \"\$(touch '$T/pwn')\" commit -m x"; [ ! -e "$T/pwn" ] && [[ "$OUT" == "SKIP${TAB}"* ]]; }
check "RT6 \$(touch ...) in a -C argument is never run" t_rt6

echo "common_dir"
t_cd1() {
    setup; mkdir -p "$T/plain$n"
    local v w o
    lib_run "$OTHER" common_dir "$VAULT"; v=$OUT; [ "$RC" -eq 0 ] && [ -n "$v" ] || return 1
    lib_run "$OTHER" common_dir "$WT"; w=$OUT; [ "$RC" -eq 0 ] || return 1
    lib_run "$OTHER" common_dir "$OTHER"; o=$OUT; [ "$RC" -eq 0 ] || return 1
    lib_run "$OTHER" common_dir "$T/plain$n"
    [ "$v" = "$w" ] && [ "$v" != "$o" ] && [ "$RC" -eq 1 ] && [ -z "$OUT" ]
}
check "CD1 vault == its worktree, != another repo; a non-repo dir -> rc 1" t_cd1

echo "commit_files"
t_cf1() {
    setup; stage "$WT" a.md "$GOOD"; stage "$WT" b.txt "plain"
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 yes ACM ".md"
    [ "$RC" -eq 0 ] && [ "$OUT" = "FILE${TAB}a.md" ] || return 1
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 0 no ACMT "file"
    [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | sort | tr '\n' ' ')" = "FILE${TAB}a.md FILE${TAB}b.txt " ]
}
check "CF1 md_only 1 lists a.md only; md_only 0 lists a.md and b.txt" t_cf1
t_cf2() {
    setup; stage "$WT" a.md "$GOOD"; git -C "$WT" commit -qm a
    git -C "$WT" mv a.md b.md; grep -v '^title:' "$WT/b.md" > "$T/b.$n" && cp "$T/b.$n" "$WT/b.md"; git -C "$WT" add b.md
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 no ACMT ".md"
    [ "$RC" -eq 0 ] && [ "$OUT" = "FILE${TAB}b.md" ] || return 1
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 yes ACM ".md"
    [ "$RC" -eq 0 ] && [ -z "$OUT" ]
}
check "CF2 a renamed-and-edited .md: renames=no ACMT lists b.md; renames=yes ACM lists nothing" t_cf2
t_cf3() {
    setup; stage "$WT" target.md "$GOOD"; stage "$WT" link.md "$GOOD"; git -C "$WT" commit -qm two
    rm "$WT/link.md"; ln -s target.md "$WT/link.md"; git -C "$WT" add link.md
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 no ACMT ".md"
    [ "$RC" -eq 0 ] && [ "$OUT" = "FILE${TAB}link.md" ] || return 1
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 no ACM ".md"
    [ "$RC" -eq 0 ] && [ -z "$OUT" ]
}
check "CF3 a file -> symlink typechange is listed with ACMT, not with ACM" t_cf3
t_cf4() {
    setup; stage "$WT" "a${TAB}b.md" "$GOOD"
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 no ACMT ".md"
    [ "$OUT" = "SKIP${TAB}a staged .md name contains a newline or tab" ] || return 1
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 0 no ACMT "file"
    [ "$OUT" = "SKIP${TAB}a staged file name contains a newline or tab" ]
}
check "CF4 a staged name with a tab -> SKIP text names the label (.md / file)" t_cf4
t_cf5() {
    setup; stage "$WT" a.md "$GOOD"; printf '%s\n' "$PLANT" > "$WT/subprocess.py"
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 no ACMT ".md"
    [ "$RC" -eq 0 ] && [ "$OUT" = "FILE${TAB}a.md" ]
}
check "CF5 a subprocess.py at <top>, cwd <top>, is not imported -> FILE lines still printed" t_cf5
t_cf6() {
    setup; stage "$WT" a.md "$GOOD"
    cf6_refused() { lib_run "$WT" commit_files "$WT" "$WT" '{}' "$@" 2>/dev/null; [ "$RC" -ne 0 ] && [ -z "$OUT" ] || { echo "    accepted: [$*]"; return 1; }; }
    cf6_refused 2 no ACMT ".md" && cf6_refused 1 maybe ACMT ".md" && cf6_refused 1 no "A;x" ".md" \
        && cf6_refused 1 no ACMT "" && cf6_refused 1 no "" ".md" || return 1
    # Control: the same call with valid parameters lists the file.
    lib_run "$WT" commit_files "$WT" "$WT" '{}' 1 no ACMT ".md"
    [ "$RC" -eq 0 ] && [ "$OUT" = "FILE${TAB}a.md" ]
}
check "CF6 invalid md_only / renames / filter / empty label -> rc != 0, nothing on stdout" t_cf6

echo "the lib's own red test"
# ST1: the same cases against a stub that defines the three functions as no-ops and sets the
# sentinel. They must FAIL: a suite that passes against a stub proves nothing about the lib.
t_st1() {
    local stub="$T/stub-lib.sh" out rc
    printf 'resolve_targets() { :; }\ncommon_dir() { :; }\ncommit_files() { :; }\nVAULT_HOOK_RESOLVER_API=1\n' > "$stub"
    out=$(VAULT_HOOK_RESOLVER_ST1_CHILD=1 VAULT_HOOK_RESOLVER_UNDER_TEST="$stub" bash "$SELF" 2>&1); rc=$?
    [ "$rc" -eq 1 ] && grep -q '^  FAIL RT1 ' <<<"$out" && grep -q '^  FAIL CF1 ' <<<"$out"
}
# The child run itself does not repeat ST1 (and is not counted for it).
if [ -z "${VAULT_HOOK_RESOLVER_ST1_CHILD:-}" ]; then
    check "ST1 RT1 and CF1 FAIL against a no-op stub lib (child run exits 1)" t_st1
fi

echo "load contract and static checks"
t_nx1() {
    [ -r "$LIB" ] || return 1
    grep -nE '^[[:space:]]*(exit|set[[:space:]]|cd[[:space:]]|shopt)' "$LIB" && return 1
    local before after printed
    before=$(printf '%s' "$-|$(pwd -P)")
    printed=$( . "$LIB"; printf '%s' "$-|$(pwd -P)" > "$T/nx1.after" ) || return 1
    after=$(cat "$T/nx1.after")
    [ -z "$printed" ] && [ "$before" = "$after" ] || return 1
    local f; for f in "$LIB" $HOOKS; do /bin/bash -n "$f" || return 1; done
}
check "NX1 the lib never exits, sets, cds or shopts; sourcing prints nothing and keeps \$- and cwd; /bin/bash -n" t_nx1
t_s1() {
    local f; for f in "$LIB" $HOOKS; do [ -r "$f" ] || return 1; done
    grep -nE '^[[:space:]]*(source|\.)[[:space:]].*\|\|' "$LIB" $HOOKS && return 1
    # Every python3 invocation in the lib runs isolated; fewer than the two known ones is a FAIL.
    local calls isolated
    calls=$(grep -vE '^[[:space:]]*#' "$LIB" | grep -cE '(^|[[:space:]])python3([[:space:]]|$)')
    isolated=$(grep -vE '^[[:space:]]*#' "$LIB" | grep -cE '(^|[[:space:]])python3[[:space:]]+-I[[:space:]]')
    [ "$calls" -ge 2 ] && [ "$calls" -eq "$isolated" ] || { echo "    python3 calls: $calls, with -I: $isolated"; return 1; }
}
check "S1 no '. lib || guard' line (never runs on bash 3.2); every lib python3 call (>= 2) has -I" t_s1
# S2: outside function bodies the lib holds only comments, blank lines and the sentinel, as its last
# line. Heredoc bodies (between <<'PY' and PY) are skipped. 0 lines scanned is a FAIL.
t_s2() {
    [ -r "$LIB" ] || return 1
    awk '
        BEGIN { infn = 0; inhd = 0; scanned = 0; bad = 0; last = "" }
        { scanned++ }
        inhd { if ($0 == "PY") inhd = 0; next }
        /<<'"'"'PY'"'"'[[:space:]]*$/ { inhd = 1; next }
        infn { if ($0 == "}") infn = 0; next }
        /^[A-Za-z_][A-Za-z0-9_]*\(\) \{$/ { infn = 1; next }
        /^[[:space:]]*(#.*)?$/ { next }
        { if (last != "") { print "top-level line before the end: " last; bad = 1 } last = $0 }
        END {
            if (scanned == 0) { print "0 lines scanned"; exit 1 }
            if (last != "VAULT_HOOK_RESOLVER_API=1") { print "last top-level line is not the sentinel: " last; exit 1 }
            exit bad
        }' "$LIB"
}
check "S2 outside functions: only comments, blanks and VAULT_HOOK_RESOLVER_API=1 as the last line" t_s2

printf '\nSUITE_RESULT pass=%d fail=%d skip=0\n' "$pass" "$failed"
[ "$failed" -eq 0 ] && [ "$pass" -gt 0 ]
