#!/usr/bin/env bash
# memory-gitleaks-git-hook.test.sh — the memory vault's git pre-commit and pre-push secret scan
# (LAB-2857) must REFUSE a commit or push whose content carries a credential, made with plain git
# (a terminal, Obsidian desktop, claude-settings-sync.sh) in the primary checkout or any worktree;
# pass the two allowlisted placeholders; and never pass silently on a missing prerequisite.
#
# Every case runs a REAL `git commit` or `git push` against hooks put in place by the real
# installer, with a local bare repo as the remote. Runs against a throwaway HOME and temp repos; the
# harness is copied from memory-gitleaks-check.test.sh, not imported (testing.md).
#   Run: bash claude/tests/memory-gitleaks-git-hook.test.sh
#   MEMORY_GITLEAKS_COMMIT_CHECK_UNDER_TEST=<wrapper> points the installed hooks at a modified copy
#   (the mutation runs in the PR use it); INSTALLER=<path> swaps the installer.
#
# This file is in a PUBLIC repo whose pre-commit runs gitleaks, so no secret and no placeholder is
# written literally: the planted token is generated at runtime, the placeholders are assembled.
#
# Exit 1 when any case fails, when nothing passed, or when no case that needs gitleaks passed (a
# host without gitleaks must not read as green); the last line is always SUITE_RESULT.
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALLER="${INSTALLER:-$PKG/scripts/install-vault-hooks.sh}"
REAL_CHECK="$PKG/scripts/memory-gitleaks-commit-check.sh"
# Physical path: git reports /private/var/... on macOS, and the assertions compare paths.
T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gitleaks-git-hook-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML MEMORY_GITLEAKS_CHECK MEMORY_GITLEAKS_PATH_PREPEND
git config --global user.email test@example.invalid
git config --global user.name test
git config --global init.defaultBranch main

HAVE_GITLEAKS=0
command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1
GITLEAKS_DIR="$(dirname "$(command -v gitleaks 2>/dev/null || echo /nonexistent/gitleaks)")"

pass=0; failed=0; skipped=0; glpass=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; [ -n "${VERBOSE:-}" ] && printf 'rc=%s\n%s\n' "${RC:-}" "${ERR:-}" | sed 's/^/       /'; fi; }
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
# An allowlist that would wave the planted token through — used to prove a commit or push cannot
# allowlist itself.
SELF_ALLOW="$CONFIG_TOML
[[allowlists]]
  description = \"self-allowlist attempt\"
  regexTarget = \"line\"
  regexes = ['''token: ghp_''']
"

# setup: a fresh vault (primary checkout + one worktree, .gitleaks.toml committed and pushed to a
# bare remote) with the hooks installed by the real installer.
n=0
setup() {
    n=$((n + 1))
    local root="$T/case$n"
    VAULT="$root/memory"; WT="$VAULT/.claude/worktrees/wt"; REMOTE="$root/remote.git"
    git init -q --bare "$REMOTE"
    git init -q "$VAULT"
    printf 'seed\n' > "$VAULT/README"
    printf '%s' "$CONFIG_TOML" > "$VAULT/.gitleaks.toml"
    git -C "$VAULT" add README .gitleaks.toml
    git -C "$VAULT" commit -q --no-verify -m seed
    git -C "$VAULT" remote add origin "$REMOTE"
    git -C "$VAULT" push -q --no-verify -u origin main 2>/dev/null
    git -C "$VAULT" worktree add -q "$WT" -b wt
    [ "${1:-}" = nohooks ] || bash "$INSTALLER" "$VAULT" >/dev/null
}

put() { printf '%s' "$3" > "$1/$2"; }
stage() { put "$@" && git -C "$1" add -- "$2"; }
# git_run <dir> <git args...>: sets RC and ERR (stderr+stdout) of a real git command.
git_run() { local d="$1"; shift; ERR=$(git -C "$d" "$@" 2>&1); RC=$?; }
head_of() { git -C "$1" rev-parse HEAD; }

