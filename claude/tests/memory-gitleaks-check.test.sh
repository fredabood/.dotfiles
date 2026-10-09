#!/usr/bin/env bash
# memory-gitleaks-check.test.sh — the vault secret-scan gate (LAB-2457) must BLOCK a memory-vault
# commit whose content carries a credential, in the primary checkout and in any worktree, pass the
# two allowlisted placeholders, and never pass silently on a missing prerequisite.
#
# Runs against a throwaway HOME and temp repos. The harness is copied from
# memory-frontmatter-check.test.sh, not imported (testing.md: copy the harness, don't import one).
#   Run: bash claude/tests/memory-gitleaks-check.test.sh
#   HOOK=<path> and MEMORY_GITLEAKS_CHECK_UNDER_TEST=<scan script> point it at a modified copy.
#
# This file is in a PUBLIC repo whose pre-commit hook runs gitleaks, so no secret and no placeholder
# is written literally: the planted token is generated at runtime, and the placeholder strings are
# assembled from pieces.
#
# Exit 1 when any case fails, or when no case that needs gitleaks passed (a host without gitleaks
# skips those cases and must not read as green); the last line is always SUITE_RESULT.
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK:-$PKG/hooks/memory-gitleaks-check.sh}"
# The package the hook under test belongs to: mklayout copies from it, so HOOK=<an older copy's
# hooks/memory-gitleaks-check.sh> runs the layout cases against that copy too (red runs, LAB-2948).
SRC="$(cd "$(dirname "$HOOK")/.." && pwd)"
SCAN="${MEMORY_GITLEAKS_CHECK_UNDER_TEST:-$PKG/scripts/memory-gitleaks-scan.sh}"
export MEMORY_GITLEAKS_CHECK_UNDER_TEST="$SCAN"
# Physical path: git reports /private/var/... on macOS, and the assertions compare paths.
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gitleaks-check-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML MEMORY_GITLEAKS_CHECK
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1

pass=0; failed=0; skipped=0; glpass=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; [ -n "${VERBOSE:-}" ] && printf '       rc=%s\n%s\n' "${RC:-}" "${ERR:-}" | sed 's/^/       /'; fi; }
# gl_check: a case that needs a gitleaks binary on the test host; counted as skip without one.
gl_check() {
    if [ "$HAVE_GITLEAKS" -eq 0 ]; then skipped=$((skipped + 1)); printf '  skip %s (gitleaks not installed)\n' "$1"; return; fi
    local before=$pass
    check "$@"
    [ "$pass" -gt "$before" ] && glpass=$((glpass + 1))
    return 0
}

PLANTED="ghp_$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 36)"
LEAK="token: $PLANTED"$'\n'
CS="client""_secret"; GO="GOC""SPX-abc123"
MARKER_LINE="api_key: <redacted LAB-2288 — the value lives in 1Password>"
GOCSPX_LINE="    \"$CS\": \"$GO...\","
PLACEHOLDERS="$MARKER_LINE"$'\n'"$GOCSPX_LINE"$'\n'
# The vault's two placeholder allowlists, verbatim apart from the assembled pieces.
CONFIG_TOML="[extend]
  useDefault = true

[[allowlists]]
  description = \"LAB-2288 redaction markers are not secrets\"
  regexTarget = \"line\"
  regexes = ['''<redacted LAB-2288[^>]*>''']

[[allowlists]]
  description = \"generic-api-key: a truncated Google OAuth example, not a value\"
  regexTarget = \"line\"
  regexes = ['''\"$CS\": \"$GO\\.\\.\\.\"''']
"

# setup: a fresh vault (primary checkout + one worktree, .gitleaks.toml committed) and an unrelated
# repo for each case.
n=0
setup() {
    n=$((n + 1))
    local root="$T/case$n"
    VAULT="$root/memory"; WT="$VAULT/.claude/worktrees/wt"; OTHER="$root/other"
    for r in "$VAULT" "$OTHER"; do
        git init -q "$r"
        printf 'seed\n' > "$r/README"
        git -C "$r" add README
    done
    printf '%s' "$CONFIG_TOML" > "$VAULT/.gitleaks.toml"
    git -C "$VAULT" add .gitleaks.toml
    for r in "$VAULT" "$OTHER"; do git -C "$r" commit -qm seed; done
    git -C "$VAULT" worktree add -q "$WT" -b wt
    export MEMORY_VAULT_PATH="$VAULT"
}

