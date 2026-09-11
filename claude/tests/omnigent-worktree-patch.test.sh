#!/usr/bin/env bash
# omnigent-worktree-patch.test.sh — the patch against a synthetic uv tool dir; never touches the
# real Omnigent install. Run: bash claude/tests/omnigent-worktree-patch.test.sh
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="$PKG/scripts/omnigent-worktree-patch"
T="$(mktemp -d "${TMPDIR:-/tmp}/omnigent-patch-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export UV_TOOL_DIR="$T"
MOD="$T/omnigent/lib/python3.12/site-packages/omnigent/host"
mkdir -p "$MOD"
F="$MOD/git_worktree.py"

pass=0; failed=0
check() { local name="$1"; shift; if "$@"; then pass=$((pass + 1)); printf '  ok   %s\n' "$name"; else failed=$((failed + 1)); printf '  FAIL %s\n' "$name"; fi; }
exits() { local want="$1"; shift; "$@" >/dev/null 2>&1; [ "$?" -eq "$want" ]; }
lacks() { ! grep -q -- "$1" "$2"; }

# The shape of the upstream function: only the anchor line matters.
cat > "$F" <<'PY'
def _pick_worktree_dir(repo_root, branch_name):
    root = Path(repo_root)
    base_dir = root.parent / f"{root.name}-worktrees"
    return base_dir / branch_name
PY

check "--check on an unpatched install exits 1" exits 1 "$PATCH" --check
check "patch exits 0" exits 0 "$PATCH"
check "worktrees now nest in the repo" grep -q 'base_dir = root / ".claude" / "worktrees"' "$F"
check "sibling path gone" lacks '-worktrees"' "$F"
cp "$F" "$T/once"
check "second run exits 0" exits 0 "$PATCH"
check "second run changes nothing" cmp -s "$F" "$T/once"
check "--check on a patched install exits 0" exits 0 "$PATCH" --check

printf 'def other():\n    return 1\n' > "$F"
check "anchor gone (upstream changed) exits 2" exits 2 "$PATCH"
check "file left untouched when the anchor is gone" grep -q 'def other' "$F"

rm -f "$F"
check "module missing exits 2" exits 2 "$PATCH"

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