count_line() { grep -Eq "memory-gitleaks-check: .*: [1-9][0-9]* (staged path|pushed object)\(s\) examined" <<<"$ERR"; }
disclaimer() { grep -q 'keyword-and-entropy check, not a proof' <<<"$ERR"; }
no_value() { ! grep -qF "$PLANTED" <<<"$ERR"; }
# refused <file>: non-zero, a line naming the check, the file and the rule, a count, the disclaimer,
# the next step, and never the value.
refused() {
    [ "$RC" -ne 0 ] && grep 'ERROR: memory-gitleaks-check' <<<"$ERR" | grep "$1" | grep -q 'rule github-pat' \
        && count_line && disclaimer && grep -q 'Vault secret scan refused this' <<<"$ERR" && no_value
}
# refused_invalid <pattern>: non-zero, the named reason, the next step, never the value.
refused_invalid() {
    [ "$RC" -ne 0 ] && grep -q "$1" <<<"$ERR" && no_value
}

echo "pre-commit: a planted credential is refused (red)"
t_r1() { setup; stage "$VAULT" leak.md "$LEAK"; local h; h=$(head_of "$VAULT")
    git_run "$VAULT" commit -q -m x; refused leak.md && [ "$(head_of "$VAULT")" = "$h" ]; }
gl_check "R1 terminal commit of a .md file in the primary checkout -> refused, HEAD unchanged" t_r1
t_r2() { setup; stage "$VAULT" config.yaml "$LEAK"; git_run "$VAULT" commit -q -m x; refused config.yaml; }
gl_check "R2 a non-.md file -> refused (every file counts)" t_r2
t_r3() { setup; stage "$VAULT" leak.md "$LEAK"; put "$VAULT" leak.md "clean now"$'\n'
    git_run "$VAULT" commit -q -m x; refused 'leak.md (staged blob)'; }
gl_check "R3 the secret only in the staged blob, working tree cleaned -> refused" t_r3
t_r4() { setup; stage "$WT" leak.md "$LEAK"; local h; h=$(head_of "$WT")
    git_run "$WT" commit -q -m x; refused leak.md && grep -q "$WT" <<<"$ERR" && [ "$(head_of "$WT")" = "$h" ]; }
gl_check "R4 a commit from a vault worktree -> refused (one install covers every worktree)" t_r4
t_r5() { setup; stage "$VAULT" note.md "ok"$'\n'; git -C "$VAULT" commit -q -m clean 2>/dev/null
    put "$VAULT" note.md "$LEAK"; git_run "$VAULT" commit -q -a -m x; refused note.md; }
gl_check "R5 commit -a of a tracked file -> refused" t_r5
t_r6() { setup; stage "$VAULT" leak.md "$LEAK"; git_run "$VAULT" commit -q --amend --no-edit; refused leak.md; }
gl_check "R6 --amend that stages a secret -> refused" t_r6
t_r7() { setup; git -C "$VAULT" checkout -q -b side; stage "$VAULT" leak.md "$LEAK"
    git -C "$VAULT" commit -q --no-verify -m side; git -C "$VAULT" checkout -q main
    git -C "$VAULT" merge -q --squash side >/dev/null 2>&1; git_run "$VAULT" commit -q -m squashed; refused leak.md; }
gl_check "R7 merge --squash of a branch carrying a secret, then commit -> refused" t_r7
# The path is tracked but its edit is NOT staged: only the temporary index git builds for
# `commit -- <path>` (and hands the hook as GIT_INDEX_FILE) holds the secret.
t_ss1() { setup; stage "$VAULT" leak.md "ok"$'\n'; git -C "$VAULT" commit -q -m clean 2>/dev/null
    put "$VAULT" leak.md "$LEAK"; git_run "$VAULT" commit -q -m x -- leak.md; refused leak.md; }