put() { printf '%s' "$3" > "$1/$2"; }
stage() { put "$@" && git -C "$1" add -- "$2"; }

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

# run_scan <toplevel> <config> <path>...: the check script directly; sets RC, OUT, ERR.
run_scan() {
    local top="$1" config="$2"; shift 2
    : > "$T/list"
    local p; for p in "$@"; do printf '%s\0' "$p" >> "$T/list"; done
    OUT=$(bash "$SCAN" "$top" "$config" "$T/list" 2>"$T/stderr"); RC=$?
    ERR=$(cat "$T/stderr")
}

count_line() { grep -Eq "memory-gitleaks-check: .*: [1-9][0-9]* staged path\(s\) examined" <<<"$ERR"; }
disclaimer() { grep -q 'keyword-and-entropy check, not a proof' <<<"$ERR"; }
# A blocked commit: exit 2, a line naming the check, the file and the rule, a count, the next step.
blocked() {
    [ "$RC" -eq 2 ] && grep 'memory-gitleaks-check' <<<"$ERR" | grep "$1" | grep -q 'github-pat' \
        && count_line && disclaimer && grep -q 'Vault secret scan blocked this commit' <<<"$ERR"
}
silent_pass() { [ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; }

echo "a planted credential is blocked (red)"
t_r1() {
    setup; stage "$WT" leak.md "$LEAK"; run_hook "$WT" "git commit -m x"; blocked leak.md || return 1
    git -C "$WT" show HEAD:.gitleaks.toml > "$T/cfg.toml"
    run_scan "$WT" "$T/cfg.toml" leak.md
    [ "$RC" -eq 1 ] && grep -q "ERROR: memory-gitleaks-check: $WT: leak.md:1 — rule github-pat" <<<"$ERR" \
        && grep -q "memory-gitleaks-check: $WT: 1 staged path(s) examined" <<<"$ERR"
}
gl_check "R1 worktree commit with a token -> hook blocks (2); the check alone exits 1 naming target, file, rule" t_r1
t_r2() { setup; stage "$VAULT" leak.md "$LEAK"; run_hook "$VAULT" "git commit -m x"; blocked leak.md; }
gl_check "R2 primary checkout commit with a token -> blocked" t_r2
t_r3() { setup; stage "$WT" leak.md "$LEAK"; run_hook "$OTHER" "git -C '$WT' commit -m x"; blocked leak.md; }
gl_check "R3 git -C <worktree> commit (cwd elsewhere) -> blocked" t_r3
t_r4() { setup; stage "$WT" leak.md "$LEAK"; run_hook "$OTHER" "cd '$WT' && git commit -m x"; blocked leak.md; }
gl_check "R4 cd <worktree> && git commit (cwd elsewhere) -> blocked" t_r4
t_r5() { setup; put "$WT" leak.md "$LEAK"; run_hook "$WT" "git add leak.md && git commit -m x"; blocked leak.md; }
gl_check "R5 git add leak.md && git commit, nothing staged before -> blocked" t_r5
t_staged_only() {
    setup; stage "$WT" leak.md "$LEAK"; put "$WT" leak.md "clean now"$'\n'
    run_hook "$WT" "git commit -m x"; blocked "leak.md (staged blob):1"
}
gl_check "token in the staged blob only (working tree cleaned, not re-added) -> blocked" t_staged_only
t_any_ext() { setup; stage "$WT" notes.txt "$LEAK"; run_hook "$WT" "git commit -m x"; blocked notes.txt; }
gl_check "a non-.md file is scanned too -> blocked" t_any_ext
t_s1() { setup; stage "$WT" leak.md "$LEAK"; run_hook "$WT" "git commit -m x"; [ "$RC" -eq 2 ] && ! grep -qF "$PLANTED" <<<"$OUT$ERR"; }
gl_check "S1 the planted value never appears in stdout or stderr (--redact)" t_s1

echo "placeholders and isolation (green)"
t_g1() {
    setup; stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 0 ] && grep -q "memory-gitleaks-check: $WT: 1 staged path(s) examined" <<<"$ERR" && disclaimer \
        && ! grep -q 'ERROR' <<<"$ERR"
}
gl_check "G1 only the two allowlisted placeholders -> passes, with count and disclaimer lines" t_g1
t_g2() {
    setup; stage "$VAULT" leak.md "$LEAK"; stage "$WT" ok.md "$PLACEHOLDERS"
    run_hook "$WT" "git commit -m x"; [ "$RC" -eq 0 ] && ! grep -q leak.md <<<"$OUT$ERR"
}
gl_check "G2 worktree commit is not judged by a token staged in the primary checkout" t_g2
t_g3() { setup; stage "$OTHER" leak.md "$LEAK"; run_hook "$OTHER" "git commit -m x"; silent_pass; }
check "G3 a non-vault repo with a token staged -> not scanned, silent" t_g3

