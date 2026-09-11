#!/usr/bin/env bash
# Single-quoted "$1" and jq $vars are passed to child shells / jq on purpose.
# shellcheck disable=SC2016
# install.test.sh — exercises claude/install.sh and scripts/claude-settings against a fake HOME.
# Never touches the real ~/.claude, vault, or state. Run: bash claude/tests/install.test.sh
set -uo pipefail

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/claude-install-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export CLAUDE_CONFIG_DIR="$HOME/.claude"
export MEMORY_VAULT_PATH="$T/vault"
export XDG_STATE_HOME="$T/state"
export CLAUDE_BACKUP_DIR="$T/backup"
unset CLAUDE_SETTINGS_OVERLAY CLAUDE_SETTINGS_BASE DOTFILES_DENYLIST
mkdir -p "$HOME"

C="$CLAUDE_CONFIG_DIR"
S="$C/settings.json"
OVL="$MEMORY_VAULT_PATH/personal/claude/settings.overlay.json"
LASTGEN="$XDG_STATE_HOME/dotfiles/claude-settings.lastgen.json"
INSTALL="$PKG/install.sh"
SETTINGS="$PKG/scripts/claude-settings"

pass=0; failed=0
ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { failed=$((failed + 1)); printf '  FAIL %s\n' "$1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
quiet() { "$@" >/dev/null 2>&1; }
section() { printf '\n%s\n' "$1"; }
canon() { jq -S 'walk(if type == "array" then sort else . end)' "$1"; }
# set_json <file> <jq args...>: edit in place (keeps the inode, mode and regular-file type)
set_json() { local f="$1" tmp; shift; tmp="$(mktemp)"; jq "$@" "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"; }

skills=("$PKG"/skills/*/)
agents=("$PKG"/agents/*.md)
first_skill="$(basename "${skills[0]}")"
first_agent="$(basename "${agents[0]}")"
base_allow0="$(jq -r '.permissions.allow[0]' "$PKG/settings.base.json")"

all_links_ok() {
    local f n
    for f in "$PKG"/agents/*.md "$PKG"/commands/*.md "$PKG"/rules/*.md; do
        n="$(basename "$(dirname "$f")")/$(basename "$f")"
        [ -L "$C/$n" ] && [ "$(readlink "$C/$n")" = "$f" ] || { echo "    bad link: $n"; return 1; }
    done
    for f in "$PKG"/hooks/*; do
        [ "$(readlink "$C/hooks/$(basename "$f")")" = "$f" ] || { echo "    bad hook link: $f"; return 1; }
    done
    for f in "$PKG"/skills/*/; do
        n="$(basename "$f")"
        [ "$(readlink "$C/skills/$n")" = "$PKG/skills/$n" ] || { echo "    bad skill link: $n"; return 1; }
    done
    [ "$(readlink "$C/statusline-command.sh")" = "$PKG/statusline-command.sh" ]
}
regular_600() { [ -f "$1" ] && [ ! -L "$1" ] && [ "$(stat -f '%Lp' "$1")" = "600" ]; }

section "fresh install, no vault"
out="$("$INSTALL" 2>"$T/err")"; rc=$?
check "exit 0" [ "$rc" -eq 0 ]
check "every managed item linked to the package" all_links_ok
check "settings.json is a regular file, mode 600" regular_600 "$S"
check "settings.json equals the base" [ "$(canon "$S")" = "$(canon "$PKG/settings.base.json")" ]
check "generation recorded" [ -f "$LASTGEN" ]
check "warns that the overlay is missing" grep -q 'no private overlay' "$T/err"

section "idempotence"
mtime="$(stat -f '%m' "$S")"
sleep 1
out="$("$INSTALL" 2>/dev/null)"
check "second run changes nothing" grep -q '^changed: 0$' <<<"$out"
check "settings.json not rewritten" [ "$(stat -f '%m' "$S")" = "$mtime" ]
check "--status healthy" quiet "$INSTALL" --status

section "a real directory shadowing a managed skill"
rm "$C/skills/$first_skill"; mkdir "$C/skills/$first_skill"; echo marker > "$C/skills/$first_skill/MARKER"
check "--status reports it" bash -c '! "$1" --status >/dev/null 2>&1' _ "$INSTALL"
"$INSTALL" >/dev/null 2>&1
check "relinked" [ "$(readlink "$C/skills/$first_skill")" = "$PKG/skills/$first_skill" ]
check "original backed up OUTSIDE ~/.claude" [ -n "$(find "$CLAUDE_BACKUP_DIR" -name MARKER 2>/dev/null)" ]
check "no backup copy left inside ~/.claude" [ -z "$(find "$C" -name MARKER 2>/dev/null)" ]
check "no link nested inside the package" [ ! -e "$PKG/skills/$first_skill/$first_skill" ]

section "a differing real file at a managed path"
rm "$C/agents/$first_agent"; echo "local edit" > "$C/agents/$first_agent"
"$INSTALL" >/dev/null 2>&1
check "relinked" [ "$(readlink "$C/agents/$first_agent")" = "$PKG/agents/$first_agent" ]
check "differing file backed up" grep -rqs 'local edit' "$CLAUDE_BACKUP_DIR"

section "pruning and unmanaged items"
ln -s "$PKG/skills/zz-removed-skill" "$C/skills/zz-removed-skill"
mkdir -p "$C/skills/third-party-x" && echo keep > "$C/skills/third-party-x/SKILL.md"
ln -s "$T" "$C/skills/foreign-link"
"$INSTALL" >/dev/null 2>&1
check "dangling link into the package pruned" [ ! -L "$C/skills/zz-removed-skill" ]
check "unmanaged real skill untouched" [ -f "$C/skills/third-party-x/SKILL.md" ]
check "foreign symlink untouched" [ -L "$C/skills/foreign-link" ]

section "dry run changes nothing"
rm "$C/agents/$first_agent"
out="$("$INSTALL" --dry-run 2>/dev/null)"
check "reports the pending link" grep -q "would: link $C/agents/$first_agent" <<<"$out"
check "link still missing" [ ! -e "$C/agents/$first_agent" ]
"$INSTALL" >/dev/null 2>&1

section "overlay merges with array union"
mkdir -p "$(dirname "$OVL")"
printf '%s\n' '{"autoMode":{"environment":["private fact"]},"permissions":{"allow":["Bash(extra:*)"]}}' > "$OVL"
"$INSTALL" >/dev/null 2>&1; rc=$?
check "install exit 0" [ "$rc" -eq 0 ]
check "overlay key present" [ "$(jq -r '.autoMode.environment[0]' "$S")" = "private fact" ]
check "overlay array item added" quiet jq -e '.permissions.allow | index("Bash(extra:*)")' "$S"
check "base array items kept" quiet jq -e --arg a "$base_allow0" '.permissions.allow | index($a)' "$S"
check "no overlay warning once present" bash -c '! "$1" status 2>&1 | grep -q "no private overlay"' _ "$SETTINGS"

section "drift Claude made is absorbed into the overlay"
set_json "$S" '.theme = "light-test"'
"$SETTINGS" sync >/dev/null 2>&1; rc=$?
check "sync exit 0" [ "$rc" -eq 0 ]
check "overlay records the change" [ "$(jq -r '.theme' "$OVL")" = "light-test" ]
check "overlay keeps its private keys" [ "$(jq -r '.autoMode.environment[0]' "$OVL")" = "private fact" ]
check "settings.json still a regular 600 file" regular_600 "$S"
check "status clean" quiet "$SETTINGS" status

section "lossy drift is refused"
cp "$OVL" "$T/ovl.before"
set_json "$S" --arg a "$base_allow0" '.permissions.allow -= [$a]'
cp "$S" "$T/live.before"
check "sync refuses" bash -c '! "$1" sync >/dev/null 2>&1' _ "$SETTINGS"
check "live left untouched" cmp -s "$S" "$T/live.before"
check "overlay left untouched" cmp -s "$OVL" "$T/ovl.before"
"$SETTINGS" apply --force >/dev/null 2>&1
check "apply --force restores the base entry" quiet jq -e --arg a "$base_allow0" '.permissions.allow | index($a)' "$S"
check "apply --force backed up the discarded live file" [ -n "$(find "$CLAUDE_BACKUP_DIR" -name settings.json)" ]

section "drift plus a changed overlay is a conflict"
set_json "$S" '.theme = "conflict-live"'
set_json "$OVL" '.tui = "conflict-overlay"'
out="$("$SETTINGS" sync 2>&1)"; rc=$?
check "sync refuses" [ "$rc" -ne 0 ]
check "names the conflict" grep -qi conflict <<<"$out"
check "status reports CONFLICT" bash -c '"$1" status 2>/dev/null | grep -q CONFLICT' _ "$SETTINGS"
"$SETTINGS" apply --force >/dev/null 2>&1

section "live file with no generation record"
rm -f "$LASTGEN"
set_json "$S" '.theme = "pre-existing"'
check "sync refuses to guess" bash -c '! "$1" sync >/dev/null 2>&1' _ "$SETTINGS"
check "live untouched" [ "$(jq -r .theme "$S")" = "pre-existing" ]
"$SETTINGS" apply --force >/dev/null 2>&1
generated_and_recorded() {
    [ -f "$LASTGEN" ] &&
        [ "$(canon "$S")" = "$("$SETTINGS" merged 2>/dev/null | jq -S 'walk(if type == "array" then sort else . end)')" ]
}
check "apply --force generates and records" generated_and_recorded

section "materialize and relink"
"$INSTALL" --materialize >/dev/null 2>&1
check "skill is now a real directory" bash -c '[ -d "$1" ] && [ ! -L "$1" ]' _ "$C/skills/$first_skill"
check "copy matches the package" diff -rq "$C/skills/$first_skill" "$PKG/skills/$first_skill"
check "agent is now a real file" bash -c '[ -f "$1" ] && [ ! -L "$1" ]' _ "$C/agents/$first_agent"
"$INSTALL" >/dev/null 2>&1
check "plain install relinks everything" all_links_ok

section "refuses a symlinked container directory"
mv "$C/rules" "$T/rules-real" && ln -s "$T/rules-real" "$C/rules"
check "install exits non-zero" bash -c '! "$1" >/dev/null 2>&1' _ "$INSTALL"
rm "$C/rules" && mv "$T/rules-real" "$C/rules"

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