gl_check "SS1 commit -- <path> of an unstaged edit (temporary GIT_INDEX_FILE) -> refused" t_ss1
t_ss2() { setup; stage "$VAULT" leak.md "$LEAK"; git_run "$VAULT" commit -q -m x -- leak.md; refused leak.md; }
gl_check "SS2 git add then commit -- <path> (the claude-settings-sync.sh form) -> refused" t_ss2
t_d4() { setup; put "$VAULT" .gitleaks.toml "$SELF_ALLOW"; git -C "$VAULT" add .gitleaks.toml
    stage "$VAULT" leak.md "$LEAK"; git_run "$VAULT" commit -q -m x; refused leak.md; }
gl_check "D4 a commit that allowlists its own secret -> still refused (HEAD's config is used)" t_d4
t_r8() { setup; stage "$VAULT" '0:x.md' "$LEAK"; put "$VAULT" '0:x.md' "clean now"$'\n'
    git_run "$VAULT" commit -q -m x; refused '0:x.md (staged blob)'; }
gl_check "R8 a staged secret in a file named 0:x.md (git's stage syntax) -> refused" t_r8

echo "pre-push: a pushed credential is refused (red)"
remote_has() { git -C "$REMOTE" rev-parse -q --verify "$1" >/dev/null 2>&1; }
t_pp1() { setup; stage "$VAULT" leak.md "$LEAK"; git -C "$VAULT" commit -q --no-verify -m x
    local before; before=$(git -C "$REMOTE" rev-parse main)
    git_run "$VAULT" push -q origin main; refused 'leak.md (pushed blob [0-9a-f]*):1' && [ "$(git -C "$REMOTE" rev-parse main)" = "$before" ]; }
gl_check "PP1 a commit made with --no-verify is refused on push; the remote is unchanged" t_pp1
t_pp2() { setup; git -C "$VAULT" checkout -q -b side; stage "$VAULT" leak.md "$LEAK"
    git -C "$VAULT" commit -q --no-verify -m side; local c; c=$(head_of "$VAULT"); git -C "$VAULT" checkout -q main
    git -C "$VAULT" cherry-pick --no-verify "$c" >/dev/null 2>&1 || git -C "$VAULT" -c core.hooksPath=/dev/null cherry-pick "$c" >/dev/null 2>&1
    git_run "$VAULT" push -q origin main; refused leak.md; }
gl_check "PP2 a cherry-picked commit carrying a secret -> push refused" t_pp2
t_pp3() { setup; git -C "$VAULT" checkout -q -b fresh; stage "$VAULT" leak.md "$LEAK"
    git -C "$VAULT" commit -q --no-verify -m x; git_run "$VAULT" push -q origin fresh; refused leak.md && ! remote_has refs/heads/fresh; }
gl_check "PP3 a new branch carrying a secret -> push refused, branch not created" t_pp3
t_pp4() { setup; put "$VAULT" .gitleaks.toml "$SELF_ALLOW"; git -C "$VAULT" add .gitleaks.toml
    stage "$VAULT" leak.md "$LEAK"; git -C "$VAULT" commit -q --no-verify -m x
    git_run "$VAULT" push -q origin main; refused leak.md && grep -q 'config: origin HEAD' <<<"$ERR"; }
gl_check "PP4 a pushed commit that allowlists its own secret -> refused (the remote's config is used)" t_pp4
t_pp5() { setup; stage "$WT" leak.md "$LEAK"; git -C "$WT" commit -q --no-verify -m x
    git_run "$WT" push -q origin wt; refused leak.md; }
gl_check "PP5 a push from a vault worktree -> refused" t_pp5

# What `git log -p` hides from a patch scan: these must still be refused at push.
t_pp6() { setup; printf '\0\n%s' "$LEAK" > "$VAULT/bin.md"; git -C "$VAULT" add bin.md
    git -C "$VAULT" commit -q --no-verify -m x; git_run "$VAULT" push -q origin main; refused bin.md; }
