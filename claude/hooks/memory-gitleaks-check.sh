#!/usr/bin/env bash
# memory-gitleaks-check.sh — PreToolUse: scan what a memory-vault commit will contain with gitleaks,
# and block the commit on a finding (LAB-2457).
#
# WHY: LAB-2288 redacted 12 credentials, four of them live, that had sat in vault notes for about
# six months. The vault is not an ordinary private repo: sync-memory-vault.py chunks every note into
# public.memories every 15 minutes and memory_search serves it, so a credential committed to a note
# is readable by every agent that queries memory within a quarter of an hour. The periodic history
# scan finds these after the fact; this gate stops the next one at commit time.
#
# HOW: the repo and the file set are resolved by the resolver shared with memory-frontmatter-check.sh,
# hooks/lib/vault-hook-resolver.sh (LAB-2858; tested by claude/tests/vault-hook-resolver.test.sh).
# The repo comes from the command (git -C, a leading cd, else the payload cwd); vault identity is
# the git common dir, equal for the primary checkout and every worktree; the file set is the index
# plus every earlier `git add` in the same command, `commit -a`, `-i` and pathspecs. Renamed and
# typechanged files are listed as additions (--no-renames, ACMT) in both gates. The one difference
# left between them is the file set: every file counts here, only .md files in the frontmatter gate.
# The scan itself is claude/scripts/memory-gitleaks-scan.sh (0 = clean, 1 = finding, 2 = invalid
# run). Claude Code blocks a PreToolUse call only on exit 2, so this hook maps 1 AND 2 to 2.
#
# CONFIG: HEAD's committed .gitleaks.toml, written to a temp file and passed with -c. A commit
# therefore cannot allowlist itself: an allowlist entry has to land in an earlier commit.
#
# EXIT CODES: 0 = allow (not a commit, not the vault, clean, a zero-content commit, or a visible
# skip); 2 = block (a finding, gitleaks or the committed config missing, gitleaks failed, the
# resolver lib missing, incomplete or failing to load, or — for a vault commit — the list of files
# the commit will contain could not be computed; LAB-2858). The lib refusals come before the vault
# is identified, so they block any Bash call whose payload mentions both git and commit.
#
# KILL SWITCH (human only): MEMORY_GITLEAKS_CHECK=off disables the gate and prints a DISABLED line
# on stderr for every commit it waves through.
#
# LIMITS:
#   - gitleaks is a keyword-and-entropy check, not a proof. Its default stopword allowlist can
#     suppress a real credential; every run says so.
#   - Only commits made through Claude Code's Bash tool are seen here (owner ruling D5). Commits
#     and pushes made elsewhere (a terminal, Obsidian, claude-settings-sync.sh) are gated by the
#     vault's own git hooks, claude/scripts/memory-gitleaks-commit-check.sh (LAB-2857); vault-sync's
#     planned auto-commit is to call that script explicitly (fredabood/homelab#2548).
#   - Interactive or file-driven adds and commits, and pathspecs using $, backticks or braces, are
#     a visible "skipped" line, as in the frontmatter hook.
#
# If you change this file, prove it with claude/tests/memory-gitleaks-check.test.sh AND the live
# probe in fredabood/homelab#2457 (a runtime-generated token staged in a throwaway vault worktree
# must be BLOCKED) — never by observing that the hook ran without error.

set -euo pipefail

TAG="memory-gitleaks-check"
INPUT=$(cat)
if [[ "${MEMORY_GITLEAKS_CHECK:-}" == off ]]; then
  if [[ "$INPUT" == *commit* ]]; then
    echo "$TAG: DISABLED by MEMORY_GITLEAKS_CHECK=off — no secret scan ran for this commit." >&2
  fi
  exit 0
fi
if [[ "$INPUT" != *git* || "$INPUT" != *commit* ]]; then
  exit 0
fi

skip() {
  echo "$TAG: skipped — $1" >&2
}

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCAN="${MEMORY_GITLEAKS_CHECK_UNDER_TEST:-$HERE/../scripts/memory-gitleaks-scan.sh}"
LIB="$HERE/lib/vault-hook-resolver.sh"
# The shared resolver (resolve_targets, common_dir, commit_files; LAB-2858). Every way it can fail to
# load blocks, because this hook cannot judge a commit without it.
# [ -r ] first: under bash 3.2 `source missing || guard` never runs the guard (exit 1 = allow).
[ -r "$LIB" ] || { echo "$TAG: BLOCKED — resolver lib missing at $LIB; restore claude/hooks/lib in dotfiles" >&2; exit 2; }
# Any exit while loading (a syntax error, or a failing top-level line under set -e, which exits 1
# on bash 3.2) becomes 2.
trap 'echo "$TAG: BLOCKED — resolver lib at $LIB failed to load" >&2; exit 2' EXIT
# shellcheck source=lib/vault-hook-resolver.sh
. "$LIB"
trap - EXIT
if [ "${VAULT_HOOK_RESOLVER_API:-}" != 1 ] || ! declare -F resolve_targets common_dir commit_files >/dev/null; then
  echo "$TAG: BLOCKED — resolver lib at $LIB is incomplete" >&2; exit 2
