#!/usr/bin/env bash
# memory-cleanup.test.sh — the staleness report scans Claude Code's project memory dirs.
# Runs against a throwaway HOME. Run: bash claude/tests/memory-cleanup.test.sh
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/memory-cleanup-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
SCRIPT="$PKG/scripts/memory-cleanup.py"

pass=0; failed=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; fi; }

seed() { # seed <slug> <file> <last_accessed or "">
    local mem="$HOME/.claude/projects/$1/memory"; mkdir -p "$mem"
    if [ -n "$3" ]; then
        printf -- '---\nname: %s\nlast_accessed: %s\n---\nbody\n' "$2" "$3" > "$mem/$2.md"
    else
        printf -- '---\nname: %s\n---\nbody\n' "$2" > "$mem/$2.md"
    fi
}

old="$(date -v-200d +%F 2>/dev/null || date -d '200 days ago' +%F)"
new="$(date +%F)"
seed -src-a stale-one "$old"
seed -src-a fresh-one "$new"
seed -src-b never-one ""

out="$(python3 "$SCRIPT")"; rc=$?
check "default scan exits 0" test "$rc" -eq 0
check "scans every project memory dir" bash -c 'grep -q -- "-src-a/memory" <<<"$1" && grep -q -- "-src-b/memory" <<<"$1"' _ "$out"
check "reports the stale file" grep -q "stale-one.md" <<<"$out"
check "reports the never-accessed file" grep -q "never-one.md" <<<"$out"

out="$(python3 "$SCRIPT" --dir "$HOME/.claude/projects/-src-b/memory")"
check "--dir limits the scan" bash -c '! grep -q -- "-src-a" <<<"$1"' _ "$out"

python3 "$SCRIPT" --dir "$HOME/nope" >/dev/null; rc=$?
check "missing --dir exits 1" test "$rc" -eq 1

python3 "$SCRIPT" --archive >/dev/null
check "--archive moves only stale files" bash -c 'test -f "$1/stale/stale-one.md" && test -f "$1/fresh-one.md"' _ "$HOME/.claude/projects/-src-a/memory"

rm -rf "$HOME/.claude/projects"; mkdir -p "$HOME/.claude/projects"
python3 "$SCRIPT" >/dev/null; rc=$?
check "no memory dirs exits 2" test "$rc" -eq 2

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
