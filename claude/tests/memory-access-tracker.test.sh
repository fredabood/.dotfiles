#!/usr/bin/env bash
# memory-access-tracker.test.sh — the hook must find the auto-memory dir Claude Code actually uses.
# Runs against a throwaway HOME. Run: bash claude/tests/memory-access-tracker.test.sh
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/memory-tracker-test.XXXXXX")"
trap 'rm -rf "$T"; rm -f /tmp/.memory-access-tracked-*"$ID"*' EXIT
export HOME="$T/home"
ID="t$$"

pass=0; failed=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; fi; }

# track <project dir> <slug Claude Code gives it>: seed a memory file there, run the hook.
track() {
    local mem="$HOME/.claude/projects/$2/memory"
    mkdir -p "$mem"
    printf -- '---\nname: probe\n---\nbody\n' > "$mem/probe.md"
    CLAUDE_PROJECT_DIR="$1" bash "$PKG/hooks/memory-access-tracker.sh"
    grep -q '^last_accessed: ' "$mem/probe.md"
}

# Claude Code replaces every non-alphanumeric character, not just "/": a worktree under
# <repo>/.claude/worktrees/ gets "--claude-worktrees-", and "_" becomes "-" too.
check "plain repo path" track "/src/$ID/app" "-src-$ID-app"
check "in-repo worktree (dot dir)" track "/src/$ID/app/.claude/worktrees/wt" "-src-$ID-app--claude-worktrees-wt"
check "underscore in a worktree name" track "/src/$ID/app/.claude/worktrees/wt_2" "-src-$ID-app--claude-worktrees-wt-2"

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