echo "invalid runs are never a silent pass"
t_z1() {
    setup; git -C "$WT" show HEAD:.gitleaks.toml > "$T/cfg.toml"; run_scan "$WT" "$T/cfg.toml"
    [ "$RC" -eq 2 ] && grep -qF "memory-gitleaks-check: $WT: 0 staged path(s) examined — nothing to scan" <<<"$ERR"
}
gl_check "Z1 the check with zero inputs exits 2 with its literal text" t_z1
t_z2() {
    setup; run_hook "$WT" "git commit --allow-empty -m x"
    [ "$RC" -eq 0 ] \
        && grep -qF "memory-gitleaks-check: $WT: 0 staged path(s) examined — ZERO-INPUT-OK: such a commit stages no content that could hold a secret" <<<"$ERR" \
        && grep -q '^ *# ZERO-INPUT-OK: such a commit stages no content that could hold a secret' "$HOOK"
}
check "Z2 a vault commit with no content -> allowed, printing the ZERO-INPUT-OK reason that is in the source" t_z2
t_p1() {
    setup; stage "$WT" leak.md "$LEAK"
    mkdir -p "$T/nogl"
    local tool; for tool in git python3; do ln -sf "$(command -v "$tool")" "$T/nogl/$tool"; done
    if PATH="$T/nogl:/usr/bin:/bin" command -v gitleaks >/dev/null 2>&1; then return 1; fi
    PATH="$T/nogl:/usr/bin:/bin" run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'gitleaks not installed' <<<"$ERR" && grep -q 'Vault secret scan blocked' <<<"$ERR"
}
check "P1 gitleaks missing -> blocked with 'gitleaks not installed'" t_p1
t_p2() {
    setup; git -C "$VAULT" rm -q .gitleaks.toml && git -C "$VAULT" commit -qm drop
    stage "$VAULT" ok.md "$PLACEHOLDERS"; run_hook "$VAULT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'no .gitleaks.toml' <<<"$ERR" || return 1
    run_scan "$VAULT" "$T/does-not-exist.toml" ok.md
    [ "$RC" -eq 2 ] && grep -q 'no .gitleaks.toml at' <<<"$ERR"
}
gl_check "P2 no .gitleaks.toml committed at HEAD -> blocked; the check alone exits 2" t_p2
t_self_allowlist() {
    setup; stage "$WT" leak.md "$LEAK"
    printf '%s\n[[allowlists]]\n  regexes = [%s]\n' "$CONFIG_TOML" "'''ghp_'''" > "$WT/.gitleaks.toml"
    git -C "$WT" add .gitleaks.toml
    run_hook "$WT" "git commit -m x"; blocked leak.md
}
gl_check "a commit cannot allowlist itself: the staged .gitleaks.toml is not the config used" t_self_allowlist

echo "kill switch"
t_k1() {
    setup; stage "$WT" leak.md "$LEAK"; MEMORY_GITLEAKS_CHECK=off run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 0 ] && grep -q 'DISABLED by MEMORY_GITLEAKS_CHECK=off' <<<"$ERR"
}
check "K1 MEMORY_GITLEAKS_CHECK=off -> allowed, with a DISABLED line" t_k1

echo "-c is load-bearing (mutation)"
t_m1() {
    setup; stage "$WT" ok.md "$PLACEHOLDERS"
    sed 's/ -c "\$CONFIG"//' "$SCAN" > "$T/scan-no-c.sh"
    grep -q -- '-c "\$CONFIG"' "$T/scan-no-c.sh" && return 1
    MEMORY_GITLEAKS_CHECK_UNDER_TEST="$T/scan-no-c.sh" run_hook "$WT" "git commit -m x"
    [ "$RC" -ne 0 ]
}
gl_check "M1 deleting -c from the check turns the placeholder case red" t_m1

