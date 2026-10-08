#!/usr/bin/env bash
# claude-settings-sync.sh — SessionStart hook: keep ~/.claude/settings.json and the private
# overlay in step, so nobody has to remember `claude-settings sync` after /config or /model.
#
# On every session start:
#   1. Fast path: if live settings.json, the base and the overlay are byte-identical to the last
#      successful sync, exit immediately (session starts are frequent; this is a few cksums).
#   2. Otherwise run `claude-settings sync` — absorbs changes Claude made last session into the
#      private overlay, and applies base/overlay changes pulled since.
#   3. If it absorbed something, commit just the overlay in the memory vault and push it in the
#      background (only when the branch has an upstream). Set CLAUDE_SETTINGS_AUTOCOMMIT=0 to
#      leave committing to you.
#   4. If sync refuses (a lossy change or a conflict), change nothing and surface one warning to
#      the user and the session. It keeps warning each session until resolved.
#   5. If the vault's secret-scan git hooks refuse the overlay commit (LAB-2857), unstage the overlay
#      so the staged value cannot wedge every later vault commit, and warn with the file and rule id
#      only. The overlay stays modified, uncommitted, in the vault.
#
# Before the fast path it also runs `install-vault-hooks.sh --check` (a few cmp calls) and warns,
# every session until fixed, when the vault's pre-commit/pre-push hooks are missing or outdated or
# gitleaks is absent. It only reads: installing is claude/install.sh's job.
#
# Never blocks a session: always exits 0. CLAUDE_SETTINGS_SYNC=0 disables it entirely.
# Log: ${XDG_STATE_HOME:-~/.local/state}/dotfiles/claude-settings-sync.log
set -uo pipefail

[ "${CLAUDE_SETTINGS_SYNC:-1}" = "0" ] && exit 0