gl_check "PP6 a file git treats as binary (NUL byte) -> push refused" t_pp6
t_pp7() { setup; printf '*.md -diff\n' > "$VAULT/.gitattributes"; stage "$VAULT" leak.md "$LEAK"; git -C "$VAULT" add .gitattributes
    git -C "$VAULT" commit -q --no-verify -m x; git_run "$VAULT" push -q origin main; refused leak.md; }
gl_check "PP7 a file hidden from diffs by .gitattributes (-diff) -> push refused" t_pp7
t_pp8() { setup; git -C "$VAULT" checkout -q -b side; stage "$VAULT" s.md "side"$'\n'; git -C "$VAULT" commit -q -m side
    git -C "$VAULT" checkout -q main; stage "$VAULT" m.md "main"$'\n'; git -C "$VAULT" commit -q -m main
    git -C "$VAULT" merge -q --no-ff --no-commit side >/dev/null 2>&1; stage "$VAULT" evil.md "$LEAK"
    git -C "$VAULT" commit -q --no-verify -m merge; git_run "$VAULT" push -q origin main; refused evil.md; }
gl_check "PP8 a secret added in a merge commit's own resolution -> push refused" t_pp8
t_pp9() { setup; git -C "$VAULT" tag -a v1 -m "$LEAK"; git_run "$VAULT" push -q origin v1
    refused 'tag message' && ! remote_has refs/tags/v1; }
gl_check "PP9 an annotated tag whose message holds a secret -> push refused" t_pp9
t_pp10() { setup; local b; b=$(printf '%s' "$LEAK" | git -C "$VAULT" hash-object -w --stdin); git -C "$VAULT" tag lt "$b"
    git_run "$VAULT" push -q origin lt; refused 'pushed blob' && ! remote_has refs/tags/lt; }
gl_check "PP10 a lightweight tag pointing straight at a secret blob -> push refused" t_pp10
t_pp11() { setup; stage "$VAULT" note.md "ok"$'\n'; git -C "$VAULT" commit -q -m "$LEAK" 2>/dev/null
    git_run "$VAULT" push -q origin main; refused 'commit message'; }
gl_check "PP11 a commit message holding a secret -> push refused" t_pp11
t_pp12() { setup; stage "$VAULT" l.md "$LEAK"; git -C "$VAULT" commit -q --no-verify -m add
    git -C "$VAULT" rm -q l.md; git -C "$VAULT" commit -q -m rm; git_run "$VAULT" push -q origin main
    refused 'l.md (pushed blob' && grep -q '(2 commit(s)' <<<"$ERR"; }
gl_check "PP12 a secret added then removed within the pushed range -> push refused (the whole range is scanned)" t_pp12
t_pp13() { setup; git -C "$VAULT" checkout -q -b leak; stage "$VAULT" l.md "$LEAK"; git -C "$VAULT" commit -q --no-verify -m x
    MEMORY_GITLEAKS_CHECK=off git -C "$VAULT" push -q origin leak 2>/dev/null; git -C "$VAULT" checkout -q main
    git -C "$REMOTE" branch -D leak >/dev/null; git -C "$REMOTE" reflog expire --expire=now --all; git -C "$REMOTE" gc -q --prune=now
    git -C "$VAULT" branch again leak; git_run "$VAULT" push -q origin again; refused l.md && ! remote_has refs/heads/again; }
gl_check "PP13 a branch purged from the remote and pushed again (stale tracking ref) -> push refused" t_pp13
t_pp14() { setup; put "$VAULT" .gitleaks.toml "$SELF_ALLOW"; git -C "$VAULT" add .gitleaks.toml
    stage "$VAULT" leak.md "$LEAK"; git -C "$VAULT" commit -q --no-verify -m x
    git_run "$VAULT" push -q "$REMOTE" main; refused leak.md; }
