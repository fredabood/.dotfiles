#!/usr/bin/env bash
# install-vault-hooks.sh — install the memory vault's git pre-commit and pre-push secret-scan hooks
# (LAB-2857), or check that they are installed.
#
#   install-vault-hooks.sh [--check] [<vault>]          <vault> defaults to $MEMORY_VAULT_PATH,
#                                                       then ~/Repositories/memory
#
# Each hook is a short shim from claude/git-hooks/vault/, COPIED into the vault's common git dir
# (`git rev-parse --git-common-dir`/hooks), so one install covers the primary checkout and every
# worktree. The absolute path of memory-gitleaks-commit-check.sh is written into the copy at install
# time; the template in this public repo holds only the @CHECK@ placeholder. A copy is used instead of
# core.hooksPath or a symlink because git silently skips a hook whose target is missing: a copied
# shim with a missing target refuses the commit instead.
#
# Install: idempotent. A foreign or outdated hook is moved to <hook>.bak.<timestamp>, never deleted.
# Refuses (exit 1) when core.hooksPath is set for the vault, since git would never run the copies.
#
# --check: exit 1, naming each problem, when a hook is missing, differs from the rendered template,
# is not executable, core.hooksPath is set, or gitleaks cannot be found. Changes nothing.
#
# Either mode exits 0 with a note when <vault> is not a git repository: there is nothing to gate.
# Written for macOS /bin/bash 3.2.
set -uo pipefail

TAG="install-vault-hooks"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TEMPLATES="$(cd "$HERE/../git-hooks/vault" && pwd -P)"
CHECK_SCRIPT="$HERE/memory-gitleaks-commit-check.sh"
HOOKS="pre-commit pre-push"

MODE=install
if [ "${1:-}" = "--check" ]; then MODE=check; shift; fi
case "${1:-}" in -*) printf '%s: unknown option %s\n' "$TAG" "$1" >&2; exit 2 ;; esac
VAULT="${1:-${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}}"

if ! git -C "$VAULT" rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s: %s is not a git repository — no vault hooks to %s\n' "$TAG" "$VAULT" "$MODE"
    exit 0
fi
COMMON="$(git -C "$VAULT" rev-parse --path-format=absolute --git-common-dir)" || exit 2
DEST="$COMMON/hooks"

# Escape the replacement: a checkout path holding \, & or | would otherwise corrupt the baked path.
CHECK_ESC="$(printf '%s' "$CHECK_SCRIPT" | sed 's/[\\&|]/\\&/g')"
render() { sed "s|@CHECK@|$CHECK_ESC|" "$TEMPLATES/$1"; }

PROBLEMS=0
problem() { printf '  ! %s\n' "$*" >&2; PROBLEMS=$((PROBLEMS + 1)); }

HP="$(git -C "$VAULT" config --get core.hooksPath 2>/dev/null || true)"
if [ -n "$HP" ]; then
    problem "core.hooksPath is set to $HP for $VAULT — git would never run the vault hooks; unset it"
    if [ "$MODE" = install ]; then
        printf '%s: refusing to install into %s\n' "$TAG" "$DEST" >&2
        exit 1
    fi
fi

if [ "$MODE" = check ]; then
    PREPEND="${MEMORY_GITLEAKS_PATH_PREPEND-/opt/homebrew/bin:/usr/local/bin}"
    [ -n "$PREPEND" ] && PATH="$PREPEND:$PATH"
    command -v gitleaks >/dev/null 2>&1 || problem "gitleaks not installed (brew install gitleaks) — every vault commit will be refused"
    for h in $HOOKS; do
        f="$DEST/$h"
        if [ ! -e "$f" ]; then problem "$f is missing"; continue; fi
        render "$h" | cmp -s - "$f" || problem "$f differs from claude/git-hooks/vault/$h (outdated or foreign)"
        [ -x "$f" ] || problem "$f is not executable — git skips it"
    done
    if [ "$PROBLEMS" -gt 0 ]; then
        printf '%s: %s: %s problem(s) — run %s/install-vault-hooks.sh\n' "$TAG" "$VAULT" "$PROBLEMS" "$HERE" >&2
        exit 1
    fi
    printf '%s: %s: pre-commit and pre-push installed and current\n' "$TAG" "$VAULT"
    exit 0
fi

mkdir -p "$DEST" || exit 2
STAMP="$(date +%Y%m%d_%H%M%S)"
CHANGED=0
for h in $HOOKS; do
    f="$DEST/$h"
    tmp="$DEST/.$h.new.$$"
    render "$h" >"$tmp" || { rm -f "$tmp"; exit 2; }
    chmod 755 "$tmp"
    if [ -e "$f" ] && cmp -s "$tmp" "$f" && [ -x "$f" ]; then
        rm -f "$tmp"
        continue
    fi
    if [ -e "$f" ] || [ -L "$f" ]; then
        mv "$f" "$f.bak.$STAMP" && printf '  backed up %s → %s\n' "$f" "$f.bak.$STAMP"
    fi
    mv "$tmp" "$f" || exit 2
    printf '  installed %s\n' "$f"
    CHANGED=$((CHANGED + 1))
done
printf '%s: %s: %s hook(s) changed\n' "$TAG" "$VAULT" "$CHANGED"
exit 0