echo "command text is never executed"
t_x1() { setup; run_hook "$OTHER" "git -C \"\$(touch '$T/pwned')\" commit -m x"; [ ! -e "$T/pwned" ]; }
check "X1 \$(...) in a -C argument is not run" t_x1
t_not_commit() { setup; stage "$WT" leak.md "$LEAK"; run_hook "$WT" "git status"; silent_pass; }
check "git status -> silent" t_not_commit

echo "renames and typechanges are scanned (LAB-2858)"
CLEAN=$'line one\nline two\nline three\nline four\nline five\n'
t_g_ren() {
    setup; stage "$WT" a.md "$CLEAN"; git -C "$WT" commit -qm a
    git -C "$WT" mv a.md b.md; printf '%s' "$LEAK" >> "$WT/b.md"; git -C "$WT" add b.md
    run_hook "$WT" "git commit -m x"; blocked b.md
}
gl_check "G-REN a renamed-and-edited file carrying a token -> blocked" t_g_ren
t_g_tc() {
    # A symlink's staged blob is its target text, so a token as the target is content git commits.
    setup; stage "$WT" leak.md "$CLEAN"; git -C "$WT" commit -qm a
    rm "$WT/leak.md"; ln -s "$PLANTED" "$WT/leak.md"; git -C "$WT" add leak.md
    run_hook "$WT" "git commit -m x"; blocked "leak.md (staged blob)"
}
gl_check "G-TC a file typechanged to a symlink whose target is a token -> blocked" t_g_tc

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
t_g_plant1() {
    setup; mkdir -p "$T/plant$n"; printf '%s\n' "$PLANT" > "$T/plant$n/shlex.py"; stage "$WT" leak.md "$LEAK"
    run_hook_from "$T/plant$n" "$WT" "git commit -m x"; blocked leak.md
}
gl_check "G-PLANT1 shlex.py in the hook's process cwd, token staged -> blocked" t_g_plant1
t_g_plant2() {
    setup; printf '%s\n' "$PLANT" > "$VAULT/subprocess.py"; stage "$VAULT" leak.md "$LEAK"
    run_hook_from "$VAULT" "$VAULT" "git commit -m x"; blocked leak.md
}
gl_check "G-PLANT2 subprocess.py at the vault root, process cwd = vault root, token staged -> blocked" t_g_plant2