gl_check "PP14 a self-allowlisting commit pushed to the remote by path, not by name -> refused (the remote's config)" t_pp14
t_pp15() { setup; git -C "$VAULT" push -q --no-verify origin main 2>/dev/null
    local other="$T/other$n"; git clone -q "$REMOTE" "$other" 2>/dev/null; stage "$other" o.md "o"$'\n'
    git -C "$other" commit -q -m o; git -C "$other" push -q origin main 2>/dev/null
    stage "$VAULT" note.md "ok"$'\n'; git -C "$VAULT" commit -q -m x; git_run "$VAULT" push -q origin HEAD:refs/heads/side
    refused_invalid 'fetch origin first'; }
gl_check "PP15 the remote's HEAD is not in this clone -> push refused with 'fetch first', not scanned on a guessed config" t_pp15

echo "clean content passes (green)"
t_g1() { setup; stage "$VAULT" placeholders.md "$PLACEHOLDERS"; git_run "$VAULT" commit -q -m x
    [ "$RC" -eq 0 ] && count_line && disclaimer && git -C "$VAULT" cat-file -e HEAD:placeholders.md; }
gl_check "G1 a commit with only the two allowlisted placeholders passes, with count line and disclaimer" t_g1
t_ppg() { setup; stage "$VAULT" placeholders.md "$PLACEHOLDERS"; git -C "$VAULT" commit -q -m x 2>/dev/null
    git_run "$VAULT" push -q origin main
    [ "$RC" -eq 0 ] && count_line && disclaimer && [ "$(git -C "$REMOTE" rev-parse main)" = "$(head_of "$VAULT")" ]; }
gl_check "PP-G a clean push passes, with count line and disclaimer" t_ppg
t_z1() { setup; git -C "$VAULT" rm -q README; git_run "$VAULT" commit -q -m x
    [ "$RC" -eq 0 ] && grep -q '0 staged path(s) examined — ZERO-INPUT-OK' <<<"$ERR" && disclaimer \
        && grep -q '^ *# ZERO-INPUT-OK: ' "$REAL_CHECK"; }
check "Z1 a deletion-only commit passes, printing its ZERO-INPUT-OK reason (declared in the source)" t_z1
t_z2() { setup; git -C "$VAULT" push -q --no-verify origin main:gone 2>/dev/null; git_run "$VAULT" push -q origin :gone
    [ "$RC" -eq 0 ] && grep -q '0 pushed object(s) examined — ZERO-INPUT-OK' <<<"$ERR" && ! remote_has refs/heads/gone; }
gl_check "Z2 a branch-delete push passes, printing its ZERO-INPUT-OK reason" t_z2
t_k1() { setup; stage "$VAULT" leak.md "$LEAK"; ERR=$(MEMORY_GITLEAKS_CHECK=off git -C "$VAULT" commit -q -m x 2>&1); RC=$?
    [ "$RC" -eq 0 ] && grep -q 'DISABLED by MEMORY_GITLEAKS_CHECK=off' <<<"$ERR"; }
check "K1 the kill switch lets the commit through and says DISABLED" t_k1

echo "a missing prerequisite never passes silently (invalid runs are refused)"
t_p1() { setup; stage "$VAULT" leak.md "$LEAK"
    ERR=$(PATH=/usr/bin:/bin MEMORY_GITLEAKS_PATH_PREPEND='' git -C "$VAULT" commit -q -m x 2>&1); RC=$?
    refused_invalid 'gitleaks not installed'; }
check "P1 no gitleaks anywhere on PATH -> commit refused, saying so" t_p1
t_p3() { setup; stage "$VAULT" leak.md "$LEAK"
    ERR=$(PATH=/usr/bin:/bin MEMORY_GITLEAKS_PATH_PREPEND="$GITLEAKS_DIR" git -C "$VAULT" commit -q -m x 2>&1); RC=$?
    refused leak.md; }
gl_check "P3 a GUI-like PATH without Homebrew -> the prepend still finds gitleaks and refuses the secret" t_p3
t_p2() { setup; git -C "$VAULT" rm -q .gitleaks.toml; git -C "$VAULT" commit -q --no-verify -m rm
    stage "$VAULT" leak.md "$LEAK"; git_run "$VAULT" commit -q -m x; refused_invalid 'no .gitleaks.toml committed at HEAD'; }