fi

TARGETS=$(resolve_targets "$INPUT") || {
  skip "could not resolve the commit's repository (python3 failed)"
  exit 0
}
if [[ -z "$TARGETS" ]]; then
  exit 0
fi

MEMORY_DIR="${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}"
VAULT_COMMON=""

VAULT_TOPS=()
VAULT_DIRS=()
VAULT_SPECS=()
while IFS=$'\t' read -r kind value spec; do
  if [[ "$kind" == SKIP ]]; then
    skip "$value"
    continue
  fi
  if ! TOP=$(git -C "$value" rev-parse --show-toplevel 2>/dev/null) || [[ -z "$TOP" ]]; then
    skip "$value is not in a git work tree"
    continue
  fi
  if [[ -z "$VAULT_COMMON" ]] && ! VAULT_COMMON=$(common_dir "$MEMORY_DIR"); then
    VAULT_COMMON=""
    skip "the vault at $MEMORY_DIR is not a git repository, so nothing could be matched against it"
    exit 0
  fi
  if [[ "$(common_dir "$TOP" || true)" == "$VAULT_COMMON" ]]; then
    VAULT_TOPS+=("$TOP")
    VAULT_DIRS+=("$value")
    VAULT_SPECS+=("$spec")
  fi
done <<<"$TARGETS"

if [[ ${#VAULT_TOPS[@]} -eq 0 ]]; then
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/memory-gitleaks-check.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Every line goes to stderr: on exit 2 Claude Code hands the model stderr only (LAB-1996).
BLOCK=0
for i in "${!VAULT_TOPS[@]}"; do
  TOP="${VAULT_TOPS[$i]}"

  if ! FILE_LINES=$(commit_files "$TOP" "${VAULT_DIRS[$i]}" "${VAULT_SPECS[$i]}" 0 no ACMT "file"); then
    # A vault commit whose file list is unknown is blocked, not passed unchecked (LAB-2858, OD1).
    echo "$TAG: $TOP: could not compute the files this commit will contain (python3 failed) — blocking rather than passing unchecked" >&2
    BLOCK=1
    continue
  fi
  LIST="$WORK/list.$i"
  : >"$LIST"
  COUNT=0
  SKIPPED=0
  while IFS=$'\t' read -r kind value; do
    if [[ "$kind" == SKIP ]]; then
      skip "$value"
      SKIPPED=1
    elif [[ "$kind" == FILE ]]; then
      printf '%s\0' "$value" >>"$LIST"
      COUNT=$((COUNT + 1))
    fi
  done <<<"$FILE_LINES"

  if [[ $COUNT -eq 0 ]]; then
    if [[ $SKIPPED -eq 1 ]]; then
      echo "$TAG: $TOP: 0 staged path(s) examined — the skipped part above was not scanned" >&2
      continue
    fi
    # The owner ruling (D2) asked first for another way to judge such a commit. There is none
    # that reaches the surface this gate protects: vault-sync feeds note CONTENT to
    # public.memories, and a message-only amend, an --allow-empty commit or a deletion-only commit
    # adds no content; an amend with nothing staged keeps HEAD's tree, which was scanned when it
    # was committed. The commit message never reaches public.memories.
    # ZERO-INPUT-OK: such a commit stages no content that could hold a secret (message-only amend, --allow-empty, deletion-only)
    echo "$TAG: $TOP: 0 staged path(s) examined — ZERO-INPUT-OK: such a commit stages no content that could hold a secret (message-only amend, --allow-empty, deletion-only)" >&2
    continue
  fi

  CONFIG="$WORK/gitleaks.$i.toml"
  if ! git -C "$TOP" show HEAD:.gitleaks.toml >"$CONFIG" 2>/dev/null; then
    echo "$TAG: $TOP: no .gitleaks.toml committed at HEAD — refusing to scan on gitleaks defaults" >&2
    BLOCK=1
    continue
  fi

  RC=0
  bash "$SCAN" "$TOP" "$CONFIG" "$LIST" || RC=$?
  if [[ $RC -ne 0 ]]; then
    BLOCK=1
    if [[ $RC -ne 1 ]]; then
      echo "$TAG: $TOP: invalid scan run (exit $RC) — blocking rather than passing unchecked" >&2
    fi
  fi
done

if [[ $BLOCK -eq 1 ]]; then
  echo "Vault secret scan blocked this commit. Remove the value (store it in 1Password and reference it), or, if it is a false positive, add a one-line allowlist with a reason to .gitleaks.toml." >&2
  exit 2
fi
exit 0