echo "the resolver lib fails closed (LAB-2858)"
# mklayout <dir> <hook-name> [lib-source|none]: a copy of the hook layout (hooks/, hooks/lib/, scripts/).
# The scan script is copied too, else the layout would exit 2 for the wrong reason.
mklayout() {
    mkdir -p "$1/hooks/lib" "$1/scripts"
    cp "$SRC/hooks/$2" "$1/hooks/"
    cp "$SRC/scripts/memory-gitleaks-scan.sh" "$1/scripts/"
    [ "${3:-}" = none ] || cp "${3:-$SRC/hooks/lib/vault-hook-resolver.sh}" "$1/hooks/lib/"
}
GL_HOOK="memory-gitleaks-check.sh"
REAL_LIB="$PKG/hooks/lib/vault-hook-resolver.sh"
t_g_l0() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK"
    stage "$WT" leak.md "$LEAK"; run_hook "$WT" "git commit -m x"; blocked leak.md || return 1
    git -C "$WT" rm -q --cached leak.md; stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 0 ] && grep -q "memory-gitleaks-check: $WT: 1 staged path(s) examined" <<<"$ERR"
}
gl_check "G-L0 control: a layout copy with the real lib blocks a token and passes the placeholders" t_g_l0
t_g_l1() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK" none
    stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'resolver lib missing' <<<"$ERR"
}
check "G-L1 no lib, clean commit -> rc 2, 'resolver lib missing'" t_g_l1
t_g_l2() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK" none
    printf 'resolve_targets() { :; }\ncommon_dir() { :; }\ncommit_files() { :; }\n' > "$L/hooks/lib/vault-hook-resolver.sh"
    stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'is incomplete' <<<"$ERR"
}
check "G-L2 a lib without the sentinel -> rc 2, 'incomplete'" t_g_l2
# G-L2b/G-L2c: the sentinel is set but a function is missing; only the declare -F half catches it.
lib_without() { sed "s/^$1() {/$1_gone() {/" "$REAL_LIB"; }
t_g_l2b() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK" none
    lib_without resolve_targets > "$L/hooks/lib/vault-hook-resolver.sh"
    grep -q '^resolve_targets_gone() {' "$L/hooks/lib/vault-hook-resolver.sh" || return 1
    stage "$WT" leak.md "$LEAK"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'is incomplete' <<<"$ERR"
}
check "G-L2b sentinel set, resolve_targets missing, token staged -> rc 2, 'incomplete'" t_g_l2b
t_g_l2c() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK" none
    lib_without commit_files > "$L/hooks/lib/vault-hook-resolver.sh"
    grep -q '^commit_files_gone() {' "$L/hooks/lib/vault-hook-resolver.sh" || return 1
    stage "$WT" leak.md "$LEAK"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'is incomplete' <<<"$ERR"
}
check "G-L2c sentinel set, commit_files missing, token staged -> rc 2, 'incomplete'" t_g_l2c
t_g_l3() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK"
    awk '/^VAULT_HOOK_RESOLVER_API=1$/ { print "false" } { print }' "$REAL_LIB" > "$L/hooks/lib/vault-hook-resolver.sh"
    grep -qx false "$L/hooks/lib/vault-hook-resolver.sh" || return 1
    stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'failed to load' <<<"$ERR"
}
check "G-L3 a lib with a failing top-level line -> rc 2, 'failed to load'" t_g_l3
t_g_h() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK"
    printf 'commit_files() { return 1; }\n' >> "$L/hooks/lib/vault-hook-resolver.sh"
    stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'could not compute the files this commit will contain .* blocking' <<<"$ERR" \
        && grep -q 'Vault secret scan blocked this commit' <<<"$ERR"
}
check "G-H the vault commit's file list cannot be computed -> rc 2, blocked with the trailer (OD1)" t_g_h
# G-GF: a git listing call fails inside commit_files (a corrupt index), with the real lib. Before the
# review fix this was a skip notice and rc 0: nothing was scanned.
t_g_gf() {
    setup; stage "$WT" leak.md "$LEAK"
    printf 'garbage' > "$(git -C "$WT" rev-parse --path-format=absolute --git-path index)"
    run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q 'could not compute the files this commit will contain .* blocking' <<<"$ERR" \
        && grep -q 'commit_files: could not read the index' <<<"$ERR"
}
check "G-GF a corrupt index in a vault worktree -> rc 2, blocked, the git reason shown (OD1)" t_g_gf

echo "fail-open paths are closed (LAB-2948)"
# run_hook_big <cwd> <repo>: run_hook with `git -C '<repo>' commit -m '<2 MiB>'`. The payload is built
# inside python3, because argv has the same 1 MiB limit the environment had.
run_hook_big() {
    local payload
    payload=$(python3 -c '
import json, sys
cmd = "git -C %s commit -m %s" % ("\x27" + sys.argv[2] + "\x27", "\x27" + "x" * 2097152 + "\x27")
print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "tool_input": {"command": cmd}, "cwd": sys.argv[1]}))' "$1" "$2")
    OUT=$(bash "$HOOK" <<<"$payload" 2>"$T/stderr"); RC=$?
    ERR=$(cat "$T/stderr")
}
t_g_big() { setup; stage "$WT" leak.md "$LEAK"; run_hook_big "$OTHER" "$WT"; blocked leak.md; }
gl_check "G-BIG a 2 MiB commit command, token staged -> blocked (item 4)" t_g_big
t_g_pyfail() {
    setup; local L="$T/layout$n" HOOK="$T/layout$n/hooks/$GL_HOOK"; mklayout "$L" "$GL_HOOK"
    printf 'resolve_targets() { return 1; }\n' >> "$L/hooks/lib/vault-hook-resolver.sh"
    stage "$WT" ok.md "$PLACEHOLDERS"; run_hook "$WT" "git commit -m x"
    [ "$RC" -eq 2 ] && grep -q "could not resolve the commit's repository" <<<"$ERR"
}
check "G-PYFAIL resolve_targets fails, clean commit -> rc 2, 'could not resolve the commit's repository' (item 4)" t_g_pyfail

printf '\nSUITE_RESULT pass=%d fail=%d skip=%d\n' "$pass" "$failed" "$skipped"
[ "$failed" -eq 0 ] && [ "$pass" -gt 0 ] && [ "$glpass" -gt 0 ]