check "P2 no .gitleaks.toml at HEAD -> commit refused rather than scanned on defaults" t_p2
t_p4() { setup; git -C "$VAULT" rm -q .gitleaks.toml; git -C "$VAULT" commit -q --no-verify -m rm
    git -C "$VAULT" push -q --no-verify origin main 2>/dev/null; git -C "$VAULT" fetch -q origin
    stage "$VAULT" note.md "ok"$'\n'; git -C "$VAULT" commit -q --no-verify -m x
    git_run "$VAULT" push -q origin main; refused_invalid "no .gitleaks.toml on origin's HEAD"; }
check "P4 no .gitleaks.toml on the remote or at HEAD -> push refused" t_p4
t_v1() { setup; mkdir -p "$T/fake$n"; printf '#!/bin/sh\necho "[]" > /dev/null\nexit 1\n' > "$T/fake$n/gitleaks"
    chmod +x "$T/fake$n/gitleaks"; stage "$VAULT" note.md "ok"$'\n'
    ERR=$(PATH="$T/fake$n:/usr/bin:/bin" MEMORY_GITLEAKS_PATH_PREPEND='' git -C "$VAULT" commit -q -m x 2>&1); RC=$?
    refused_invalid 'gitleaks failed' && grep -q 'invalid scan run' <<<"$ERR"; }
check "V1 gitleaks exits 1 with no findings (a crash) -> refused, not read as a finding or a pass" t_v1
t_v2() { setup; mkdir -p "$T/fake$n"; printf '#!/bin/sh\nexit 1\n' > "$T/fake$n/gitleaks"; chmod +x "$T/fake$n/gitleaks"
    stage "$VAULT" note.md "ok"$'\n'; git -C "$VAULT" commit -q --no-verify -m x; local before; before=$(git -C "$REMOTE" rev-parse main)
    ERR=$(PATH="$T/fake$n:/usr/bin:/bin" MEMORY_GITLEAKS_PATH_PREPEND='' git -C "$VAULT" push -q origin main 2>&1); RC=$?
    refused_invalid 'gitleaks failed' && ! grep -q 'Traceback' <<<"$ERR" && ! count_line \
        && [ "$(git -C "$REMOTE" rev-parse main)" = "$before" ]; }
check "V2 gitleaks crashes during pre-push -> refused, no count line claims a scan, no traceback" t_v2
t_p5() { case "$GITLEAKS_DIR" in /opt/homebrew/bin|/usr/local/bin) ;; *) return 0 ;; esac
    setup; stage "$VAULT" leak.md "$LEAK"
    ERR=$(env -u MEMORY_GITLEAKS_PATH_PREPEND PATH=/usr/bin:/bin git -C "$VAULT" commit -q -m x 2>&1); RC=$?
    refused leak.md; }
gl_check "P5 the DEFAULT prepend finds a Homebrew gitleaks from a GUI-like PATH" t_p5
t_sh1() { setup; stage "$VAULT" note.md "ok"$'\n'
    ERR=$(MEMORY_GITLEAKS_COMMIT_CHECK_UNDER_TEST="$T/does-not-exist.sh" git -C "$VAULT" commit -q -m x 2>&1); RC=$?
    refused_invalid 'vault git hook: .* missing — nothing was scanned'; }
check "SH1 the hook's target is missing (a container, a moved checkout) -> refused, not silently skipped" t_sh1

echo "installer"
t_i1() { setup nohooks; local a b; bash "$INSTALLER" --check "$VAULT" >/dev/null 2>&1; a=$?
    bash "$INSTALLER" "$VAULT" >/dev/null 2>&1; bash "$INSTALLER" --check "$VAULT" >/dev/null 2>&1; b=$?
    [ "$a" -eq 1 ] && [ "$b" -eq 0 ]; }