# Find the package from wherever Claude runs this: ~/.claude/hooks is a symlink to claude/hooks,
# so resolve the script's directory PHYSICALLY (cd -P) before stepping up — a logical `..` would
# land in ~/.claude. The loop also handles the script itself being a per-file link.
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
    target="$(readlink "$self")"
    case "$target" in
        /*) self="$target" ;;
        *)  self="$(dirname "$self")/$target" ;;
    esac
done
PKG_DIR="$(cd -P "$(dirname "$self")" && cd .. && pwd -P)"
SETTINGS_CMD="$PKG_DIR/scripts/claude-settings"
if [ ! -x "$SETTINGS_CMD" ]; then
    # Never die silently: a sync hook that quietly stops syncing is the failure this exists to prevent.
    printf '{"systemMessage": "Claude settings sync hook could not find claude-settings next to %s — settings are not being synced. Re-run ~/Repositories/dotfiles/claude/install.sh."}\n' "$self"
    exit 0
fi

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
LIVE="$CLAUDE_DIR/settings.json"
BASE="${CLAUDE_SETTINGS_BASE:-$PKG_DIR/settings.base.json}"
VAULT="${MEMORY_VAULT_PATH:-$HOME/Repositories/memory}"
OVERLAY="${CLAUDE_SETTINGS_OVERLAY:-$VAULT/personal/claude/settings.overlay.json}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
STAMP="$STATE_DIR/claude-settings-sync.stamp"
LOCK="$STATE_DIR/claude-settings-sync.lock"
LOG="$STATE_DIR/claude-settings-sync.log"

mkdir -p "$STATE_DIR" 2>/dev/null || exit 0

# Warnings are collected and emitted once, as ONE JSON object, on the way out.
WARNINGS=""
add_warning() { WARNINGS="${WARNINGS:+$WARNINGS }$1"; }
emit() {
    [ -n "$WARNINGS" ] || return 0
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg m "$WARNINGS" \
            '{systemMessage: $m, hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $m}}'
    else
        printf '%s\n' "$WARNINGS"
    fi
}
finish() { emit; exit 0; }

# A refused overlay commit (below) leaves a marker, so the warning repeats every session, fast path
# included, until the overlay is committed or reverted, instead of being reported once and forgotten.
REFUSED="$STATE_DIR/claude-settings-sync.refused"
if [ -f "$REFUSED" ]; then
    refused_rel="$(cat "$REFUSED" 2>/dev/null)"
    if [ -n "$refused_rel" ] && [ -n "$(git -C "$VAULT" status --porcelain -- "$refused_rel" 2>/dev/null)" ]; then
        add_warning "$refused_rel in the vault still holds a change its secret scan refused to commit; remove the value, then commit it. Details: $LOG"
    else
        rm -f "$REFUSED"
    fi
fi

VAULT_HOOKS="$PKG_DIR/scripts/install-vault-hooks.sh"
if [ -f "$VAULT_HOOKS" ] && ! hooks_out="$(bash "$VAULT_HOOKS" --check "$VAULT" 2>&1)"; then
    add_warning "Memory vault secret-scan git hooks need attention: $(printf '%s' "$hooks_out" | sed 's/^ *! //' | tr '\n' ' ')"
fi

signature() {
    local f
    for f in "$LIVE" "$BASE" "$OVERLAY"; do
        if [ -f "$f" ]; then cksum < "$f"; else echo missing; fi
    done
}

[ -f "$STAMP" ] && [ "$(signature)" = "$(cat "$STAMP" 2>/dev/null)" ] && finish

# One sync at a time across concurrently starting sessions; recover a lock left by a crash.
if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +2 2>/dev/null)" ]; then
        rmdir "$LOCK" 2>/dev/null
        mkdir "$LOCK" 2>/dev/null || finish
    else
        finish
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG"; }

output="$("$SETTINGS_CMD" sync 2>&1)"
rc=$?
log "sync rc=$rc: $(printf '%s' "$output" | tr '\n' ' ')"

if [ "$rc" -ne 0 ]; then
    reason="$(printf '%s\n' "$output" | grep -E '^claude-settings: ' | grep -v 'warning:' | tail -1)"
    add_warning "Claude settings sync needs attention — ~/.claude/settings.json was left as-is. ${reason:-See $LOG.} Inspect with: ~/Repositories/dotfiles/claude/scripts/claude-settings diff"
    finish
fi

case "$output" in
    *"absorbed live changes"*)
        if [ "${CLAUDE_SETTINGS_AUTOCOMMIT:-1}" != "0" ] && git -C "$VAULT" rev-parse --git-dir >/dev/null 2>&1; then
            case "$OVERLAY" in
                "$VAULT"/*)
                    rel="${OVERLAY#"$VAULT"/}"
                    if git -C "$VAULT" add -- "$rel" 2>>"$LOG" &&
                        ! git -C "$VAULT" diff --cached --quiet -- "$rel"; then
                        if commit_out="$(git -C "$VAULT" commit -q \
                            -m "chore: absorb Claude Code settings changes ($(hostname -s 2>/dev/null || echo host))" \
                            -- "$rel" 2>&1)"; then
                            printf '%s\n' "$commit_out" >>"$LOG"
                            log "committed $rel in $VAULT"
                            if git -C "$VAULT" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
                                nohup git -C "$VAULT" push -q >>"$LOG" 2>&1 &
                            fi
                        else
                            # A refused commit (the vault's secret-scan hook, LAB-2857) leaves the
                            # overlay staged in the real index, where every later commit from this
                            # checkout would pick it up and be refused too. Unstage it.
                            printf '%s\n' "$commit_out" >>"$LOG"
                            git -C "$VAULT" reset -q -- "$rel" 2>>"$LOG"
                            log "commit of $rel refused; unstaged"
                            printf '%s\n' "$rel" >"$REFUSED"
                            rules="$(printf '%s\n' "$commit_out" | sed -n 's/.* — rule \([A-Za-z0-9_.-]*\)$/\1/p' | sort -u | tr '\n' ' ')"
                            add_warning "The vault refused to commit $rel${rules:+ (gitleaks rule: ${rules% })}; it was left uncommitted and unstaged. Remove the value from the overlay, then commit it. Details: $LOG"
                        fi
                    fi
                    ;;
            esac
        fi
        ;;
esac

signature > "$STAMP"
finish
