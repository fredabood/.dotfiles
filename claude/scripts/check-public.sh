#!/usr/bin/env bash
# check-public.sh — keep secrets and private information out of the PUBLIC dotfiles repo.
#
#   check-public.sh --staged     scan files staged for commit (the .githooks/pre-commit entry point)
#   check-public.sh <path>...    scan working-tree files under the given repo-relative paths
#
# Two layers:
#   1. gitleaks — credentials (tokens, keys, JWTs). Required; missing gitleaks fails closed.
#   2. a PRIVATE denylist — hostnames, domains, client names, addresses: things that are not
#      credentials, so gitleaks cannot know them. The list lives in the memory vault at
#      $MEMORY_VAULT_PATH/personal/claude/denylist.txt, because a denylist committed here would
#      publish exactly the strings it exists to keep out. One extended regex per line, matched
#      case-insensitively on word boundaries; blank lines and # comments are ignored.
#      A missing denylist is warned about, not fatal, so a fresh clone can still commit.
#
# Matching uses `git grep`, not `grep`: the grep on PATH varies by machine (ugrep, BSD, GNU)
# and they disagree on regex edge cases.
set -euo pipefail

REPO="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
VAULT="${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}"
DENYLIST="${DOTFILES_DENYLIST:-$VAULT/personal/claude/denylist.txt}"

[ $# -gt 0 ] || { printf 'usage: %s --staged | <path>...\n' "$0" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-public.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail=0
cd "$REPO"

if ! command -v gitleaks >/dev/null 2>&1; then
    printf 'check-public: gitleaks not installed (brew install gitleaks) — refusing to pass unchecked\n' >&2
    exit 1
fi

if [ "$1" = "--staged" ]; then
    if ! gitleaks git --pre-commit --staged --redact --no-banner --log-level warn "$REPO"; then
        printf 'check-public: gitleaks found a credential in the staged changes\n' >&2
        fail=1
    fi
else
    for path in "$@"; do
        if ! gitleaks dir --redact --no-banner --log-level warn "$path"; then
            printf 'check-public: gitleaks found a credential under %s\n' "$path" >&2
            fail=1
        fi
    done
fi

if [ ! -f "$DENYLIST" ]; then
    printf 'check-public: warning: private denylist not found at %s — only credentials were checked\n' "$DENYLIST" >&2
else
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$DENYLIST" > "$TMP/patterns"
    if [ -s "$TMP/patterns" ]; then
        if [ "$1" = "--staged" ]; then
            git diff --cached --name-only -z --diff-filter=ACMR > "$TMP/files"
            if [ -s "$TMP/files" ] && xargs -0 git grep --cached -n -I -i -w -E -f "$TMP/patterns" -- < "$TMP/files"; then
                printf 'check-public: staged changes contain private information (matched the vault denylist above)\n' >&2
                fail=1
            fi
        elif git grep --no-index -n -I -i -w -E -f "$TMP/patterns" -- "$@"; then
            printf 'check-public: private information found (matched the vault denylist above)\n' >&2
            fail=1
        fi
    fi
fi

[ "$fail" -eq 0 ] && printf 'check-public: clean\n'
exit "$fail"