gl_check "I1 --check exits 1 before install and 0 after" t_i1
t_i2() { setup nohooks; local hooks="$VAULT/.git/hooks"; printf '#!/bin/sh\necho foreign\n' > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"; bash "$INSTALLER" "$VAULT" >/dev/null 2>&1
    local out; out=$(bash "$INSTALLER" "$VAULT" 2>&1)
    ls "$hooks"/pre-commit.bak.* >/dev/null 2>&1 && grep -q foreign "$hooks"/pre-commit.bak.* \
        && grep -q ': 0 hook(s) changed' <<<"$out" && ! grep -q '@CHECK@' "$hooks/pre-commit"; }
check "I2 install backs up a foreign hook, and a second run changes nothing" t_i2
t_i3() { setup nohooks; git -C "$VAULT" config core.hooksPath .githooks; local rc=0
    bash "$INSTALLER" "$VAULT" >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 1 ] && [ ! -e "$VAULT/.git/hooks/pre-commit" ] && ! bash "$INSTALLER" --check "$VAULT" >/dev/null 2>&1; }
check "I3 a vault with core.hooksPath set is refused by install and flagged by --check" t_i3
t_i4() { setup; chmod -x "$VAULT/.git/hooks/pre-push"; local out; out=$(bash "$INSTALLER" --check "$VAULT" 2>&1)
    [ $? -eq 1 ] && grep -q 'pre-push is not executable' <<<"$out"; }
gl_check "I4 --check flags a hook that is not executable" t_i4
t_i5() { setup; printf '# edited\n' >> "$VAULT/.git/hooks/pre-commit"; local out; out=$(bash "$INSTALLER" --check "$VAULT" 2>&1)
    [ $? -eq 1 ] && grep -q 'pre-commit differs' <<<"$out"; }
gl_check "I5 --check flags a hook that drifted from the template" t_i5
t_i6() { local out; out=$(bash "$INSTALLER" --check "$T/not-a-repo" 2>&1) && grep -q 'not a git repository' <<<"$out"; }
check "I6 a vault path that is not a git repo is a visible no-op, not an error" t_i6
t_i7() { ! grep -rq '/Users/' "$PKG/git-hooks/vault/"; }
check "I7 the committed hook templates hold no absolute user path (public repo)" t_i7
# claude/.gitignore is deny-all with an allowlist: an un-admitted directory never gets committed, and a
# fresh clone's installer would then have no templates to copy.
t_i8() { local f; for f in "$PKG"/git-hooks/vault/pre-commit "$PKG"/git-hooks/vault/pre-push \
        "$PKG"/scripts/install-vault-hooks.sh "$PKG"/scripts/memory-gitleaks-commit-check.sh; do
        git -C "$PKG" check-ignore -q "$f" && { echo "    ignored: $f"; return 1; }
    done; return 0; }
if git -C "$PKG" rev-parse --git-dir >/dev/null 2>&1; then
    check "I8 the hook templates and scripts are not git-ignored (they reach a fresh clone)" t_i8
fi

echo "the value never reaches output"
t_s1() { setup; stage "$VAULT" leak.md "$LEAK"; git_run "$VAULT" commit -q -m x; local a="$ERR"
    git -C "$VAULT" commit -q --no-verify -m x; git_run "$VAULT" push origin main
    ! grep -qF "$PLANTED" <<<"$a$ERR"; }
gl_check "S1 neither a refused commit nor a refused push prints the planted value" t_s1

[ -z "${NO_BASELINE:-}" ] && {
    echo "baseline: what the gate prevents"
    t_b0() { setup nohooks; stage "$VAULT" leak.md "$LEAK"; git -C "$VAULT" commit -q -m x 2>/dev/null \
        && git -C "$VAULT" cat-file -e HEAD:leak.md; }
    check "B0 with no hook installed the same commit lands (R1's red baseline)" t_b0
}

printf '\nSUITE_RESULT pass=%d fail=%d skip=%d\n' "$pass" "$failed" "$skipped"
[ "$failed" -eq 0 ] && [ "$pass" -gt 0 ] && [ "$glpass" -gt 0 ]
